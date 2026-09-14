defmodule Koda.Repo.Migrations.AddRatchetFieldsToDmMessages do
  use Ecto.Migration

  def change do
    alter table(:dm_messages) do
      # Double Ratchet message header (see Koda.Crypto / the client's
      # lib/core/crypto module). All nullable -- legacy/plaintext rows
      # predate real E2EE and won't have them.
      add_if_not_exists :ratchet_key, :string
      add_if_not_exists :msg_number,  :integer
      add_if_not_exists :prev_chain,  :integer
      add_if_not_exists :nonce,       :string
      # X3DH handshake header -- present only on the message that
      # establishes a new session (ephemeral pub, identity pub, which
      # OPK was consumed, if any).
      add_if_not_exists :x3dh_header, :map
    end
  end
end
