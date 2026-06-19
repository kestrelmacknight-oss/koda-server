defmodule Koda.Servers.Server do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "servers" do
    field :name,         :string
    field :description,  :string
    field :icon_url,     :string
    field :banner_url,   :string
    field :is_public,    :boolean, default: false
    field :category,     :string
    field :member_count, :integer, default: 1
    belongs_to :owner, Koda.Auth.User
    has_many :channels, Koda.Servers.Channel
    has_many :members,  Koda.Servers.Member
    timestamps(type: :utc_datetime)
  end

  def changeset(server, attrs) do
    server
    |> cast(attrs, [:name, :description, :icon_url, :banner_url,
                    :is_public, :category, :owner_id])
    |> validate_required([:name, :owner_id])
    |> validate_length(:name, min: 2, max: 100)
    |> validate_length(:description, max: 500)
  end
end
