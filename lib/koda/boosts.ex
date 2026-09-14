defmodule Koda.Boosts do
  @moduledoc """
  Server boosting: Pulse subscribers earn one redeemable "boost token" per
  monthly renewal (see Koda.Marketplace.confirm_subscription/1) and can
  gift it to any server they belong to. A server's boost level is derived
  from how many currently-active (non-expired) boosts are applied to it --
  same shape as Discord's server boosting, simplified to one tier ladder.

  The boost_tokens/server_boosts tables predate this module (added in the
  20260716000001_create_server_subscriptions migration alongside server
  subscription tiers) but were never wired to any schema or context code
  until now.
  """
  import Ecto.Query
  alias Koda.Repo

  # How long an unredeemed token stays redeemable before it expires unused.
  @token_validity_days 60
  # How long one applied boost lasts before it needs renewing with a fresh token.
  @boost_duration_days 30

  defmodule BoostToken do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id
    schema "boost_tokens" do
      field :user_id,    :binary_id
      field :used,       :boolean, default: false
      field :used_at,    :utc_datetime_usec
      field :server_id,  :binary_id
      field :expires_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end
    def changeset(t, attrs) do
      t |> cast(attrs, [:user_id, :used, :used_at, :server_id, :expires_at])
        |> validate_required([:user_id, :expires_at])
    end
  end

  defmodule ServerBoost do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id
    schema "server_boosts" do
      field :server_id,  :binary_id
      field :user_id,    :binary_id
      field :token_id,   :binary_id
      field :expires_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end
    def changeset(b, attrs) do
      b |> cast(attrs, [:server_id, :user_id, :token_id, :expires_at])
        |> validate_required([:server_id, :expires_at])
    end
  end

  @doc "Mints one redeemable boost token for a user. Called on Pulse subscription renewal."
  def mint_boost_token(user_id) do
    %BoostToken{}
    |> BoostToken.changeset(%{
      user_id:    user_id,
      expires_at: DateTime.utc_now() |> DateTime.add(@token_validity_days, :day)
    })
    |> Repo.insert()
  end

  @doc "Unused, unexpired boost tokens a user currently holds, oldest first."
  def list_available_tokens(user_id) do
    Repo.all(
      from t in BoostToken,
      where: t.user_id == ^user_id and t.used == false and t.expires_at > ^DateTime.utc_now(),
      order_by: [asc: t.expires_at]
    )
  end

  @doc """
  Redeems the caller's oldest available boost token on a server, applying a
  fresh #{@boost_duration_days}-day boost. Row-locks the token so two
  concurrent requests can't both redeem the same one. Callers are
  responsible for checking server membership first (see
  BoostController.boost/2) -- this function only knows about tokens.
  """
  def redeem_boost(user_id, server_id) do
    Repo.transaction(fn ->
      token =
        Repo.one(
          from t in BoostToken,
          where: t.user_id == ^user_id and t.used == false and t.expires_at > ^DateTime.utc_now(),
          order_by: [asc: t.expires_at],
          limit: 1,
          lock: "FOR UPDATE"
        )

      case token do
        nil ->
          Repo.rollback(:no_tokens_available)

        token ->
          now = DateTime.utc_now()
          {:ok, updated_token} =
            token
            |> BoostToken.changeset(%{used: true, used_at: now, server_id: server_id})
            |> Repo.update()

          {:ok, boost} =
            %ServerBoost{}
            |> ServerBoost.changeset(%{
              server_id:  server_id,
              user_id:    user_id,
              token_id:   updated_token.id,
              expires_at: DateTime.add(now, @boost_duration_days, :day)
            })
            |> Repo.insert()

          boost
      end
    end)
  end

  @doc "Count of currently-active (non-expired) boosts applied to a server."
  def active_boost_count(server_id) do
    Repo.aggregate(
      from(b in ServerBoost, where: b.server_id == ^server_id and b.expires_at > ^DateTime.utc_now()),
      :count
    )
  end

  @doc """
  Discord-inspired boost level ladder (0-3), derived purely from the
  active boost count. Informational for now -- perk-gating (e.g. raised
  upload limits) is a natural follow-up once the core mechanic is in use,
  deliberately not invented here.
  """
  def boost_level(count) do
    cond do
      count >= 10 -> 3
      count >= 5  -> 2
      count >= 2  -> 1
      true        -> 0
    end
  end

  def server_boost_status(server_id) do
    count = active_boost_count(server_id)
    %{count: count, level: boost_level(count)}
  end
end
