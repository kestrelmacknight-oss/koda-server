defmodule Koda.Servers.Category do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "categories" do
    field :name,     :string
    field :position, :integer, default: 0
    belongs_to :server, Koda.Servers.Server
    has_many   :channels, Koda.Servers.Channel
    timestamps(type: :utc_datetime)
  end

  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :position, :server_id])
    |> validate_required([:name, :server_id])
    |> validate_length(:name, min: 1, max: 100)
  end
end
