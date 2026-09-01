defmodule Koda.Repo.Migrations.CreateMarketplace do
  use Ecto.Migration

  def change do
    # Creator Stripe Connect accounts
    create table(:stripe_connect_accounts, primary_key: false) do
      add :id,                    :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id,               references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :stripe_account_id,     :string, null: false
      add :onboarding_complete,   :boolean, default: false
      add :payouts_enabled,       :boolean, default: false
      add :charges_enabled,       :boolean, default: false
      add :country,               :string
      timestamps(type: :utc_datetime_usec)
    end
    create unique_index(:stripe_connect_accounts, [:user_id])
    create unique_index(:stripe_connect_accounts, [:stripe_account_id])

    # Server banks (points only)
    create table(:server_banks, primary_key: false) do
      add :id,                :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :server_id,         references(:servers, type: :binary_id, on_delete: :delete_all), null: false
      add :balance,           :integer, default: 0, null: false  # points (1pt = 1 fee cent)
      add :lifetime_received, :integer, default: 0, null: false
      timestamps(type: :utc_datetime_usec)
    end
    create unique_index(:server_banks, [:server_id])

    # Point transactions (server bank audit trail)
    create table(:point_transactions, primary_key: false) do
      add :id,             :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :server_id,      references(:servers, type: :binary_id, on_delete: :delete_all), null: false
      add :amount,         :integer, null: false   # points credited
      add :source_type,    :string, null: false    # tip|subscription|boost
      add :source_id,      :binary_id             # reference to tip/subscription id
      add :inserted_at,    :utc_datetime_usec, null: false
    end
    create index(:point_transactions, [:server_id])

    # Marketplace tips
    create table(:marketplace_tips, primary_key: false) do
      add :id,                      :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :from_user_id,            references(:users, type: :binary_id, on_delete: :nilify_all)
      add :to_user_id,              references(:users, type: :binary_id, on_delete: :nilify_all)
      add :server_id,               references(:servers, type: :binary_id, on_delete: :nilify_all)
      add :amount_cents,            :integer, null: false    # total charged to buyer
      add :creator_amount_cents,    :integer, null: false    # 95% to creator
      add :fee_cents,               :integer, null: false    # 5% Koda fee
      add :points_credited,         :integer, null: false    # points to server bank
      add :stripe_payment_intent_id, :string
      add :stripe_transfer_id,      :string
      add :status,                  :string, default: "pending"  # pending|complete|failed|refunded
      add :message,                 :string                  # optional tip message
      timestamps(type: :utc_datetime_usec)
    end
    create index(:marketplace_tips, [:from_user_id])
    create index(:marketplace_tips, [:to_user_id])
    create index(:marketplace_tips, [:server_id])
    create index(:marketplace_tips, [:status])

    # Koda subscriptions (Spark / Pulse)
    create table(:koda_subscriptions, primary_key: false) do
      add :id,                      :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id,                 references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :tier,                    :string, null: false      # spark|pulse
      add :server_id,               references(:servers, type: :binary_id, on_delete: :nilify_all)
      add :gifted_by_user_id,       references(:users, type: :binary_id, on_delete: :nilify_all)
      add :amount_cents,            :integer, null: false
      add :stripe_payment_intent_id, :string
      add :expires_at,              :utc_datetime_usec, null: false
      add :active,                  :boolean, default: true
      timestamps(type: :utc_datetime_usec)
    end
    create index(:koda_subscriptions, [:user_id])
    create index(:koda_subscriptions, [:expires_at])
    create index(:koda_subscriptions, [:active])

    # Add koda_tier to users
    alter table(:users) do
      add_if_not_exists :koda_tier, :string, default: "free"
    end
  end
end
