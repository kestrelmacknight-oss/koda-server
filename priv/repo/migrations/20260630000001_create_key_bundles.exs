defmodule Koda.Repo.Migrations.CreateKeyBundles do
  use Ecto.Migration

  def change do
    create table(:key_bundles, primary_key: false) do
      add :id,          :binary_id, primary_key: true
      add :user_id,     references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # X3DH public key material -- private keys never leave the client.
      # All values are base64-encoded binary.
      add :ik_sign_pub, :string, null: false   # Ed25519 identity signing key
      add :ik_dh_pub,   :string, null: false   # X25519 identity DH key
      add :spk_pub,     :string, null: false   # Signed pre-key
      add :spk_sig,     :string, null: false   # SPK signature by ik_sign_pub
      add :opks,        {:array, :string}, default: [], null: false  # One-time pre-keys

      # SPK rotation -- pre-keys should rotate every 7 days.
      add :spk_rotated_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:key_bundles, [:user_id])
    create index(:key_bundles, [:spk_rotated_at])
  end
end