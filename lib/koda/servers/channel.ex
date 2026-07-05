defmodule Koda.Servers.Channel do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "channels" do
    field :name,               :string
    field :type,               :string, default: "text"
    field :description,        :string
    field :position,           :integer, default: 0
    field :is_subscriber_only, :boolean, default: false
    field :is_read_only,       :boolean, default: false
    belongs_to :server,   Koda.Servers.Server
    belongs_to :category, Koda.Servers.Category
    timestamps(type: :utc_datetime)
  end
  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [:name, :type, :description, :position,
                    :is_subscriber_only, :is_read_only, :server_id, :category_id])
    |> validate_required([:name, :server_id])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_inclusion(:type, ["text", "voice", "gallery"])
  end
  def voice?(%__MODULE__{type: "voice"}), do: true
  def voice?(_), do: false
  def gallery?(%__MODULE__{type: "gallery"}), do: true
  def gallery?(_), do: false
end