defmodule Koda.Repo.Migrations.CreateDigitalProducts do
  use Ecto.Migration

  def change do
    create table(:digital_products, primary_key: false) do
      add :id,               :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :creator_id,       references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :server_id,        references(:servers, type: :binary_id, on_delete: :nilify_all)
      add :free_for_tier_id, references(:server_subscription_tiers, type: :binary_id, on_delete: :nilify_all)
      add :title,            :string, null: false
      add :description,      :text
      add :price_cents,      :integer, null: false, default: 0
      add :product_type,     :string, null: false, default: "file"  # file|license_key
      add :file_url,         :string
      add :file_name,        :string
      add :file_size_bytes,  :integer
      add :scope,            :string, default: "server"  # server|creator
      add :active,           :boolean, default: true
      add :purchase_count,   :integer, default: 0
      timestamps(type: :utc_datetime_usec)
    end
    create index(:digital_products, [:creator_id])
    create index(:digital_products, [:server_id])

    create table(:product_purchases, primary_key: false) do
      add :id,                      :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :product_id,              references(:digital_products, type: :binary_id, on_delete: :delete_all), null: false
      add :buyer_id,                references(:users, type: :binary_id, on_delete: :nilify_all)
      add :amount_cents,            :integer, null: false
      add :stripe_payment_intent_id, :string
      add :license_key,             :string
      add :download_token,          :string
      add :download_token_expires_at, :utc_datetime_usec
      add :download_count,          :integer, default: 0
      add :status,                  :string, default: "pending"  # pending|complete|refunded
      timestamps(type: :utc_datetime_usec)
    end
    create index(:product_purchases, [:product_id])
    create index(:product_purchases, [:buyer_id])
    create index(:product_purchases, [:download_token])

    create table(:license_keys, primary_key: false) do
      add :id,          :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :product_id,  references(:digital_products, type: :binary_id, on_delete: :delete_all), null: false
      add :key,         :string, null: false
      add :claimed_by,  references(:users, type: :binary_id, on_delete: :nilify_all)
      add :claimed_at,  :utc_datetime_usec
      add :purchase_id, references(:product_purchases, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end
    create index(:license_keys, [:product_id])
    create unique_index(:license_keys, [:key])
  end
end
