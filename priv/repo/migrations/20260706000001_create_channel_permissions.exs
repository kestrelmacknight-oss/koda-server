defmodule Koda.Repo.Migrations.CreateChannelPermissions do
  use Ecto.Migration

  def change do
    create table(:channel_allowed_roles, primary_key: false) do
      add :id,         :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all), null: false
      add :role_id,    references(:roles, type: :binary_id, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:channel_allowed_roles, [:channel_id, :role_id])
    create index(:channel_allowed_roles, [:role_id])
  end
end
