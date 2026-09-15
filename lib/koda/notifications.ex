defmodule Koda.Notifications do
  import Ecto.Query
  alias Koda.Repo

  defmodule Notification do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "notifications" do
      field :type,  :string
      field :title, :string
      field :body,  :string
      field :data,  :map, default: %{}
      field :read,  :boolean, default: false
      belongs_to :user, Koda.Auth.User
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    def changeset(n, attrs) do
      n |> cast(attrs, [:user_id, :type, :title, :body, :data, :read])
        |> validate_required([:user_id, :type, :title])
    end
  end

  def list(user_id, opts \\ []) do
    query = from n in Notification,
            where: n.user_id == ^user_id,
            order_by: [desc: n.inserted_at],
            limit: 50

    query = if Keyword.get(opts, :unread_only),
      do:   where(query, [n], n.read == false),
      else: query

    Repo.all(query)
  end

  def create(user_id, type, title, body \\ nil, data \\ %{}) do
    %Notification{}
    |> Notification.changeset(%{
      user_id: user_id, type: type,
      title: title, body: body, data: data
    })
    |> Repo.insert()
  end

  @doc """
  Persists a notification and immediately pushes it over the user's own
  socket topic ("user:\#{id}"), same event shape Koda.Chat's mention
  notifications already use -- the client's single existing "notification"
  listener (home_screen.dart's _subscribeToUserNotifications) handles both
  with no new client-side plumbing needed. Used by every payment confirm
  path (tips, subscriptions, digital goods, stage tickets) to tell the
  buyer's own client a Stripe Checkout it opened just completed.
  """
  def notify_and_push(user_id, type, title, body \\ nil, data \\ %{}) do
    case create(user_id, type, title, body, data) do
      {:ok, notif} = result ->
        Phoenix.PubSub.broadcast(
          Koda.PubSub,
          "user:#{user_id}",
          {:notification, %{
            id:          notif.id,
            type:        notif.type,
            title:       notif.title,
            body:        notif.body,
            data:        notif.data,
            inserted_at: DateTime.to_iso8601(notif.inserted_at)
          }}
        )
        result
      error -> error
    end
  end

  def mark_read(id) do
    Repo.update_all(from(n in Notification, where: n.id == ^id), set: [read: true])
  end

  def mark_all_read(user_id) do
    Repo.update_all(
      from(n in Notification, where: n.user_id == ^user_id and n.read == false),
      set: [read: true]
    )
  end

  def unread_count(user_id) do
    Repo.aggregate(
      from(n in Notification, where: n.user_id == ^user_id and n.read == false),
      :count
    )
  end
end
