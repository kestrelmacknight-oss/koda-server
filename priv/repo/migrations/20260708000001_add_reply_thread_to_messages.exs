defmodule Koda.Repo.Migrations.AddReplyThreadToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add_if_not_exists :reply_to_id, :binary_id, null: true
      add_if_not_exists :thread_id,   :binary_id, null: true
      add_if_not_exists :edited_at,   :utc_datetime_usec, null: true
    end

    alter table(:channels) do
      add_if_not_exists :parent_message_id, :binary_id, null: true
      add_if_not_exists :is_thread,         :boolean, default: false
      add_if_not_exists :thread_count,      :integer, default: 0
    end

    create index(:messages, [:reply_to_id])
    create index(:messages, [:thread_id])
    create index(:channels, [:parent_message_id])
  end
end
