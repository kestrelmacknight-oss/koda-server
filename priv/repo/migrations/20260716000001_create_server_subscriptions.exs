defmodule Koda.Repo.Migrations.CreateServerSubscriptions do
  use Ecto.Migration

  def change do
    # Server subscription tiers (owner-configured, up to 3)
    create table(:server_subscription_tiers, primary_key: false) do
      add :id,                    :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :server_id,             references(:servers, type: :binary_id, on_delete: :delete_all), null: false
      add :name,                  :string, null: false        # e.g. "Fan", "Supporter", "VIP"
      add :description,           :string
      add :price_cents,           :integer, null: false
      add :role_id,               :binary_id                  # auto-assigned role
      add :twitch_discount_percent, :integer, default: 0      # future Twitch hook
      add :marketplace_discount_percent, :integer, default: 0 # discount on server marketplace
      add :position,              :integer, default: 1        # 1, 2, or 3
      add :active,                :boolean, default: true
      timestamps(type: :utc_datetime_usec)
    end
    create index(:server_subscription_tiers, [:server_id])

    # Active server subscriptions
    create table(:server_subscriptions, primary_key: false) do
      add :id,                      :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :tier_id,                 references(:server_subscription_tiers, type: :binary_id, on_delete: :delete_all), null: false
      add :server_id,               references(:servers, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id,                 references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :stripe_payment_intent_id, :string
      add :amount_cents,            :integer, null: false
      add :fee_cents,               :integer, null: false     # 5% to server bank
      add :points_credited,         :integer, null: false
      add :status,                  :string, default: "active"
      add :expires_at,              :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end
    create index(:server_subscriptions, [:user_id])
    create index(:server_subscriptions, [:server_id])
    create index(:server_subscriptions, [:tier_id])
    create unique_index(:server_subscriptions, [:user_id, :tier_id])

    # Boost tokens (Pulse users get 1/month)
    create table(:boost_tokens, primary_key: false) do
      add :id,          :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id,     references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :used,        :boolean, default: false
      add :used_at,     :utc_datetime_usec
      add :server_id,   references(:servers, type: :binary_id, on_delete: :nilify_all)
      add :expires_at,  :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end
    create index(:boost_tokens, [:user_id])

    # Server boosts (applied boost tokens)
    create table(:server_boosts, primary_key: false) do
      add :id,          :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :server_id,   references(:servers, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id,     references(:users, type: :binary_id, on_delete: :nilify_all)
      add :token_id,    references(:boost_tokens, type: :binary_id, on_delete: :nilify_all)
      add :expires_at,  :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end
    create index(:server_boosts, [:server_id])
  end
end
