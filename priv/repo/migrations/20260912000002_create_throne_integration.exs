defmodule Koda.Repo.Migrations.CreateThroneIntegration do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add_if_not_exists :throne_webhook_token, :string
    end

    create_if_not_exists unique_index(:users, [:throne_webhook_token])

    create_if_not_exists table(:throne_gifts, primary_key: false) do
      add :id,          :binary_id, primary_key: true
      add :creator_id,  references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :event_id,    :string, null: false
      add :event_type,  :string, null: false
      add :gifter_username, :string
      add :amount_cents, :integer
      add :currency,     :string
      add :item_name,    :string
      add :item_thumbnail_url, :string
      add :message,      :string
      add :is_surprise_gift, :boolean, default: false
      add :raw_payload,  :map
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create_if_not_exists unique_index(:throne_gifts, [:event_id])
    create_if_not_exists index(:throne_gifts, [:creator_id])
  end
end
