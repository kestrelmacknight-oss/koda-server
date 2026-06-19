defmodule Koda.Auth.VerificationCode do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "verification_codes" do
    belongs_to :user, Koda.Auth.User
    field :code,       :string
    field :type,       :string
    field :used,       :boolean, default: false
    field :expires_at, :utc_datetime
    timestamps(type: :utc_datetime, updated_at: false)
  end
end
