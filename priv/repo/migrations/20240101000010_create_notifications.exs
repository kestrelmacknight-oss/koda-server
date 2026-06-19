defmodule Koda.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications, primary_key: false) do
      add :id,         :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id,    references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :type,       :string,  null: false
      add :title,      :string,  null: false
      add :body,       :text
      add :data,       :map,     default: %{}
      add :read,       :boolean, default: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:notifications, [:user_id, :read])
    create index(:notifications, [:user_id, :inserted_at])
  end
end
