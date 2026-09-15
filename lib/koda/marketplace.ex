defmodule Koda.Marketplace do
  @moduledoc """
  Handles tips, subscriptions, Stripe Connect onboarding,
  and server bank point crediting.
  """
  import Ecto.Query
  alias Koda.Repo

  @platform_fee_percent 0.05
  @spark_price_cents    500   # $5/month
  @pulse_price_cents    1000  # $10/month

  # ── Schemas ──────────────────────────────────────────────────────────────

  defmodule StripeConnectAccount do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id
    schema "stripe_connect_accounts" do
      field :user_id,             :binary_id
      field :stripe_account_id,   :string
      field :onboarding_complete, :boolean, default: false
      field :payouts_enabled,     :boolean, default: false
      field :charges_enabled,     :boolean, default: false
      field :country,             :string
      timestamps(type: :utc_datetime_usec)
    end
    def changeset(s, attrs) do
      s |> cast(attrs, [:user_id, :stripe_account_id, :onboarding_complete,
                        :payouts_enabled, :charges_enabled, :country])
        |> validate_required([:user_id, :stripe_account_id])
        |> unique_constraint(:user_id)
        |> unique_constraint(:stripe_account_id)
    end
  end

  defmodule ServerBank do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id
    schema "server_banks" do
      field :server_id,         :binary_id
      field :balance,           :integer, default: 0
      field :lifetime_received, :integer, default: 0
      timestamps(type: :utc_datetime_usec)
    end
    def changeset(b, attrs) do
      b |> cast(attrs, [:server_id, :balance, :lifetime_received])
        |> validate_required([:server_id])
    end
  end

  defmodule PointTransaction do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id
    schema "point_transactions" do
      field :server_id,    :binary_id
      field :amount,       :integer
      field :source_type,  :string
      field :source_id,    :binary_id
      field :inserted_at,  :utc_datetime_usec
    end
    def changeset(t, attrs) do
      t |> cast(attrs, [:server_id, :amount, :source_type, :source_id, :inserted_at])
        |> validate_required([:server_id, :amount, :source_type])
    end
  end

  defmodule MarketplaceTip do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id
    schema "marketplace_tips" do
      field :from_user_id,             :binary_id
      field :to_user_id,               :binary_id
      field :server_id,                :binary_id
      field :amount_cents,             :integer
      field :creator_amount_cents,     :integer
      field :fee_cents,                :integer
      field :points_credited,          :integer
      field :stripe_payment_intent_id, :string
      field :stripe_transfer_id,       :string
      field :status,                   :string, default: "pending"
      field :message,                  :string
      timestamps(type: :utc_datetime_usec)
    end
    def changeset(t, attrs) do
      t |> cast(attrs, [:from_user_id, :to_user_id, :server_id,
                        :amount_cents, :creator_amount_cents, :fee_cents,
                        :points_credited, :stripe_payment_intent_id,
                        :stripe_transfer_id, :status, :message])
        |> validate_required([:from_user_id, :to_user_id, :amount_cents])
        |> validate_number(:amount_cents, greater_than: 0)
    end
  end

  defmodule KodaSubscription do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id
    schema "koda_subscriptions" do
      field :user_id,                  :binary_id
      field :tier,                     :string
      field :server_id,                :binary_id
      field :gifted_by_user_id,        :binary_id
      field :amount_cents,             :integer
      field :stripe_payment_intent_id, :string
      field :expires_at,               :utc_datetime_usec
      field :active,                   :boolean, default: true
      timestamps(type: :utc_datetime_usec)
    end
    def changeset(s, attrs) do
      s |> cast(attrs, [:user_id, :tier, :server_id, :gifted_by_user_id,
                        :amount_cents, :stripe_payment_intent_id, :expires_at, :active])
        |> validate_required([:user_id, :tier, :amount_cents, :expires_at])
        |> validate_inclusion(:tier, ["spark", "pulse"])
    end
  end

  # ── Stripe Connect ────────────────────────────────────────────────────────

  def get_connect_account(user_id) do
    Repo.get_by(StripeConnectAccount, user_id: user_id)
  end

  def create_connect_account(user_id) do
    stripe_key = Application.get_env(:koda, :stripe_secret_key)
    case Stripe.Account.create(%{type: "express"}, api_key: stripe_key) do
      {:ok, account} ->
        %StripeConnectAccount{}
        |> StripeConnectAccount.changeset(%{
          user_id: user_id,
          stripe_account_id: account.id
        })
        |> Repo.insert()
      {:error, err} -> {:error, err}
    end
  end

  def get_onboarding_url(user_id, return_url, refresh_url) do
    stripe_key = Application.get_env(:koda, :stripe_secret_key)
    case get_connect_account(user_id) do
      nil -> {:error, :no_account}
      acct ->
        Stripe.AccountLink.create(%{
          account: acct.stripe_account_id,
          refresh_url: refresh_url,
          return_url: return_url,
          type: "account_onboarding"
        }, api_key: stripe_key)
    end
  end

  def sync_connect_account(user_id) do
    stripe_key = Application.get_env(:koda, :stripe_secret_key)
    case get_connect_account(user_id) do
      nil -> {:error, :no_account}
      acct ->
        # Use Stripe API directly to retrieve connected account
        url = "https://api.stripe.com/v1/accounts/#{acct.stripe_account_id}"
        headers = [{"Authorization", "Bearer #{stripe_key}"}]
        case :hackney.get(url, headers, "", [with_body: true]) do
          {:ok, 200, _headers, body} ->
            data = Jason.decode!(body)
            acct
            |> StripeConnectAccount.changeset(%{
              onboarding_complete: data["details_submitted"] || false,
              payouts_enabled:     data["payouts_enabled"] || false,
              charges_enabled:     data["charges_enabled"] || false,
              country:             data["country"]
            })
            |> Repo.update()
          {:ok, status, _, body} ->
            {:error, "Stripe returned #{status}: #{body}"}
          {:error, err} -> {:error, err}
        end
    end
  end

  # ── Tips ──────────────────────────────────────────────────────────────────

  def calculate_tip(amount_cents) do
    # Tips go 100% to creator — Stripe takes their standard fee automatically
    %{
      amount_cents:         amount_cents,
      creator_amount_cents: amount_cents,
      fee_cents:            0,
      points_credited:      0
    }
  end

  @doc """
  Where Stripe Checkout redirects after a successful/cancelled payment.
  The app never relies on this redirect for state -- confirmation flows
  entirely through the webhook + a push notification to the buyer's own
  client (Koda.Notifications.notify_and_push/5), since desktop has no
  way to deep-link back into the app. A plain page is enough here;
  dedicated confirmation pages on koda.fyi would just be UX polish.
  """
  def checkout_success_url, do: "https://koda.fyi/?payment=success"
  def checkout_cancel_url,  do: "https://koda.fyi/?payment=cancelled"

  def create_tip_payment_intent(from_user_id, to_user_id, server_id, amount_cents, message \\ nil) do
    stripe_key = Application.get_env(:koda, :stripe_secret_key)
    calc = calculate_tip(amount_cents)

    # Get creator's Connect account
    case get_connect_account(to_user_id) do
      nil -> {:error, :creator_not_connected}
      connect_acct ->
        unless connect_acct.charges_enabled do
          {:error, :creator_not_onboarded}
        else
          # A Checkout Session (not a bare PaymentIntent) since desktop --
          # this app's actual primary platform -- has no native Stripe
          # SDK; the client opens session.url in the system browser and
          # Stripe hosts the entire card-entry UI. payment_intent_data
          # carries the same transfer_data/metadata a direct
          # PaymentIntent.create would have, so the underlying
          # PaymentIntent this session creates immediately (session.payment_intent)
          # is indistinguishable to confirm_tip/1 and the webhook handler
          # below from one created the old way -- neither needed to change.
          case Stripe.Checkout.Session.create(%{
            mode: :payment,
            line_items: [%{
              price_data: %{
                currency: "usd",
                product_data: %{name: "Tip"},
                unit_amount: amount_cents
              },
              quantity: 1
            }],
            payment_intent_data: %{
              transfer_data: %{
                destination: connect_acct.stripe_account_id,
                amount:       amount_cents
              },
              metadata: %{
                from_user_id: from_user_id,
                to_user_id:   to_user_id,
                server_id:    server_id || "",
                type:         "tip"
              }
            },
            success_url: checkout_success_url(),
            cancel_url:  checkout_cancel_url()
          }, api_key: stripe_key) do
            {:ok, session} ->
              # Create pending tip record
              {:ok, tip} = %MarketplaceTip{}
              |> MarketplaceTip.changeset(Map.merge(calc, %{
                from_user_id:             from_user_id,
                to_user_id:               to_user_id,
                server_id:                server_id,
                stripe_payment_intent_id: session.payment_intent,
                status:                   "pending",
                message:                  message
              }))
              |> Repo.insert()
              {:ok, %{tip: tip, checkout_url: session.url}}
            {:error, err} -> {:error, err}
          end
        end
    end
  end

  def confirm_tip(stripe_payment_intent_id) do
    case Repo.get_by(MarketplaceTip, stripe_payment_intent_id: stripe_payment_intent_id) do
      nil -> {:error, :not_found}
      tip ->
        tip
        |> MarketplaceTip.changeset(%{status: "complete"})
        |> Repo.update()
        |> case do
          {:ok, updated_tip} ->
            # Credit server bank
            if updated_tip.server_id do
              credit_server_bank(updated_tip.server_id, updated_tip.points_credited,
                "tip", updated_tip.id)
            end
            # Tell the tipper's own client their Checkout tab is done --
            # the app has no other way to know without this, since it
            # can't poll Stripe or receive a deep-link callback.
            amount_str = :erlang.float_to_binary(updated_tip.amount_cents / 100, decimals: 2)
            Koda.Notifications.notify_and_push(updated_tip.from_user_id, "payment_confirmed",
              "Tip sent", "Your $#{amount_str} tip went through.",
              %{payment_type: "tip", tip_id: updated_tip.id})
            {:ok, updated_tip}
          err -> err
        end
    end
  end

  # ── Server Bank ──────────────────────────────────────────────────────────

  def get_or_create_server_bank(server_id) do
    case Repo.get_by(ServerBank, server_id: server_id) do
      nil ->
        %ServerBank{}
        |> ServerBank.changeset(%{server_id: server_id})
        |> Repo.insert!()
      bank -> bank
    end
  end

  def credit_server_bank(server_id, points, source_type, source_id) do
    bank = get_or_create_server_bank(server_id)
    Repo.update_all(
      from(b in ServerBank, where: b.id == ^bank.id),
      inc: [balance: points, lifetime_received: points]
    )
    %PointTransaction{}
    |> PointTransaction.changeset(%{
      server_id:   server_id,
      amount:      points,
      source_type: source_type,
      source_id:   source_id,
      inserted_at: DateTime.utc_now()
    })
    |> Repo.insert()
  end

  def get_server_bank_balance(server_id) do
    case Repo.get_by(ServerBank, server_id: server_id) do
      nil  -> 0
      bank -> bank.balance
    end
  end

  # ── Revenue reporting ────────────────────────────────────────────────────
  #
  # Every credit_server_bank/4 call already writes a PointTransaction row
  # (source_type + amount), so the revenue dashboard is read-only queries
  # over that existing ledger rather than a new tracking mechanism.

  defp transactions_query(server_id, opts) do
    query = from t in PointTransaction, where: t.server_id == ^server_id
    query = case Keyword.get(opts, :from) do
      nil -> query
      dt  -> from t in query, where: t.inserted_at >= ^dt
    end
    query = case Keyword.get(opts, :to) do
      nil -> query
      dt  -> from t in query, where: t.inserted_at <= ^dt
    end
    # :before is a strict "<" pagination cursor (the caller already has
    # the row at exactly this timestamp and wants older ones), distinct
    # from the inclusive :to bound used to close off a reporting window.
    case Keyword.get(opts, :before) do
      nil -> query
      dt  -> from t in query, where: t.inserted_at < ^dt
    end
  end

  @doc "Current balance, lifetime total, and an all-time breakdown by source_type."
  def revenue_summary(server_id) do
    bank = get_or_create_server_bank(server_id)
    %{
      balance:           bank.balance,
      lifetime_received: bank.lifetime_received,
      breakdown:         revenue_breakdown(server_id)
    }
  end

  @doc "Points earned per source_type within `opts[:from..:to]` (default: all-time)."
  def revenue_breakdown(server_id, opts \\ []) do
    server_id
    |> transactions_query(opts)
    |> group_by([t], t.source_type)
    |> select([t], %{source_type: t.source_type, total: sum(t.amount), count: count(t.id)})
    |> Repo.all()
    |> Enum.sort_by(& &1.total, :desc)
  end

  @doc """
  Points earned per calendar day over the last `days` days (default 30,
  ending today), zero-filled so a chart doesn't have to guess at gaps
  where nothing happened.
  """
  def revenue_timeseries(server_id, days \\ 30) do
    to   = DateTime.utc_now()
    from = DateTime.add(to, -(max(days, 1) - 1) * 86400, :second)

    rows =
      server_id
      |> transactions_query(from: from, to: to)
      |> group_by([t], fragment("date(?)", t.inserted_at))
      |> select([t], %{day: fragment("date(?)", t.inserted_at), total: sum(t.amount)})
      |> Repo.all()

    by_day = Map.new(rows, fn r -> {Date.to_iso8601(r.day), r.total} end)

    Date.range(DateTime.to_date(from), DateTime.to_date(to))
    |> Enum.map(fn d ->
      key = Date.to_iso8601(d)
      %{date: key, total: Map.get(by_day, key, 0)}
    end)
  end

  @doc "Most recent transactions for a server, newest first, cursor-paginated on inserted_at via opts[:before]."
  def list_transactions(server_id, opts \\ []) do
    limit = opts |> Keyword.get(:limit, 50) |> max(1) |> min(200)

    server_id
    |> transactions_query(opts)
    |> order_by([t], desc: t.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def transaction_json(t) do
    %{
      id:          t.id,
      amount:      t.amount,
      source_type: t.source_type,
      source_id:   t.source_id,
      inserted_at: DateTime.to_iso8601(t.inserted_at)
    }
  end

  # ── Subscriptions ────────────────────────────────────────────────────────

  def subscription_price(tier) do
    case tier do
      "spark" -> @spark_price_cents
      "pulse" -> @pulse_price_cents
      _       -> nil
    end
  end

  def create_subscription_payment_intent(user_id, tier, server_id, gifted_by_user_id \\ nil) do
    stripe_key = Application.get_env(:koda, :stripe_secret_key)
    amount_cents = subscription_price(tier)
    unless amount_cents do
      {:error, :invalid_tier}
    else
      case Stripe.Checkout.Session.create(%{
        mode: :payment,
        line_items: [%{
          price_data: %{
            currency: "usd",
            product_data: %{name: "Koda #{String.capitalize(tier)} subscription"},
            unit_amount: amount_cents
          },
          quantity: 1
        }],
        payment_intent_data: %{
          metadata: %{
            user_id:          user_id,
            tier:             tier,
            server_id:        server_id || "",
            gifted_by:        gifted_by_user_id || "",
            type:             "subscription"
          }
        },
        success_url: checkout_success_url(),
        cancel_url:  checkout_cancel_url()
      }, api_key: stripe_key) do
        {:ok, session} -> {:ok, session.url}
        {:error, err} -> {:error, err}
      end
    end
  end

  def confirm_subscription(stripe_payment_intent_id) do
    stripe_key = Application.get_env(:koda, :stripe_secret_key)
    case Stripe.PaymentIntent.retrieve(stripe_payment_intent_id, api_key: stripe_key) do
      {:ok, pi} ->
        meta = pi.metadata
        tier = meta["tier"]
        user_id = meta["user_id"]
        server_id = if meta["server_id"] == "", do: nil, else: meta["server_id"]
        gifted_by = if meta["gifted_by"] == "", do: nil, else: meta["gifted_by"]
        amount_cents = pi.amount

        # Create subscription record
        expires_at = DateTime.utc_now() |> DateTime.add(30, :day)
        {:ok, sub} = %KodaSubscription{}
        |> KodaSubscription.changeset(%{
          user_id:                  user_id,
          tier:                     tier,
          server_id:                server_id,
          gifted_by_user_id:        gifted_by,
          amount_cents:             amount_cents,
          stripe_payment_intent_id: stripe_payment_intent_id,
          expires_at:               expires_at,
          active:                   true
        })
        |> Repo.insert()

        # Update user tier
        Repo.update_all(
          from(u in Koda.Auth.User, where: u.id == ^user_id),
          set: [koda_tier: tier]
        )

        # Credit server bank
        fee_cents = round(amount_cents * 0.05)
        if server_id do
          credit_server_bank(server_id, fee_cents, "subscription", sub.id)
        end

        # Pulse perk: one redeemable server boost token per renewal.
        if tier == "pulse" do
          Koda.Boosts.mint_boost_token(user_id)
        end

        # Notify whoever actually paid -- the gift-giver if this was
        # gifted, otherwise the subscriber themselves -- that their
        # Checkout tab is done.
        payer_id = gifted_by || user_id
        Koda.Notifications.notify_and_push(payer_id, "payment_confirmed",
          "Subscription active", "Koda #{String.capitalize(tier)} is now active.",
          %{payment_type: "subscription", subscription_id: sub.id})

        {:ok, sub}
      {:error, err} -> {:error, err}
    end
  end

  def active_subscription(user_id) do
    Repo.one(
      from s in KodaSubscription,
      where: s.user_id == ^user_id and s.active == true
          and s.expires_at > ^DateTime.utc_now(),
      order_by: [desc: s.inserted_at],
      limit: 1
    )
  end

  # ── Stripe Webhooks ───────────────────────────────────────────────────────

  def handle_webhook("payment_intent.succeeded", %{"id" => pi_id, "metadata" => meta}) do
    case meta["type"] do
      "tip"                  -> confirm_tip(pi_id)
      "subscription"         -> confirm_subscription(pi_id)
      "server_subscription"  -> Koda.ServerSubscriptions.confirm_subscription(pi_id)
      "digital_product"      -> Koda.DigitalProducts.confirm_purchase(pi_id)
      "stage_ticket"         -> Koda.Events.confirm_ticket(pi_id)
      _                      -> :ok
    end
  end

  def handle_webhook("account.updated", %{"id" => account_id}) do
    # Sync Connect account status when Stripe notifies us of changes
    case Repo.get_by(StripeConnectAccount, stripe_account_id: account_id) do
      nil  -> :ok
      acct ->
        stripe_key = Application.get_env(:koda, :stripe_secret_key)
        url = "https://api.stripe.com/v1/accounts/#{account_id}"
        headers = [{"Authorization", "Bearer #{stripe_key}"}]
        case :hackney.get(url, headers, "", [with_body: true]) do
          {:ok, 200, _, body} ->
            data = Jason.decode!(body)
            acct
            |> StripeConnectAccount.changeset(%{
              onboarding_complete: data["details_submitted"] || false,
              payouts_enabled:     data["payouts_enabled"] || false,
              charges_enabled:     data["charges_enabled"] || false
            })
            |> Repo.update()
          _ -> :ok
        end
    end
  end

  def handle_webhook(_, _), do: :ok

  # ── Queries ───────────────────────────────────────────────────────────────

  def tip_json(tip) do
    %{
      id:             tip.id,
      from_user_id:   tip.from_user_id,
      to_user_id:     tip.to_user_id,
      server_id:      tip.server_id,
      amount_cents:   tip.amount_cents,
      creator_amount: tip.creator_amount_cents,
      fee_cents:      tip.fee_cents,
      points_credited: tip.points_credited,
      status:         tip.status,
      message:        tip.message,
      inserted_at:    DateTime.to_iso8601(tip.inserted_at)
    }
  end
end
