defmodule Koda.Repo.Migrations.CreateInvites do
  use Ecto.Migration

  def change do
    create table(:invites, primary_key: false) do
      add :id,           :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :server_id,    references(:servers, type: :binary_id, on_delete: :delete_all), null: false
      add :creator_id,   references(:users,   type: :binary_id, on_delete: :delete_all), null: false
      add :code,         :string, null: false
      add :is_permanent, :boolean, default: false
      add :uses,         :integer, default: 0
      add :max_uses,     :integer
      add :expires_at,   :utc_datetime
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:invites, [:code])
    create index(:invites, [:server_id])
  end
end
