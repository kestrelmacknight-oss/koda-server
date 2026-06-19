defmodule Koda.Repo.Migrations.CreateMemberRoles do
  use Ecto.Migration

  def change do
    create table(:member_roles, primary_key: false) do
      add :id,        :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :member_id, references(:server_members, type: :binary_id, on_delete: :delete_all), null: false
      add :role_id,   references(:roles, type: :binary_id, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:member_roles, [:member_id, :role_id])
    create index(:member_roles, [:role_id])
  end
end
