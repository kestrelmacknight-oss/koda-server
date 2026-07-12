defmodule KodaWeb.ModerationController do
  use KodaWeb, :controller
  alias Koda.{Servers, Chat}

  # -- Message moderation -------------------------------------------------------

  def delete_message(conn, %{"channel_id" => channel_id, "message_id" => message_id}) do
    user    = Guardian.Plug.current_resource(conn)
    channel = Servers.get_channel(channel_id)

    if channel && (Servers.owner?(channel.server_id, user.id) or
                   Servers.member_can?(channel.server_id, user.id, "manage_messages")) do
      case Chat.delete_message(channel_id, message_id) do
        :ok ->
          # Broadcast deletion so connected clients remove it from view
          Phoenix.PubSub.broadcast(Koda.PubSub, "channel:#{channel_id}",
            {:message_deleted, message_id})
          json(conn, %{ok: true})
        {:error, reason} ->
          conn |> put_status(500) |> json(%{error: inspect(reason)})
      end
    else
      conn |> put_status(403) |> json(%{error: "Not authorized"})
    end
  end

  # -- Member moderation --------------------------------------------------------

  def kick_member(conn, %{"server_id" => server_id, "user_id" => target_id}) do
    user = Guardian.Plug.current_resource(conn)

    cond do
      target_id == user.id ->
        conn |> put_status(422) |> json(%{error: "Cannot kick yourself"})
      not (Servers.owner?(server_id, user.id) or
           Servers.member_can?(server_id, user.id, "kick_members")) ->
        conn |> put_status(403) |> json(%{error: "Not authorized"})
      true ->
        case Servers.remove_member(server_id, target_id) do
          :ok         -> json(conn, %{ok: true})
          {:error, _} -> conn |> put_status(404) |> json(%{error: "Member not found"})
        end
    end
  end

  def ban_member(conn, %{"server_id" => server_id, "user_id" => target_id}) do
    user = Guardian.Plug.current_resource(conn)

    cond do
      target_id == user.id ->
        conn |> put_status(422) |> json(%{error: "Cannot ban yourself"})
      not (Servers.owner?(server_id, user.id) or
           Servers.member_can?(server_id, user.id, "ban_members")) ->
        conn |> put_status(403) |> json(%{error: "Not authorized"})
      true ->
        case Servers.ban_member(server_id, target_id) do
          {:ok, _}    -> json(conn, %{ok: true})
          {:error, _} -> conn |> put_status(404) |> json(%{error: "Member not found"})
        end
    end
  end

  def unban_member(conn, %{"server_id" => server_id, "user_id" => target_id}) do
    user = Guardian.Plug.current_resource(conn)

    if Servers.owner?(server_id, user.id) or
       Servers.member_can?(server_id, user.id, "ban_members") do
      case Servers.unban_member(server_id, target_id) do
        :ok         -> json(conn, %{ok: true})
        {:error, _} -> conn |> put_status(404) |> json(%{error: "Member not found"})
      end
    else
      conn |> put_status(403) |> json(%{error: "Not authorized"})
    end
  end

  def list_bans(conn, %{"server_id" => server_id}) do
    user = Guardian.Plug.current_resource(conn)

    if Servers.owner?(server_id, user.id) or
       Servers.member_can?(server_id, user.id, "ban_members") do
      bans = Servers.list_bans(server_id)
      json(conn, %{bans: Enum.map(bans, fn m ->
        %{user_id: m.user_id, username: m.user.username}
      end)})
    else
      conn |> put_status(403) |> json(%{error: "Not authorized"})
    end
  end
end