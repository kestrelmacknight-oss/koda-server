defmodule Koda.Repo.Migrations.CreateDmConversations do
  use Ecto.Migration

  def change do
    create table(:dm_conversations, primary_key: false) do
      add :id,           :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :initiator_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :recipient_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:dm_conversations, [:initiator_id, :recipient_id])
    create index(:dm_conversations, [:initiator_id])
    create index(:dm_conversations, [:recipient_id])
  end
end
