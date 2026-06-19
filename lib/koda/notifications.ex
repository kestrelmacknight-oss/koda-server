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
      timestamps(type: :utc_datetime, updated_at: false)
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
