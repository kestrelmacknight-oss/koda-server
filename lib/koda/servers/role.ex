defmodule Koda.Servers.Role do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # The fixed permission set Koda understands today. Adding a new
  # permission later just means adding a key here AND teaching
  # Koda.Servers.member_can?/3 about it -- existing roles simply
  # treat any permission key not in their stored map as `false`.
  @permission_keys ~w(
    view_channels send_messages connect_voice manage_server
    manage_channels manage_roles manage_messages kick_members
    ban_members mention_everyone
  )

  schema "roles" do
    field :name,        :string
    field :color,       :string,  default: "#9BA5C8"
    field :position,    :integer, default: 0
    field :is_default,  :boolean, default: false
    field :permissions, :map,     default: %{}
    belongs_to :server, Koda.Servers.Server
    many_to_many :members, Koda.Servers.Member,
      join_through: "member_roles",
      join_keys: [role_id: :id, member_id: :id]
    timestamps(type: :utc_datetime)
  end

  def changeset(role, attrs) do
    role
    |> cast(attrs, [:name, :color, :position, :permissions, :server_id])
    |> validate_required([:name, :server_id])
    |> validate_length(:name, min: 1, max: 50)
    |> validate_format(:color, ~r/^#[0-9A-Fa-f]{6}$/, message: "must be a hex color like #7B68EE")
    |> normalize_permissions()
  end

  def permission_keys, do: @permission_keys

  defp normalize_permissions(changeset) do
    case get_change(changeset, :permissions) do
      nil -> changeset
      perms ->
        cleaned =
          @permission_keys
          |> Enum.map(fn key -> {key, !!Map.get(perms, key, false)} end)
          |> Map.new()
        put_change(changeset, :permissions, cleaned)
    end
  end
end
