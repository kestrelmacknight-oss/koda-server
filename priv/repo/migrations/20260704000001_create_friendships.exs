defmodule Koda.Repo.Migrations.CreateFriendships do
  use Ecto.Migration

  def change do
    create table(:friendships, primary_key: false) do
      add :id,         :binary_id, primary_key: true
      add :user_id,    references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :friend_id,  references(:users, type: :binary_id, on_delete: :delete_all), null: false
      # status: pending | accepted | declined | blocked
      add :status,     :string, null: false, default: "pending"
      # Optional message sent with the friend request
      add :message,    :string
      timestamps(type: :utc_datetime)
    end

    # Only one relationship per pair in either direction
    create unique_index(:friendships, [:user_id, :friend_id])
    create index(:friendships, [:friend_id])
    create index(:friendships, [:status])

    # Add friends_only_dms toggle to users
    alter table(:users) do
      add_if_not_exists :friends_only_dms, :boolean, default: false
    end
  end
end
