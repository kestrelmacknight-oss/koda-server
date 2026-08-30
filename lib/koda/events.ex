defmodule Koda.Events do
  import Ecto.Query
  alias Koda.Repo

  defmodule ServerEvent do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id
    schema "server_events" do
      field :channel_id,  :binary_id
      field :server_id,   :binary_id
      field :created_by,  :binary_id
      field :title,       :string
      field :description, :string
      field :location,    :string
      field :start_at,    :utc_datetime_usec
      field :end_at,      :utc_datetime_usec
      field :recurrence,  :string, default: "none"
      field :color,       :string, default: "#2DD4A0"
      timestamps(type: :utc_datetime_usec)
    end
    def changeset(e, attrs) do
      e |> cast(attrs, [:channel_id, :server_id, :created_by, :title,
                        :description, :location, :start_at, :end_at,
                        :recurrence, :color])
        |> validate_required([:channel_id, :server_id, :title, :start_at])
        |> validate_inclusion(:recurrence, ["none","daily","weekly","monthly"])
    end
  end

  defmodule EventSubscription do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id
    schema "event_subscriptions" do
      field :event_id, :binary_id
      field :user_id,  :binary_id
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end
    def changeset(s, attrs) do
      s |> cast(attrs, [:event_id, :user_id])
        |> validate_required([:event_id, :user_id])
        |> unique_constraint([:event_id, :user_id])
    end
  end

  def list_events(channel_id) do
    Repo.all(from e in ServerEvent,
      where: e.channel_id == ^channel_id,
      order_by: [asc: e.start_at])
    |> Enum.map(&event_json/1)
  end

  def get_event(id), do: Repo.get(ServerEvent, id)

  def create_event(attrs) do
    %ServerEvent{} |> ServerEvent.changeset(attrs) |> Repo.insert()
  end

  def update_event(event, attrs) do
    event |> ServerEvent.changeset(attrs) |> Repo.update()
  end

  def delete_event(event), do: Repo.delete(event)

  def subscribe(event_id, user_id) do
    %EventSubscription{}
    |> EventSubscription.changeset(%{event_id: event_id, user_id: user_id})
    |> Repo.insert(on_conflict: :nothing)
  end

  def unsubscribe(event_id, user_id) do
    Repo.delete_all(from s in EventSubscription,
      where: s.event_id == ^event_id and s.user_id == ^user_id)
  end

  def subscribed?(event_id, user_id) do
    Repo.exists?(from s in EventSubscription,
      where: s.event_id == ^event_id and s.user_id == ^user_id)
  end

  def subscriber_ids(event_id) do
    Repo.all(from s in EventSubscription,
      where: s.event_id == ^event_id,
      select: s.user_id)
  end

  def event_json(e) do
    %{
      id:          e.id,
      channel_id:  e.channel_id,
      server_id:   e.server_id,
      created_by:  e.created_by,
      title:       e.title,
      description: e.description,
      location:    e.location,
      start_at:    DateTime.to_iso8601(e.start_at),
      end_at:      if(e.end_at, do: DateTime.to_iso8601(e.end_at), else: nil),
      recurrence:  e.recurrence,
      color:       e.color
    }
  end
end
