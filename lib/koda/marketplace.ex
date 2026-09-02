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
        case Stripe.Account.retrieve(acct.stripe_account_id, api_key: stripe_key) do
          {:ok, stripe_acct} ->
            acct
            |> StripeConnectAccount.changeset(%{
              onboarding_complete: stripe_acct.details_submitted,
              payouts_enabled:     stripe_acct.payouts_enabled,
              charges_enabled:     stripe_acct.charges_enabled,
              country:             stripe_acct.country
            })
            |> Repo.update()
          {:error, err} -> {:error, err}
        end
    end
  end

  # ── Tips ──────────────────────────────────────────────────────────────────

  def calculate_tip(amount_cents) do
    fee_cents = round(amount_cents * @platform_fee_percent)
    creator_cents = amount_cents - fee_cents
    %{
      amount_cents:         amount_cents,
      creator_amount_cents: creator_cents,
      fee_cents:            fee_cents,
      points_credited:      fee_cents  # 1pt per fee cent
    }
  end

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
          # Create PaymentIntent with automatic transfer to creator
          case Stripe.PaymentIntent.create(%{
            amount:   amount_cents,
            currency: "usd",
            transfer_data: %{
              destination: connect_acct.stripe_account_id,
              amount:       calc.creator_amount_cents
            },
            metadata: %{
              from_user_id: from_user_id,
              to_user_id:   to_user_id,
              server_id:    server_id || "",
              type:         "tip"
            }
          }, api_key: stripe_key) do
            {:ok, pi} ->
              # Create pending tip record
              {:ok, tip} = %MarketplaceTip{}
              |> MarketplaceTip.changeset(Map.merge(calc, %{
                from_user_id:             from_user_id,
                to_user_id:               to_user_id,
                server_id:                server_id,
                stripe_payment_intent_id: pi.id,
                status:                   "pending",
                message:                  message
              }))
              |> Repo.insert()
              {:ok, %{tip: tip, client_secret: pi.client_secret}}
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
      case Stripe.PaymentIntent.create(%{
        amount:   amount_cents,
        currency: "usd",
        metadata: %{
          user_id:          user_id,
          tier:             tier,
          server_id:        server_id || "",
          gifted_by:        gifted_by_user_id || "",
          type:             "subscription"
        }
      }, api_key: stripe_key) do
        {:ok, pi} -> {:ok, pi.client_secret}
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
      "tip"          -> confirm_tip(pi_id)
      "subscription" -> confirm_subscription(pi_id)
      _              -> :ok
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
