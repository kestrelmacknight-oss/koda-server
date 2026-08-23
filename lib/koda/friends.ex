defmodule Koda.Friends do
  @moduledoc """
  Friend system: requests, acceptance, blocking, and DM privacy enforcement.
  """
  import Ecto.Query
  alias Koda.{Repo, Auth}

  defmodule Friendship do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "friendships" do
      field :status,  :string, default: "pending"
      field :message, :string
      belongs_to :user,   Auth.User
      belongs_to :friend, Auth.User
      timestamps(type: :utc_datetime)
    end

    def changeset(f, attrs) do
      f
      |> cast(attrs, [:user_id, :friend_id, :status, :message])
      |> validate_required([:user_id, :friend_id])
      |> validate_inclusion(:status, ~w(pending accepted declined blocked))
      |> unique_constraint([:user_id, :friend_id])
    end
  end

  # ── Send friend request ────────────────────────────────────────────────────

  def send_request(from_id, to_id, message \\ nil) do
    cond do
      from_id == to_id ->
        {:error, :cannot_friend_yourself}

      already_friends?(from_id, to_id) ->
        {:error, :already_friends}

      request_pending?(from_id, to_id) ->
        {:error, :request_already_sent}

      blocked?(from_id, to_id) ->
        {:error, :blocked}

      true ->
        %Friendship{}
        |> Friendship.changeset(%{
            user_id:   from_id,
            friend_id: to_id,
            status:    "pending",
            message:   message
           })
        |> Repo.insert()
    end
  end

  # ── Accept / decline / cancel ──────────────────────────────────────────────

  def accept_request(from_id, to_id) do
    case get_request(from_id, to_id) do
      nil -> {:error, :not_found}
      req ->
        req
        |> Friendship.changeset(%{status: "accepted"})
        |> Repo.update()
    end
  end

  def decline_request(from_id, to_id) do
    case get_request(from_id, to_id) do
      nil -> {:error, :not_found}
      req -> Repo.delete(req)
    end
  end

  def cancel_request(from_id, to_id) do
    case Repo.get_by(Friendship, user_id: from_id, friend_id: to_id, status: "pending") do
      nil -> {:error, :not_found}
      req -> Repo.delete(req)
    end
  end

  def unfriend(user_id, friend_id) do
    from(f in Friendship,
      where: (f.user_id == ^user_id and f.friend_id == ^friend_id) or
             (f.user_id == ^friend_id and f.friend_id == ^user_id)
    )
    |> Repo.delete_all()
    :ok
  end

  def block(user_id, target_id) do
    # Remove any existing friendship first
    unfriend(user_id, target_id)

    %Friendship{}
    |> Friendship.changeset(%{user_id: user_id, friend_id: target_id, status: "blocked"})
    |> Repo.insert(on_conflict: :replace_all, conflict_target: [:user_id, :friend_id])
  end

  def unblock(user_id, target_id) do
    Repo.delete_all(
      from f in Friendship,
      where: f.user_id == ^user_id and f.friend_id == ^target_id and f.status == "blocked"
    )
    :ok
  end

  # ── Queries ────────────────────────────────────────────────────────────────

  def list_friends(user_id) do
    from(f in Friendship,
      where: ((f.user_id == ^user_id or f.friend_id == ^user_id) and f.status == "accepted"),
      preload: [:user, :friend]
    )
    |> Repo.all()
    |> Enum.map(fn f ->
      if f.user_id == user_id, do: f.friend, else: f.user
    end)
  end

  def list_pending_received(user_id) do
    from(f in Friendship,
      where: f.friend_id == ^user_id and f.status == "pending",
      preload: [:user]
    )
    |> Repo.all()
    |> Enum.map(fn f -> %{id: f.id, user: f.user, message: f.message, sent_at: f.inserted_at} end)
  end

  def list_pending_sent(user_id) do
    from(f in Friendship,
      where: f.user_id == ^user_id and f.status == "pending",
      preload: [:friend]
    )
    |> Repo.all()
    |> Enum.map(fn f -> %{id: f.id, user: f.friend, message: f.message, sent_at: f.inserted_at} end)
  end

  def friends?(user_id, other_id) do
    Repo.exists?(
      from f in Friendship,
      where: ((f.user_id == ^user_id and f.friend_id == ^other_id) or
              (f.user_id == ^other_id and f.friend_id == ^user_id)) and
             f.status == "accepted"
    )
  end

  def blocked?(user_id, other_id) do
    Repo.exists?(
      from f in Friendship,
      where: f.user_id == ^user_id and f.friend_id == ^other_id and f.status == "blocked"
    )
  end

  # ── DM privacy enforcement ─────────────────────────────────────────────────

  def can_dm?(from_id, to_id) do
    target = Repo.get!(Auth.User, to_id)
    if target.friends_only_dms do
      friends?(from_id, to_id)
    else
      true
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp get_request(from_id, to_id) do
    Repo.get_by(Friendship, user_id: from_id, friend_id: to_id, status: "pending")
  end

  defp already_friends?(a, b), do: friends?(a, b)

  defp request_pending?(a, b) do
    Repo.exists?(
      from f in Friendship,
      where: ((f.user_id == ^a and f.friend_id == ^b) or
              (f.user_id == ^b and f.friend_id == ^a)) and
             f.status == "pending"
    )
  end
end
