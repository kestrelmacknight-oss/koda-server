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
      bucket = Map.get(params, "bucket", Koda.Scylla.month_bucket())
      case Chat.get_messages(channel_id, bucket: bucket) do
        {:ok, msgs}  -> json(conn, %{messages: msgs})
        {:error, _}  -> json(conn, %{messages: []})
      end
    else
      conn |> put_status(403) |> json(%{error: "Not authorized"})
    end
  end

  def send_message(conn, %{"channel_id" => channel_id, "content" => content} = params) do
    user    = Guardian.Plug.current_resource(conn)
    channel = Servers.get_channel(channel_id)
    if channel && Servers.get_member(channel.server_id, user.id) do
      encrypted = Map.get(params, "encrypted", false)
      case Chat.send_message(channel_id, user.id, content, sender_username: user.username, encrypted: encrypted) do
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
    %{id: c.id, name: c.name, type: c.type, description: c.description,
      position: c.position, is_subscriber_only: c.is_subscriber_only,
      server_id: c.server_id, category_id: c.category_id}
  end

  defp format_errors(cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, k ->
        opts |> Keyword.get(String.to_existing_atom(k), k) |> to_string()
      end)
    end)
  end
end