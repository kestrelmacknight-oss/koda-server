defmodule Koda.Crypto do
  @moduledoc """
  Key bundle storage for the KCP (Koda Cryptographic Protocol) X3DH layer.

  The server stores only public key material -- private keys are generated
  on the client and never transmitted. When Alice wants to send an encrypted
  message to Bob, she fetches Bob's key bundle, performs X3DH locally, and
  sends the ciphertext. The server is a pure key directory, never a
  participant in the cryptographic operations.

  OPK (one-time pre-key) consumption is not yet implemented -- keys are
  returned but not marked used. This is acceptable for Alpha; add OPK
  consumption before public launch.
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
      field :spk_rotated_at, :utc_datetime
      belongs_to :user, Koda.Auth.User
      timestamps(type: :utc_datetime)
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
  Returns the bundle without consuming OPKs (Alpha behaviour).
  """
  def get_key_bundle(user_id) do
    Repo.get_by(KeyBundle, user_id: user_id)
  end

  @doc """
  Returns true if the user has uploaded a key bundle.
  """
  def has_key_bundle?(user_id) do
    Repo.exists?(from b in KeyBundle, where: b.user_id == ^user_id)
  end
end