defmodule Koda.Repo.Migrations.CreateServerEvents do
  use Ecto.Migration

  def change do
    create table(:server_events, primary_key: false) do
      add :id,          :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :channel_id,  references(:channels, type: :binary_id, on_delete: :delete_all), null: false
      add :server_id,   references(:servers,  type: :binary_id, on_delete: :delete_all), null: false
      add :created_by,  references(:users,    type: :binary_id, on_delete: :nilify_all)
      add :title,       :string, null: false
      add :description, :text
      add :location,    :string
      add :start_at,    :utc_datetime_usec, null: false
      add :end_at,      :utc_datetime_usec
      add :recurrence,  :string, default: "none" # none, daily, weekly, monthly
      add :color,       :string, default: "#2DD4A0"
      timestamps(type: :utc_datetime_usec)
    end

    create table(:event_subscriptions, primary_key: false) do
      add :id,       :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :event_id, references(:server_events, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id,  references(:users, type: :binary_id, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:server_events, [:channel_id])
    create index(:server_events, [:server_id])
    create index(:server_events, [:start_at])
    create unique_index(:event_subscriptions, [:event_id, :user_id])
  end
end
