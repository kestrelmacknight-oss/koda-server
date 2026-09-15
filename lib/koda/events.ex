defmodule Koda.Events do
  @moduledoc """
  Calendar events, including recurrence expansion and (for events linked
  to a stage channel) paid tickets.

  A `ServerEvent` row is a *series*, not a single occurrence: `channel_id`
  is which calendar it's filed under, `recurrence` says how it repeats,
  and `start_at`/`end_at` describe the *first* occurrence only. Listing
  events for a date range expands each series into the individual
  occurrences that actually fall in that range -- see occurrence_starts/3
  -- so a "weekly" event genuinely recurs instead of only ever appearing
  on the date it was created.

  Subscriptions and tickets are both at the series level (subscribe/buy
  once, it applies to every occurrence), matching how a recurring event
  is normally thought of as one ongoing thing rather than many.
  """
  import Ecto.Query
  alias Koda.Repo

  defmodule ServerEvent do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id
    schema "server_events" do
      field :channel_id,       :binary_id
      field :server_id,        :binary_id
      field :created_by,       :binary_id
      field :title,            :string
      field :description,      :string
      field :location,         :string
      field :start_at,         :utc_datetime_usec
      field :end_at,           :utc_datetime_usec
      field :recurrence,       :string, default: "none"
      field :color,            :string, default: "#2DD4A0"
      field :price_cents,      :integer, default: 0
      field :stage_channel_id, :binary_id
      timestamps(type: :utc_datetime_usec)
    end
    def changeset(e, attrs) do
      e |> cast(attrs, [:channel_id, :server_id, :created_by, :title,
                        :description, :location, :start_at, :end_at,
                        :recurrence, :color, :price_cents, :stage_channel_id])
        |> validate_required([:channel_id, :server_id, :title, :start_at])
        |> validate_inclusion(:recurrence, ["none","daily","weekly","monthly"])
        |> validate_number(:price_cents, greater_than_or_equal_to: 0)
    end
  end

  defmodule EventSubscription do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id
    schema "event_subscriptions" do
      field :event_id, :binary_id
      field :user_id,  :binary_id
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end
    def changeset(s, attrs) do
      s |> cast(attrs, [:event_id, :user_id])
        |> validate_required([:event_id, :user_id])
        |> unique_constraint([:event_id, :user_id])
    end
  end

  defmodule EventTicket do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id
    schema "event_tickets" do
      field :event_id,                 :binary_id
      field :buyer_id,                 :binary_id
      field :amount_cents,             :integer
      field :fee_cents,                :integer, default: 0
      field :stripe_payment_intent_id, :string
      field :status,                   :string, default: "pending"
      timestamps(type: :utc_datetime_usec)
    end
    def changeset(t, attrs) do
      t |> cast(attrs, [:event_id, :buyer_id, :amount_cents, :fee_cents,
                        :stripe_payment_intent_id, :status])
        |> validate_required([:event_id, :buyer_id, :amount_cents])
    end
  end

  # ── Event CRUD ───────────────────────────────────────────────────────────

  @doc """
  Occurrences of every series on `channel_id` that fall within
  `[from, to]` (both optional; default to a 3-month-back/9-month-forward
  window when omitted, generous enough for a client that isn't yet
  range-aware without silently truncating a long-running recurring
  event). Each occurrence is its own JSON map with its own computed
  start_at/end_at; `id` is shared across every occurrence of the same
  series (subscribe/unsubscribe and ticket checks are series-level).
  """
  def list_events(channel_id, opts \\ []) do
    now  = DateTime.utc_now()
    from = Keyword.get(opts, :from) || DateTime.add(now, -90 * 86400, :second)
    to   = Keyword.get(opts, :to)   || DateTime.add(now, 270 * 86400, :second)

    Repo.all(from e in ServerEvent, where: e.channel_id == ^channel_id)
    |> Enum.flat_map(&expand_occurrences(&1, from, to))
    |> Enum.sort_by(& &1.start_at, DateTime)
  end

  @doc "The stored series row itself (not occurrence-expanded)."
  def get_event(id), do: Repo.get(ServerEvent, id)

  def create_event(attrs) do
    %ServerEvent{} |> ServerEvent.changeset(attrs) |> Repo.insert()
  end

  def update_event(event, attrs) do
    event |> ServerEvent.changeset(attrs) |> Repo.update()
  end

  def delete_event(event), do: Repo.delete(event)

  def subscribe(event_id, user_id) do
    %EventSubscription{}
    |> EventSubscription.changeset(%{event_id: event_id, user_id: user_id})
    |> Repo.insert(on_conflict: :nothing)
  end

  def unsubscribe(event_id, user_id) do
    Repo.delete_all(from s in EventSubscription,
      where: s.event_id == ^event_id and s.user_id == ^user_id)
  end

  def subscribed?(event_id, user_id) do
    Repo.exists?(from s in EventSubscription,
      where: s.event_id == ^event_id and s.user_id == ^user_id)
  end

  def subscriber_ids(event_id) do
    Repo.all(from s in EventSubscription,
      where: s.event_id == ^event_id,
      select: s.user_id)
  end

  def event_json(e, occurrence_start \\ nil, occurrence_end \\ nil) do
    %{
      id:               e.id,
      channel_id:       e.channel_id,
      server_id:        e.server_id,
      created_by:       e.created_by,
      title:            e.title,
      description:      e.description,
      location:         e.location,
      start_at:         DateTime.to_iso8601(occurrence_start || e.start_at),
      end_at:           (occurrence_end || e.end_at) && DateTime.to_iso8601(occurrence_end || e.end_at),
      recurrence:       e.recurrence,
      color:            e.color,
      price_cents:      e.price_cents,
      stage_channel_id: e.stage_channel_id
    }
  end

  # ── Recurrence expansion ─────────────────────────────────────────────────

  # Safety cap so a years-old daily event can't force generating (or
  # anyone from requesting) an unbounded number of occurrences in one
  # call -- 1000 steps covers ~2.7 years of daily recurrence, which is
  # already far more than any single list_events window needs.
  @max_occurrence_steps 1000

  defp expand_occurrences(%ServerEvent{recurrence: "none"} = e, from, to) do
    if in_range?(e.start_at, e.end_at, from, to), do: [event_json(e)], else: []
  end

  defp expand_occurrences(%ServerEvent{} = e, from, to) do
    duration = occurrence_duration(e)

    occurrence_starts(e.start_at, e.recurrence, from, to)
    |> Enum.map(fn occ_start ->
      occ_end = e.end_at && DateTime.add(occ_start, duration, :second)
      event_json(e, occ_start, occ_end)
    end)
  end

  defp in_range?(start_at, end_at, from, to) do
    effective_end = end_at || start_at
    DateTime.compare(effective_end, from) != :lt and DateTime.compare(start_at, to) != :gt
  end

  defp occurrence_duration(%{end_at: nil}), do: 0
  defp occurrence_duration(%{start_at: s, end_at: e}), do: DateTime.diff(e, s)

  @doc """
  Every occurrence start time of a `first_start`/`recurrence` series
  that falls within `[from, to]`. Exposed (not private) so both
  list_events/2 and current_ticketed_event/1 share one implementation
  of "what are this series' occurrences" rather than two subtly
  different ones.

  For daily/weekly (a fixed-length step), this jumps directly to the
  first occurrence at or after `from` via exact arithmetic rather than
  walking forward one step at a time from the series' original start --
  a daily event running for a few years would otherwise need thousands
  of steps just to reach a `from` far in its future, exceeding
  @max_occurrence_steps before ever producing a real answer. Monthly
  has no fixed step length (months vary), but even a 1000-step cap
  covers over 80 years of monthly recurrence, so it isn't worth the
  same estimate-and-correct complexity.
  """
  def occurrence_starts(first_start, recurrence, from, to) do
    cond do
      DateTime.compare(first_start, to) == :gt ->
        []

      recurrence == "daily" ->
        walk_fixed_step(anchor_at_or_after(first_start, 86400, from), 86400, from, to, 0, [])

      recurrence == "weekly" ->
        walk_fixed_step(anchor_at_or_after(first_start, 7 * 86400, from), 7 * 86400, from, to, 0, [])

      recurrence == "monthly" ->
        walk_monthly(first_start, from, to, 0, [])

      true ->
        []
    end
  end

  # The first occurrence of a fixed-length-step series at or after
  # `from`, found by exact division rather than iterating -- correct
  # regardless of how far `first_start` is in the past.
  defp anchor_at_or_after(first_start, step_seconds, from) do
    diff = DateTime.diff(from, first_start)
    steps = if diff <= 0, do: 0, else: div(diff, step_seconds)
    candidate = DateTime.add(first_start, steps * step_seconds, :second)
    if DateTime.compare(candidate, from) == :lt,
      do: DateTime.add(candidate, step_seconds, :second),
      else: candidate
  end

  defp walk_fixed_step(_current, _step, _from, _to, count, acc) when count >= @max_occurrence_steps,
    do: Enum.reverse(acc)
  defp walk_fixed_step(current, step_seconds, from, to, count, acc) do
    cond do
      DateTime.compare(current, to) == :gt ->
        Enum.reverse(acc)
      DateTime.compare(current, from) != :lt ->
        walk_fixed_step(DateTime.add(current, step_seconds, :second), step_seconds, from, to, count + 1, [current | acc])
      true ->
        walk_fixed_step(DateTime.add(current, step_seconds, :second), step_seconds, from, to, count + 1, acc)
    end
  end

  defp walk_monthly(_current, _from, _to, count, acc) when count >= @max_occurrence_steps,
    do: Enum.reverse(acc)
  defp walk_monthly(current, from, to, count, acc) do
    cond do
      DateTime.compare(current, to) == :gt ->
        Enum.reverse(acc)
      DateTime.compare(current, from) != :lt ->
        walk_monthly(shift_months(current, 1), from, to, count + 1, [current | acc])
      true ->
        walk_monthly(shift_months(current, 1), from, to, count + 1, acc)
    end
  end

  # Calendar-correct month shift (Jan 31 + 1 month -> Feb 28/29, not an
  # invalid date or a silently-wrong day) -- plain DateTime.add/3 can't
  # do this since a month isn't a fixed number of seconds.
  defp shift_months(%DateTime{} = dt, n) do
    total = dt.month - 1 + n
    new_year  = dt.year + div(total, 12)
    new_month = rem(total, 12) + 1
    last_day  = :calendar.last_day_of_the_month(new_year, new_month)
    %{dt | year: new_year, month: new_month, day: min(dt.day, last_day)}
  end

  # ── Stage ticket gating ──────────────────────────────────────────────────

  # How early a ticket-holder (or the room generally, once free) may
  # join before the scheduled start.
  @join_grace_seconds 15 * 60
  # Assumed length of an occurrence with no explicit end_at, purely for
  # deciding how long the ticket gate stays "live" after start.
  @default_occurrence_seconds 2 * 60 * 60

  @doc """
  The priced event currently "live" (within its join window) for a
  stage channel, if any -- i.e. what stage_controller.join/2 should
  require a ticket for. Series-aware: a recurring ticketed event is
  live during *any* of its occurrences' windows, not only its first.
  """
  def current_ticketed_event(stage_channel_id) do
    now = DateTime.utc_now()
    window_from = DateTime.add(now, -@default_occurrence_seconds, :second)
    window_to   = DateTime.add(now, @join_grace_seconds, :second)

    Repo.all(
      from e in ServerEvent,
      where: e.stage_channel_id == ^stage_channel_id and e.price_cents > 0
    )
    |> Enum.find(fn event -> occurrence_live_now?(event, now, window_from, window_to) end)
  end

  defp occurrence_live_now?(%ServerEvent{recurrence: "none"} = e, now, _wf, _wt) do
    occurrence_window_contains?(e.start_at, occurrence_duration_or_default(e), now)
  end
  defp occurrence_live_now?(%ServerEvent{} = e, now, window_from, window_to) do
    duration = occurrence_duration_or_default(e)
    e.start_at
    |> occurrence_starts(e.recurrence, window_from, window_to)
    |> Enum.any?(&occurrence_window_contains?(&1, duration, now))
  end

  defp occurrence_duration_or_default(%{end_at: nil}), do: @default_occurrence_seconds
  defp occurrence_duration_or_default(%{start_at: s, end_at: e}), do: max(DateTime.diff(e, s), 0)

  defp occurrence_window_contains?(occ_start, duration, now) do
    join_opens  = DateTime.add(occ_start, -@join_grace_seconds, :second)
    occ_ends    = DateTime.add(occ_start, duration, :second)
    DateTime.compare(now, join_opens) != :lt and DateTime.compare(now, occ_ends) != :gt
  end

  # ── Tickets ──────────────────────────────────────────────────────────────

  def has_ticket?(event_id, user_id) do
    Repo.exists?(from t in EventTicket,
      where: t.event_id == ^event_id and t.buyer_id == ^user_id and t.status == "complete")
  end

  def create_ticket_intent(event_id, buyer_id) do
    case get_event(event_id) do
      nil -> {:error, :event_not_found}
      event ->
        cond do
          has_ticket?(event_id, buyer_id) ->
            {:error, :already_has_ticket}

          event.price_cents == 0 ->
            complete_free_ticket(event, buyer_id)

          true ->
            server = Koda.Servers.get_server(event.server_id)
            connect_acct = server && Koda.Marketplace.get_connect_account(server.owner_id)

            cond do
              is_nil(connect_acct) ->
                {:error, :owner_not_connected}

              not connect_acct.charges_enabled ->
                {:error, :owner_not_onboarded}

              true ->
                stripe_key = Application.get_env(:koda, :stripe_secret_key)
                fee_cents = round(event.price_cents * 0.05)
                # 95% to the server owner via Connect, 5% stays as
                # Koda's platform fee -- confirm_ticket/1's server-bank
                # points credit (unchanged) is a separate symbolic
                # number layered on that same 5%, not money moved twice.
                owner_amount_cents = event.price_cents - fee_cents

                case Stripe.Checkout.Session.create(%{
                  mode: :payment,
                  line_items: [%{
                    price_data: %{
                      currency: "usd",
                      product_data: %{name: "Ticket: #{event.title}"},
                      unit_amount: event.price_cents
                    },
                    quantity: 1
                  }],
                  payment_intent_data: %{
                    transfer_data: %{
                      destination: connect_acct.stripe_account_id,
                      amount:       owner_amount_cents
                    },
                    metadata: %{type: "stage_ticket", event_id: event_id, buyer_id: buyer_id}
                  },
                  success_url: Koda.Marketplace.checkout_success_url(),
                  cancel_url:  Koda.Marketplace.checkout_cancel_url()
                }, api_key: stripe_key) do
                  {:ok, session} ->
                    {:ok, ticket} = %EventTicket{}
                    |> EventTicket.changeset(%{
                      event_id:                 event_id,
                      buyer_id:                 buyer_id,
                      amount_cents:             event.price_cents,
                      fee_cents:                fee_cents,
                      stripe_payment_intent_id: session.payment_intent,
                      status:                   "pending"
                    })
                    |> Repo.insert()
                    {:ok, %{ticket: ticket, checkout_url: session.url, free: false}}
                  {:error, err} -> {:error, err}
                end
            end
        end
    end
  end

  defp complete_free_ticket(event, buyer_id) do
    {:ok, ticket} = %EventTicket{}
    |> EventTicket.changeset(%{event_id: event.id, buyer_id: buyer_id, amount_cents: 0, status: "complete"})
    |> Repo.insert()
    {:ok, %{ticket: ticket, free: true}}
  end

  def confirm_ticket(stripe_payment_intent_id) do
    case Repo.get_by(EventTicket, stripe_payment_intent_id: stripe_payment_intent_id) do
      nil -> {:error, :not_found}
      ticket ->
        {:ok, updated} = ticket
        |> EventTicket.changeset(%{status: "complete"})
        |> Repo.update()

        event = get_event(updated.event_id)
        if event && updated.fee_cents > 0 do
          Koda.Marketplace.credit_server_bank(event.server_id, updated.fee_cents, "stage_ticket", updated.id)
        end

        Phoenix.PubSub.broadcast(Koda.PubSub, "user:#{updated.buyer_id}",
          {:ticket_confirmed, %{event_id: updated.event_id}})
        Koda.Notifications.notify_and_push(updated.buyer_id, "payment_confirmed",
          "Ticket confirmed",
          "#{if event, do: "Your ticket for #{event.title} is confirmed.", else: "Your ticket is confirmed."}",
          %{payment_type: "stage_ticket", event_id: updated.event_id})

        {:ok, updated}
    end
  end

  def my_ticket_event_ids(user_id) do
    Repo.all(from t in EventTicket,
      where: t.buyer_id == ^user_id and t.status == "complete",
      select: t.event_id)
  end
end
