defmodule Koda.ServerSubscriptions do
  @moduledoc """
  Server subscription tiers — owner-configured, up to 3 tiers per server.
  5% of each subscription goes to the server bank as points.
  """
  import Ecto.Query
  alias Koda.Repo
  alias Koda.Marketplace

  @platform_fee_percent 0.05

  defmodule Tier do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id
    schema "server_subscription_tiers" do
      field :server_id,                   :binary_id
      field :name,                        :string
      field :description,                 :string
      field :price_cents,                 :integer
      field :role_id,                     :binary_id
      field :twitch_discount_percent,     :integer, default: 0
      field :marketplace_discount_percent, :integer, default: 0
      field :position,                    :integer, default: 1
      field :active,                      :boolean, default: true
      timestamps(type: :utc_datetime_usec)
    end
    def changeset(t, attrs) do
      t |> cast(attrs, [:server_id, :name, :description, :price_cents,
                        :role_id, :twitch_discount_percent,
                        :marketplace_discount_percent, :position, :active])
        |> validate_required([:server_id, :name, :price_cents])
        |> validate_number(:price_cents, greater_than: 0)
        |> validate_number(:position, greater_than_or_equal_to: 1,
                           less_than_or_equal_to: 3)
    end
  end

  defmodule Subscription do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id
    schema "server_subscriptions" do
      field :tier_id,                   :binary_id
      field :server_id,                 :binary_id
      field :user_id,                   :binary_id
      field :stripe_payment_intent_id,  :string
      field :amount_cents,              :integer
      field :fee_cents,                 :integer
      field :points_credited,           :integer
      field :status,                    :string, default: "active"
      field :expires_at,                :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end
    def changeset(s, attrs) do
      s |> cast(attrs, [:tier_id, :server_id, :user_id,
                        :stripe_payment_intent_id, :amount_cents,
                        :fee_cents, :points_credited, :status, :expires_at])
        |> validate_required([:tier_id, :server_id, :user_id,
                              :amount_cents, :expires_at])
    end
  end

  # ── Tier management ───────────────────────────────────────────────────────

  def list_tiers(server_id) do
    Repo.all(from t in Tier,
      where: t.server_id == ^server_id and t.active == true,
      order_by: [asc: t.position])
    |> Enum.map(&tier_json/1)
  end

  def get_tier(id), do: Repo.get(Tier, id)

  def create_tier(attrs) do
    # Enforce max 3 tiers per server
    server_id = attrs["server_id"] || attrs[:server_id]
    count = Repo.aggregate(from(t in Tier,
      where: t.server_id == ^server_id and t.active == true), :count)
    if count >= 3 do
      {:error, :max_tiers_reached}
    else
      %Tier{} |> Tier.changeset(attrs) |> Repo.insert()
    end
  end

  def update_tier(tier, attrs) do
    tier |> Tier.changeset(attrs) |> Repo.update()
  end

  def delete_tier(tier) do
    tier |> Tier.changeset(%{active: false}) |> Repo.update()
  end

  # ── Subscriptions ─────────────────────────────────────────────────────────

  def list_subscriptions(server_id, user_id) do
    Repo.all(from s in Subscription,
      where: s.server_id == ^server_id and s.user_id == ^user_id
          and s.status == "active" and s.expires_at > ^DateTime.utc_now())
  end

  def active_subscription(server_id, user_id) do
    Repo.one(from s in Subscription,
      where: s.server_id == ^server_id and s.user_id == ^user_id
          and s.status == "active" and s.expires_at > ^DateTime.utc_now(),
      order_by: [desc: s.inserted_at],
      limit: 1)
  end

  @doc """
  Whether this server's owner can actually be paid -- Connect account
  exists and onboarding is complete. Checked before letting a member pay
  into a tier, not just at tier-creation time, since Connect status can
  change (or never have been set up) after tiers already exist.
  """
  def owner_payable?(server_id) do
    case Koda.Servers.get_server(server_id) do
      nil -> false
      server ->
        case Marketplace.get_connect_account(server.owner_id) do
          nil -> false
          acct -> acct.charges_enabled
        end
    end
  end

  def create_subscription_intent(tier_id, user_id) do
    case get_tier(tier_id) do
      nil -> {:error, :tier_not_found}
      tier ->
        server = Koda.Servers.get_server(tier.server_id)
        connect_acct = server && Marketplace.get_connect_account(server.owner_id)

        cond do
          is_nil(server) ->
            {:error, :tier_not_found}

          is_nil(connect_acct) ->
            {:error, :owner_not_connected}

          not connect_acct.charges_enabled ->
            {:error, :owner_not_onboarded}

          true ->
            stripe_key = Application.get_env(:koda, :stripe_secret_key)
            fee_cents = round(tier.price_cents * @platform_fee_percent)
            # 95% to the server owner via Stripe Connect, 5% stays in
            # Koda's own balance as the real platform fee -- the server
            # bank's points credit (confirm_subscription/1, unchanged)
            # is a separate, purely symbolic loyalty number layered on
            # top of that same 5%, not money moved a second time.
            owner_amount_cents = tier.price_cents - fee_cents

            case Stripe.Checkout.Session.create(%{
              mode: :payment,
              line_items: [%{
                price_data: %{
                  currency: "usd",
                  product_data: %{name: "#{tier.name} subscription"},
                  unit_amount: tier.price_cents
                },
                quantity: 1
              }],
              payment_intent_data: %{
                transfer_data: %{
                  destination: connect_acct.stripe_account_id,
                  amount:       owner_amount_cents
                },
                metadata: %{
                  type:      "server_subscription",
                  tier_id:   tier.id,
                  server_id: tier.server_id,
                  user_id:   user_id,
                  fee_cents: fee_cents
                }
              },
              success_url: Marketplace.checkout_success_url(),
              cancel_url:  Marketplace.checkout_cancel_url()
            }, api_key: stripe_key) do
              {:ok, session} ->
                {:ok, %{
                  checkout_url: session.url,
                  amount_cents: tier.price_cents,
                  fee_cents:    fee_cents,
                  tier:         tier_json(tier)
                }}
              {:error, err} -> {:error, err}
            end
        end
    end
  end

  def confirm_subscription(stripe_payment_intent_id) do
    stripe_key = Application.get_env(:koda, :stripe_secret_key)
    case Stripe.PaymentIntent.retrieve(
        stripe_payment_intent_id, api_key: stripe_key) do
      {:ok, pi} ->
        meta = pi.metadata
        tier_id   = meta["tier_id"]
        user_id   = meta["user_id"]
        server_id = meta["server_id"]
        fee_cents = String.to_integer(meta["fee_cents"] || "0")
        tier = get_tier(tier_id)
        unless tier do
          {:error, :tier_not_found}
        else
          expires_at = DateTime.utc_now() |> DateTime.add(30, :day)
          {:ok, sub} = %Subscription{}
          |> Subscription.changeset(%{
            tier_id:                  tier_id,
            server_id:                server_id,
            user_id:                  user_id,
            stripe_payment_intent_id: stripe_payment_intent_id,
            amount_cents:             tier.price_cents,
            fee_cents:                fee_cents,
            points_credited:          fee_cents,
            status:                   "active",
            expires_at:               expires_at
          })
          |> Repo.insert()

          # Credit server bank
          Marketplace.credit_server_bank(server_id, fee_cents,
            "server_subscription", sub.id)

          # Assign subscriber role if configured
          if tier.role_id do
            assign_subscriber_role(server_id, user_id, tier.role_id)
          end

          Koda.Notifications.notify_and_push(user_id, "payment_confirmed",
            "Subscription active", "Your #{tier.name} subscription is now active.",
            %{payment_type: "server_subscription", subscription_id: sub.id})

          {:ok, sub}
        end
      {:error, err} -> {:error, err}
    end
  end

  defp assign_subscriber_role(server_id, user_id, role_id) do
    case Koda.Repo.get_by(Koda.Servers.Member,
        server_id: server_id, user_id: user_id) do
      nil -> :ok
      member ->
        case Koda.Repo.get_by(Koda.Servers.MemberRole,
            member_id: member.id, role_id: role_id) do
          nil ->
            %Koda.Servers.MemberRole{}
            |> Koda.Servers.MemberRole.changeset(%{
                member_id: member.id, role_id: role_id})
            |> Koda.Repo.insert(on_conflict: :nothing)
          _ -> :ok
        end
    end
  end

  def subscriber_count(tier_id) do
    Repo.aggregate(from(s in Subscription,
      where: s.tier_id == ^tier_id and s.status == "active"
          and s.expires_at > ^DateTime.utc_now()), :count)
  end

  # ── JSON ──────────────────────────────────────────────────────────────────

  def tier_json(t) do
    %{
      id:                           t.id,
      server_id:                    t.server_id,
      name:                         t.name,
      description:                  t.description,
      price_cents:                  t.price_cents,
      role_id:                      t.role_id,
      twitch_discount_percent:      t.twitch_discount_percent,
      marketplace_discount_percent: t.marketplace_discount_percent,
      position:                     t.position,
      active:                       t.active
    }
  end
end
