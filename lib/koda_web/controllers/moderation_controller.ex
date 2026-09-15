defmodule KodaWeb.ModerationController do
  use KodaWeb, :controller
  alias Koda.{Servers, Chat, Moderation}

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
          :ok ->
            Moderation.log(server_id, "kick", actor_id: user.id, target_user_id: target_id)
            json(conn, %{ok: true})
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
          {:ok, _} ->
            Moderation.log(server_id, "ban", actor_id: user.id, target_user_id: target_id)
            json(conn, %{ok: true})
          {:error, _} -> conn |> put_status(404) |> json(%{error: "Member not found"})
        end
    end
  end

  def unban_member(conn, %{"server_id" => server_id, "user_id" => target_id}) do
    user = Guardian.Plug.current_resource(conn)

    if Servers.owner?(server_id, user.id) or
       Servers.member_can?(server_id, user.id, "ban_members") do
      case Servers.unban_member(server_id, target_id) do
        :ok ->
          Moderation.log(server_id, "unban", actor_id: user.id, target_user_id: target_id)
          json(conn, %{ok: true})
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

  # -- Mute (Tier 1: metadata-only, no message content involved) ---------------

  def mute_member(conn, %{"server_id" => server_id, "user_id" => target_id} = params) do
    user = Guardian.Plug.current_resource(conn)
    duration = params |> Map.get("duration_seconds", 600) |> to_int(600) |> max(1) |> min(2_592_000)

    cond do
      target_id == user.id ->
        conn |> put_status(422) |> json(%{error: "Cannot mute yourself"})
      not (Servers.owner?(server_id, user.id) or
           Servers.member_can?(server_id, user.id, "mute_members")) ->
        conn |> put_status(403) |> json(%{error: "Not authorized"})
      true ->
        case Moderation.mute_member(server_id, target_id, duration,
               actor_id: user.id, reason: Map.get(params, "reason")) do
          {:ok, member} -> json(conn, %{ok: true, muted_until: DateTime.to_iso8601(member.muted_until)})
          {:error, _}   -> conn |> put_status(404) |> json(%{error: "Member not found"})
        end
    end
  end

  def unmute_member(conn, %{"server_id" => server_id, "user_id" => target_id}) do
    user = Guardian.Plug.current_resource(conn)

    if Servers.owner?(server_id, user.id) or
       Servers.member_can?(server_id, user.id, "mute_members") do
      case Moderation.unmute_member(server_id, target_id, actor_id: user.id) do
        {:ok, _}    -> json(conn, %{ok: true})
        {:error, _} -> conn |> put_status(404) |> json(%{error: "Member not found"})
      end
    else
      conn |> put_status(403) |> json(%{error: "Not authorized"})
    end
  end

  # -- Raid lockdown -------------------------------------------------------------

  def unlock_invites(conn, %{"server_id" => server_id}) do
    user = Guardian.Plug.current_resource(conn)

    if Servers.owner?(server_id, user.id) or
       Servers.member_can?(server_id, user.id, "manage_server") do
      case Servers.set_invites_locked(server_id, false) do
        {:ok, _} ->
          Moderation.log(server_id, "raid_lockdown_disabled", actor_id: user.id)
          json(conn, %{ok: true})
        {:error, _} -> conn |> put_status(404) |> json(%{error: "Server not found"})
      end
    else
      conn |> put_status(403) |> json(%{error: "Not authorized"})
    end
  end

  # -- Audit log -------------------------------------------------------------

  def audit_log(conn, %{"server_id" => server_id}) do
    user = Guardian.Plug.current_resource(conn)

    if Servers.owner?(server_id, user.id) or
       Servers.member_can?(server_id, user.id, "kick_members") or
       Servers.member_can?(server_id, user.id, "ban_members") or
       Servers.member_can?(server_id, user.id, "mute_members") do
      actions = Moderation.list_actions(server_id)
      json(conn, %{actions: Enum.map(actions, &Moderation.action_json/1)})
    else
      conn |> put_status(403) |> json(%{error: "Not authorized"})
    end
  end

  defp to_int(v, _default) when is_integer(v), do: v
  defp to_int(v, default) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> default
    end
  end
  defp to_int(_, default), do: default
end