defmodule Koda.Friends do
  import Ecto.Query
  alias Koda.Repo

  defmodule Friendship do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "friends" do
      field :status, :string, default: "pending"
      belongs_to :user,   Koda.Auth.User, foreign_key: :user_id
      belongs_to :friend, Koda.Auth.User, foreign_key: :friend_id
      timestamps(type: :utc_datetime)
    end

    def changeset(f, attrs) do
      f |> cast(attrs, [:user_id, :friend_id, :status])
        |> validate_required([:user_id, :friend_id])
        |> unique_constraint([:user_id, :friend_id])
    end
  end

  def list_friends(user_id) do
    accepted = Repo.all(
      from f in Friendship,
      where: (f.user_id == ^user_id or f.friend_id == ^user_id)
         and f.status == "accepted",
      preload: [:user, :friend]
    )

    pending = Repo.all(
      from f in Friendship,
      where: f.friend_id == ^user_id and f.status == "pending",
      preload: [:user]
    )

    %{friends: accepted, pending: pending}
  end

  def send_request(user_id, friend_id) when user_id != friend_id do
    %Friendship{}
    |> Friendship.changeset(%{user_id: user_id, friend_id: friend_id})
    |> Repo.insert()
  end

  def accept_request(friendship_id, user_id) do
    case Repo.get(Friendship, friendship_id) do
      %Friendship{friend_id: ^user_id} = f ->
        f |> Ecto.Changeset.change(status: "accepted") |> Repo.update()
      _ ->
        {:error, :not_found}
    end
  end

  def remove(user_id, other_id) do
    Repo.delete_all(
      from f in Friendship,
      where: (f.user_id == ^user_id and f.friend_id == ^other_id)
          or (f.user_id == ^other_id and f.friend_id == ^user_id)
    )
    :ok
  end

  def block(user_id, target_id) do
    remove(user_id, target_id)
    %Friendship{}
    |> Friendship.changeset(%{user_id: user_id, friend_id: target_id, status: "blocked"})
    |> Repo.insert()
  end
end
