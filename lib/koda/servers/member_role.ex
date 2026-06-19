defmodule Koda.Servers.MemberRole do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "member_roles" do
    belongs_to :member, Koda.Servers.Member
    belongs_to :role,   Koda.Servers.Role
    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(member_role, attrs) do
    member_role
    |> cast(attrs, [:member_id, :role_id])
    |> validate_required([:member_id, :role_id])
    |> unique_constraint([:member_id, :role_id])
  end
end
