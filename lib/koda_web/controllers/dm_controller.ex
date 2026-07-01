defmodule KodaWeb.DmController do
  use KodaWeb, :controller
  alias Koda.DirectMessages

  def list_conversations(conn, _) do
    user = Guardian.Plug.current_resource(conn)
    convos = DirectMessages.list_conversations(user.id)
    json(conn, %{conversations: Enum.map(convos, fn c ->
      other = if c.initiator_id == user.id, do: c.recipient, else: c.initiator
      %{id: c.id, user: %{id: other.id, username: other.username, avatar_url: other.avatar_url}}
    end)})
  end

  def open_conversation(conn, %{"user_id" => other_id}) do
    user = Guardian.Plug.current_resource(conn)
    case DirectMessages.open_conversation(user.id, other_id) do
      {:ok, c} -> json(conn, %{conversation: %{id: c.id}})
      {:error, _} -> conn |> put_status(422) |> json(%{error: "Could not open conversation"})
    end
  end

  def messages(conn, %{"conversation_id" => conv_id} = params) do
    user  = Guardian.Plug.current_resource(conn)
    convo = DirectMessages.get_conversation(conv_id, user.id)
    if convo do
      bucket = Map.get(params, "bucket", Koda.Scylla.month_bucket())
      case DirectMessages.get_messages(conv_id, bucket: bucket) do
        {:ok, msgs} -> json(conn, %{messages: msgs})
        {:error, _} -> json(conn, %{messages: []})
      end
    else
      conn |> put_status(403) |> json(%{error: "Not authorized"})
    end
  end

  def send_message(conn, %{"conversation_id" => conv_id, "content" => content}) do
    user  = Guardian.Plug.current_resource(conn)
    convo = DirectMessages.get_conversation(conv_id, user.id)
    if convo do
      case DirectMessages.send_message(conv_id, user.id, content,
             sender_username: user.username) do
        {:ok, msg}  -> conn |> put_status(201) |> json(%{message: msg})
        {:error, _} -> conn |> put_status(500) |> json(%{error: "Send failed"})
      end
    else
      conn |> put_status(403) |> json(%{error: "Not authorized"})
    end
  end
end