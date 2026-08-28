defmodule KodaWeb.ChannelController do
  use KodaWeb, :controller
  alias Koda.{Servers, Chat}

  def index(conn, %{"server_id" => server_id}) do
    user = Guardian.Plug.current_resource(conn)
    unless Servers.get_member(server_id, user.id) do
      conn |> put_status(403) |> json(%{error: "Not a member"})
    else
      channels = Servers.list_channels(server_id)
      json(conn, %{channels: Enum.map(channels, &channel_json/1)})
    end
  end

  def create(conn, %{"server_id" => server_id} = params) do
    user = Guardian.Plug.current_resource(conn)
    if Servers.owner?(server_id, user.id) or
       Servers.member_can?(server_id, user.id, "manage_channels") do
      case Servers.create_channel(server_id, params) do
        {:ok, ch}    -> conn |> put_status(201) |> json(%{channel: channel_json(ch)})
        {:error, cs} -> conn |> put_status(422) |> json(%{errors: format_errors(cs)})
      end
    else
      conn |> put_status(403) |> json(%{error: "Not authorized"})
    end
  end

  def update(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)
    case Servers.get_channel(id) do
      nil -> conn |> put_status(404) |> json(%{error: "Not found"})
      ch  ->
        if Servers.owner?(ch.server_id, user.id) or
           Servers.member_can?(ch.server_id, user.id, "manage_channels") do
          case Servers.update_channel(ch, params) do
            {:ok, updated} -> json(conn, %{channel: channel_json(updated)})
            {:error, _}    -> conn |> put_status(422) |> json(%{error: "Update failed"})
          end
        else
          conn |> put_status(403) |> json(%{error: "Not authorized"})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)
    case Servers.get_channel(id) do
      nil -> conn |> put_status(404) |> json(%{error: "Not found"})
      ch  ->
        if Servers.owner?(ch.server_id, user.id) or
           Servers.member_can?(ch.server_id, user.id, "manage_channels") do
          Servers.delete_channel(ch)
          json(conn, %{ok: true})
        else
          conn |> put_status(403) |> json(%{error: "Not authorized"})
        end
    end
  end

  def messages(conn, %{"channel_id" => channel_id} = params) do
    user = Guardian.Plug.current_resource(conn)
    channel = Servers.get_channel(channel_id)
    if channel && Servers.get_member(channel.server_id, user.id) do
      msgs = Chat.get_messages(channel_id)
      json(conn, %{messages: msgs})
    else
      conn |> put_status(403) |> json(%{error: "Not authorized"})
    end
  end

  def send_message(conn, %{"channel_id" => channel_id, "content" => content} = params) do
    channel = Koda.Servers.get_channel(channel_id)
    user = Guardian.Plug.current_resource(conn)
    if channel && channel.is_read_only do
      # Check if user has a role with manage_messages or send_messages permission
      has_permission = Koda.Servers.member_can?(channel.server_id, user.id, "manage_messages") or
                       Koda.Servers.owner?(channel.server_id, user.id)
      unless has_permission do
        conn |> put_status(403) |> json(%{error: "This channel is view only"}) |> halt()
      end
    end
    user    = Guardian.Plug.current_resource(conn)
    channel = Servers.get_channel(channel_id)
    if channel && Servers.get_member(channel.server_id, user.id) do
      encrypted = Map.get(params, "encrypted", false)
      reply_to_id = Map.get(params, "reply_to_id")
      case Chat.send_message(channel_id, user.id, content,
          sender_username: user.username,
          encrypted: encrypted,
          reply_to_id: reply_to_id) do
        {:ok, msg}   -> conn |> put_status(201) |> json(%{message: msg})
        {:error, _}  -> conn |> put_status(500) |> json(%{error: "Send failed"})
      end
    else
      conn |> put_status(403) |> json(%{error: "Not authorized"})
    end
  end

  def typing(conn, %{"channel_id" => channel_id}) do
    user = Guardian.Plug.current_resource(conn)
    Phoenix.PubSub.broadcast(Koda.PubSub, "channel:#{channel_id}",
      {:typing, %{user_id: user.id, username: user.username}})
    json(conn, %{ok: true})
  end

  defp channel_json(c) do
    allowed_role_ids = Koda.Servers.get_channel_allowed_roles(c.id)
    %{id: c.id, name: c.name, type: c.type, description: c.description,
      position: c.position, is_subscriber_only: c.is_subscriber_only,
      server_id: c.server_id, category_id: c.category_id,
      rules_content: Map.get(c, :rules_content),
      is_read_only: c.is_read_only,
      is_thread: c.is_thread,
      parent_message_id: c.parent_message_id,
      thread_count: c.thread_count,
      allowed_role_ids: allowed_role_ids}
  end

  defp format_errors(cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, k ->
        opts |> Keyword.get(String.to_existing_atom(k), k) |> to_string()
      end)
    end)
  end
  def create_thread(conn, %{"channel_id" => channel_id, "message_id" => message_id, "name" => name}) do
    user = Guardian.Plug.current_resource(conn)
    channel = Koda.Servers.get_channel(channel_id)
    unless channel do
      conn |> put_status(404) |> json(%{error: "Channel not found"})
    else
      case Koda.Servers.create_channel(channel.server_id, %{
        "name" => name,
        "type" => "text",
        "is_thread" => true,
        "parent_message_id" => message_id,
        "category_id" => channel.category_id
      }) do
        {:ok, thread} ->
          # Increment thread count on parent message
          conn |> put_status(201) |> json(%{channel: channel_json(thread)})
        {:error, cs} ->
          conn |> put_status(422) |> json(%{errors: format_errors(cs)})
      end
    end
  end
end
