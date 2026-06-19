defmodule Koda.Servers.Member do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "server_members" do
    field :nickname,      :string
    field :is_subscriber, :boolean, default: false
    field :is_banned,     :boolean, default: false
    field :joined_at,     :utc_datetime
    belongs_to :server, Koda.Servers.Server
    belongs_to :user,   Koda.Auth.User
    many_to_many :roles, Koda.Servers.Role,
      join_through: "member_roles",
      join_keys: [member_id: :id, role_id: :id]
    timestamps(type: :utc_datetime)
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:server_id, :user_id, :nickname, :is_subscriber,
                    :is_banned, :joined_at])
    |> validate_required([:server_id, :user_id, :joined_at])
    |> unique_constraint([:server_id, :user_id])
  end
end
