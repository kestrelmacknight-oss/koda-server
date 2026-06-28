defmodule Koda.Auth.User do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :username,             :string
    field :email,                :string
    field :password,             :string, virtual: true
    field :password_confirmation,:string, virtual: true
    field :hashed_password,      :string
    field :display_name,         :string
    field :avatar_url,           :string
    field :bio,                  :string
    field :status,               :string, default: "offline"
    field :totp_secret,          :string
    field :totp_enabled,         :boolean, default: false
    field :is_admin,             :boolean, default: false
    field :must_change_password, :boolean, default: false
    field :email_verified,       :boolean, default: false
    field :settings,             :map, default: %{}
    timestamps(type: :utc_datetime)
  end
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :email, :password, :password_confirmation,
                    :is_admin, :must_change_password, :email_verified])
    |> validate_required([:username, :email, :password])
    |> validate_length(:username, min: 2, max: 32)
    |> validate_format(:username, ~r/^[a-zA-Z0-9_]+$/,
         message: "only letters, numbers, and underscores")
    |> validate_length(:email, max: 160)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/)
    |> validate_length(:password, min: 8, max: 128)
    |> validate_confirmation(:password, required: false)
    |> unique_constraint(:username)
    |> unique_constraint(:email)
    |> downcase_email()
    |> hash_password()
  end
  def update_changeset(user, attrs) do
    user
    |> cast(attrs, [:display_name, :avatar_url, :bio, :status,
                    :must_change_password, :email_verified])
    |> validate_length(:display_name, max: 64)
    |> validate_length(:bio, max: 500)
    |> validate_inclusion(:status, ["online", "away", "dnd", "offline"])
  end
  # Settings are stored as a single free-form JSON map, keyed by section
  # (e.g. "voice", "appearance", "notifications") -- the client merges
  # patches locally and sends the complete, already-merged object on
  # every save, so this changeset just replaces the column wholesale
  # rather than attempting any merge logic of its own.
  def settings_changeset(user, attrs) do
    user
    |> cast(attrs, [:settings])
  end
  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password, :password_confirmation])
    |> validate_required([:password])
    |> validate_length(:password, min: 8, max: 128)
    |> validate_confirmation(:password, message: "does not match")
    |> hash_password()
    |> put_change(:must_change_password, false)
  end
  def totp_changeset(user, attrs) do
    user
    |> cast(attrs, [:totp_secret, :totp_enabled])
  end
  def valid_password?(%__MODULE__{hashed_password: hash}, password)
      when is_binary(hash) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hash)
  end
  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
  defp hash_password(changeset) do
    case get_change(changeset, :password) do
      nil -> changeset
      pwd -> put_change(changeset, :hashed_password, Bcrypt.hash_pwd_salt(pwd))
    end
  end
  defp downcase_email(changeset) do
    update_change(changeset, :email, &String.downcase/1)
  end
end