defmodule Koda.Repo.Migrations.CreateFriends do
  use Ecto.Migration

  def change do
    create table(:friends, primary_key: false) do
      add :id,          :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id,     references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :friend_id,   references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :status,      :string, default: "pending"   # pending | accepted | blocked
      timestamps(type: :utc_datetime)
    end

    create unique_index(:friends, [:user_id, :friend_id])
    create index(:friends, [:friend_id])
    create index(:friends, [:user_id, :status])
  end
end
