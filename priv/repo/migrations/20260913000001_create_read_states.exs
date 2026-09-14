defmodule Koda.Repo.Migrations.CreateReadStates do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:read_states, primary_key: false) do
      add :id,           :binary_id, primary_key: true
      add :user_id,       references(:users, type: :binary_id, on_delete: :delete_all), null: false
      # scope: "channel" | "dm" -- scope_id is a channel_id or dm conversation_id
      # respectively, stored as text since dm_messages.conversation_id is text
      # while messages.channel_id is a true binary_id.
      add :scope,          :string, null: false
      add :scope_id,       :string, null: false
      add :last_read_at,   :utc_datetime_usec, null: false
    end

    create_if_not_exists unique_index(:read_states, [:user_id, :scope, :scope_id])
  end
end
