defmodule Koda.Repo.Migrations.CreateMessagesTables do
  use Ecto.Migration

  def change do
    create table(:messages, primary_key: false) do
      add :id,         :binary_id, primary_key: true
      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all), null: false
      add :sender_id,  references(:users, type: :binary_id), null: false
      add :content,    :text, null: false
      add :encrypted,  :boolean, default: false
      add :inserted_at, :utc_datetime, null: false
    end

    create index(:messages, [:channel_id, :inserted_at])
    create index(:messages, [:sender_id])

    create table(:dm_messages, primary_key: false) do
      add :id,              :binary_id, primary_key: true
      add :conversation_id, :string, null: false
      add :sender_id,       references(:users, type: :binary_id), null: false
      add :content,         :text, null: false
      add :encrypted,       :boolean, default: false
      add :inserted_at,     :utc_datetime, null: false
    end

    create index(:dm_messages, [:conversation_id, :inserted_at])

    create table(:message_reactions, primary_key: false) do
      add :id,         :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :message_id, :binary_id, null: false
      add :user_id,    references(:users, type: :binary_id), null: false
      add :emoji,      :string, null: false
    end

    create unique_index(:message_reactions, [:message_id, :user_id, :emoji])
  end
end
