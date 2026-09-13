defmodule Koda.Crypto do
  @moduledoc """
  Key bundle storage for the KCP (Koda Cryptographic Protocol) X3DH layer.

  The server stores only public key material -- private keys are generated
  on the client and never transmitted. When Alice wants to send an encrypted
  message to Bob, she fetches Bob's key bundle, performs X3DH locally, and
  sends the ciphertext. The server is a pure key directory, never a
  participant in the cryptographic operations.

  OPKs are consumed (removed) on fetch via consume_opk/1 -- see
  key_bundle_controller.ex show/2, which is deliberately a side-effecting
  GET, same as Signal's own prekey directory.
  """
  import Ecto.Query
  alias Koda.Repo

  defmodule KeyBundle do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "key_bundles" do
      field :ik_sign_pub,   :string
      field :ik_dh_pub,     :string
      field :spk_pub,       :string
      field :spk_sig,       :string
      field :opks,          {:array, :string}, default: []
      field :spk_rotated_at, :utc_datetime_usec
      belongs_to :user, Koda.Auth.User
      timestamps(type: :utc_datetime_usec)
    end

    def changeset(bundle, attrs) do
      bundle
      |> cast(attrs, [:user_id, :ik_sign_pub, :ik_dh_pub, :spk_pub, :spk_sig, :opks, :spk_rotated_at])
      |> validate_required([:user_id, :ik_sign_pub, :ik_dh_pub, :spk_pub, :spk_sig])
    end
  end

  @doc """
  Upload or replace a user's key bundle.
  Called on first login and after SPK rotation.
  """
  def put_key_bundle(user_id, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Repo.get_by(KeyBundle, user_id: user_id) do
      nil ->
        %KeyBundle{}
        |> KeyBundle.changeset(Map.merge(attrs, %{
            "user_id"        => user_id,
            "spk_rotated_at" => now
          }))
        |> Repo.insert()

      existing ->
        existing
        |> KeyBundle.changeset(Map.put(attrs, "spk_rotated_at", now))
        |> Repo.update()
    end
  end

  @doc """
  Fetch another user's public key bundle for X3DH initiation.
  Returns the bundle without consuming OPKs -- use consume_opk/1 when
  actually initiating a session (see key_bundle_controller.ex show/2).
  """
  def get_key_bundle(user_id) do
    Repo.get_by(KeyBundle, user_id: user_id)
  end

  @doc """
  Pops one one-time prekey off a user's bundle for X3DH initiation and
  persists its removal, so it can never be reused for a second session
  (OPK reuse breaks X3DH's forward-secrecy guarantee for that handshake).

  Row-locked so two concurrent initiations can't both be handed the same
  OPK. Returns {:ok, {bundle, opk_or_nil, remaining_count}} -- opk is nil
  when the bundle has none left (X3DH can still proceed with only
  DH1-DH3; the caller just skips DH4). {:error, :not_found} if the user
  has no bundle at all.
  """
  def consume_opk(user_id) do
    Repo.transaction(fn ->
      case Repo.one(from b in KeyBundle, where: b.user_id == ^user_id, lock: "FOR UPDATE") do
        nil ->
          Repo.rollback(:not_found)

        %KeyBundle{opks: []} = bundle ->
          {bundle, nil, 0}

        %KeyBundle{opks: [opk | rest]} = bundle ->
          {:ok, updated} =
            bundle
            |> Ecto.Changeset.change(opks: rest)
            |> Repo.update()

          {updated, opk, length(rest)}
      end
    end)
  end

  @doc """
  Returns true if the user has uploaded a key bundle.
  """
  def has_key_bundle?(user_id) do
    Repo.exists?(from b in KeyBundle, where: b.user_id == ^user_id)
  end
end