defmodule KodaWeb.FriendsController do
  use KodaWeb, :controller
  alias Koda.{Friends, Auth, Repo}

  def send_request(conn, %{"user_id" => to_id} = params) do
    user    = Guardian.Plug.current_resource(conn)
    message = Map.get(params, "message")

    case Friends.send_request(user.id, to_id, message) do
      {:ok, _}                       -> json(conn, %{ok: true})
      {:error, :cannot_friend_yourself} -> conn |> put_status(422) |> json(%{error: "You cannot friend yourself"})
      {:error, :already_friends}     -> conn |> put_status(409) |> json(%{error: "Already friends"})
      {:error, :request_already_sent}-> conn |> put_status(409) |> json(%{error: "Request already sent"})
      {:error, :blocked}             -> conn |> put_status(403) |> json(%{error: "Cannot send request"})
      {:error, cs}                   -> conn |> put_status(422) |> json(%{error: inspect(cs)})
    end
  end

  def accept_request(conn, %{"user_id" => from_id}) do
    user = Guardian.Plug.current_resource(conn)
    case Friends.accept_request(from_id, user.id) do
      {:ok, _}            -> json(conn, %{ok: true})
      {:error, :not_found}-> conn |> put_status(404) |> json(%{error: "Request not found"})
      {:error, e}         -> conn |> put_status(422) |> json(%{error: inspect(e)})
    end
  end

  def decline_request(conn, %{"user_id" => from_id}) do
    user = Guardian.Plug.current_resource(conn)
    case Friends.decline_request(from_id, user.id) do
      {:ok, _}            -> json(conn, %{ok: true})
      {:error, :not_found}-> conn |> put_status(404) |> json(%{error: "Request not found"})
      {:error, e}         -> conn |> put_status(422) |> json(%{error: inspect(e)})
    end
  end

  def unfriend(conn, %{"user_id" => friend_id}) do
    user = Guardian.Plug.current_resource(conn)
    Friends.unfriend(user.id, friend_id)
    json(conn, %{ok: true})
  end

  def block(conn, %{"user_id" => target_id}) do
    user = Guardian.Plug.current_resource(conn)
    Friends.block(user.id, target_id)
    json(conn, %{ok: true})
  end

  def unblock(conn, %{"user_id" => target_id}) do
    user = Guardian.Plug.current_resource(conn)
    Friends.unblock(user.id, target_id)
    json(conn, %{ok: true})
  end

  def list(conn, _params) do
    user    = Guardian.Plug.current_resource(conn)
    friends = Friends.list_friends(user.id)
    json(conn, %{friends: Enum.map(friends, &user_json/1)})
  end

  def pending(conn, _params) do
    user     = Guardian.Plug.current_resource(conn)
    received = Friends.list_pending_received(user.id)
    sent     = Friends.list_pending_sent(user.id)
    json(conn, %{
      received: Enum.map(received, fn r ->
        %{id: r.id, user: user_json(r.user), message: r.message,
          sent_at: DateTime.to_iso8601(r.sent_at)}
      end),
      sent: Enum.map(sent, fn s ->
        %{id: s.id, user: user_json(s.user), message: s.message,
          sent_at: DateTime.to_iso8601(s.sent_at)}
      end)
    })
  end

  def status(conn, %{"user_id" => other_id}) do
    user = Guardian.Plug.current_resource(conn)
    json(conn, %{
      friends:  Friends.friends?(user.id, other_id),
      blocked:  Friends.blocked?(user.id, other_id),
      can_dm:   Friends.can_dm?(user.id, other_id)
    })
  end

  # Update friends_only_dms toggle
  def update_privacy(conn, %{"friends_only_dms" => value}) do
    user = Guardian.Plug.current_resource(conn)
    user
    |> Ecto.Changeset.change(friends_only_dms: value)
    |> Repo.update()
    json(conn, %{ok: true})
  end

  defp user_json(u) do
    %{id: u.id, username: u.username, avatar_url: u.avatar_url}
  end
end
