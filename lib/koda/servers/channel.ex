defmodule Koda.Servers.Channel do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "channels" do
    field :name,               :string
    field :type,               :string, default: "text"
    field :description,        :string
    field :rules_content,       :string
    field :is_thread,            :boolean, default: false
    field :parent_message_id,   :binary_id
    field :thread_count,        :integer, default: 0
    field :position,           :integer, default: 0
    field :is_subscriber_only, :boolean, default: false
    field :is_read_only,       :boolean, default: false
    # BlueSky-style content labels, set by a server owner/mod -- see
    # Koda.Servers.member_can_view_channel?/2 (hard-blocks child accounts)
    # and content_filters in a standard user's settings (hide/warn/show).
    field :content_labels,    {:array, :string}, default: []
    belongs_to :server,   Koda.Servers.Server
    belongs_to :category, Koda.Servers.Category
    timestamps(type: :utc_datetime_usec)
  end
  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [:name, :type, :description, :position, :rules_content,
                    :is_subscriber_only, :is_read_only, :is_thread,
                    :parent_message_id, :thread_count, :server_id, :category_id,
                    :content_labels])
    |> validate_required([:name, :server_id])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_inclusion(:type, ["text", "voice", "gallery", "stage", "rules", "role-select", "calendar"])
    |> validate_subset(:content_labels, ["adult", "suggestive", "graphic", "nudity"])
  end
  def voice?(%__MODULE__{type: "voice"}), do: true
  def voice?(_), do: false
  def gallery?(%__MODULE__{type: "gallery"}), do: true
  def gallery?(_), do: false
end