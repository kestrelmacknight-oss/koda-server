defmodule Koda.Repo.Migrations.AddChannelEncryption do
  use Ecto.Migration

  def change do
    # A channel's series of shared symmetric keys. The server only ever
    # sees this registry -- the key material itself never touches it,
    # only per-recipient ciphertext in channel_key_deliveries below.
    # Rotated (a new row inserted) whenever a member leaves/is removed,
    # so a departed member can't read anything sent after they're gone.
    create table(:channel_epoch_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all), null: false
      add :epoch, :integer, null: false
      add :created_by, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end
    create unique_index(:channel_epoch_keys, [:channel_id, :epoch])

    # One encrypted copy of a given epoch's key per recipient, delivered
    # over that recipient's existing pairwise DM Double Ratchet session
    # (same envelope shape as a DM message) -- never posted into
    # dm_messages itself, so it never shows up in anyone's DM inbox.
    create table(:channel_key_deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all), null: false
      add :epoch, :integer, null: false
      add :sender_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :recipient_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :content, :text, null: false
      add :ratchet_key, :string, null: false
      add :msg_number, :integer, null: false
      add :prev_chain, :integer, null: false
      add :nonce, :string, null: false
      add :x3dh_header, :map
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end
    create unique_index(:channel_key_deliveries, [:channel_id, :epoch, :recipient_id])
    create index(:channel_key_deliveries, [:recipient_id])

    alter table(:messages) do
      # Which epoch's key this message was encrypted with -- nil for
      # legacy/unencrypted history, which stays readable as plaintext.
      add_if_not_exists :epoch, :integer
      add_if_not_exists :nonce, :string
      # Mentions are computed client-side (against plaintext, before
      # encryption) and sent as structured IDs instead of the server
      # regex-scanning message content -- see Koda.Chat.process_mentions/4.
      add_if_not_exists :mentioned_user_ids, {:array, :binary_id}, default: []
      add_if_not_exists :mentioned_role_ids, {:array, :binary_id}, default: []
      add_if_not_exists :mention_everyone, :boolean, default: false
    end
  end
end
