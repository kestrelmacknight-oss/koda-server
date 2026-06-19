defmodule KodaWeb.FriendController do
  use KodaWeb, :controller
  alias Koda.Friends

  def index(conn, _) do
    user = Guardian.Plug.current_resource(conn)
    json(conn, Friends.list_friends(user.id))
  end

  def send_request(conn, %{"username" => username}) do
    user  = Guardian.Plug.current_resource(conn)
    other = Koda.Auth.get_user_by_username(username)
    if other && other.id != user.id do
      case Friends.send_request(user.id, other.id) do
        {:ok, _}    -> json(conn, %{ok: true})
        {:error, _} -> conn |> put_status(422) |> json(%{error: "Request already sent"})
      end
    else
      conn |> put_status(422) |> json(%{error: "User not found"})
    end
  end

  def accept(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)
    case Friends.accept_request(id, user.id) do
      {:ok, _}    -> json(conn, %{ok: true})
      {:error, _} -> conn |> put_status(422) |> json(%{error: "Not found"})
    end
  end

  def remove(conn, %{"user_id" => other_id}) do
    user = Guardian.Plug.current_resource(conn)
    Friends.remove(user.id, other_id)
    json(conn, %{ok: true})
  end

  def block(conn, %{"user_id" => target_id}) do
    user = Guardian.Plug.current_resource(conn)
    Friends.block(user.id, target_id)
    json(conn, %{ok: true})
  end
end
