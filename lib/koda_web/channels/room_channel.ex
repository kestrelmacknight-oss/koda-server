defmodule KodaWeb.RoomChannel do
  use KodaWeb, :channel
  alias Koda.{Servers, Chat}

  @impl true
  def join("channel:" <> channel_id, _payload, socket) do
    user    = Guardian.Phoenix.Socket.current_resource(socket)
    channel = Servers.get_channel(channel_id)

    cond do
      is_nil(channel) ->
        {:error, %{reason: "channel_not_found"}}

      is_nil(Servers.get_member(channel.server_id, user.id)) ->
        {:error, %{reason: "not_a_member"}}

      true ->
        send(self(), {:after_join, channel_id})
        {:ok, assign(socket, :channel_id, channel_id)}
    end
  end

  def join("dm:" <> conversation_id, _payload, socket) do
    user  = Guardian.Phoenix.Socket.current_resource(socket)
    convo = Koda.DirectMessages.get_conversation(conversation_id, user.id)

    if convo do
      {:ok, assign(socket, :conversation_id, conversation_id)}
    else
      {:error, %{reason: "not_authorized"}}
    end
  end

  def join("user:" <> user_id, _payload, socket) do
    current = Guardian.Phoenix.Socket.current_resource(socket)
    if current.id == user_id do
      {:ok, socket}
    else
      {:error, %{reason: "not_authorized"}}
    end
  end

  @impl true
  def handle_info({:after_join, channel_id}, socket) do
    KodaWeb.Presence.track(socket, socket.assigns[:channel_id], %{
      user_id:    Guardian.Phoenix.Socket.current_resource(socket).id,
      joined_at:  DateTime.utc_now() |> DateTime.to_iso8601()
    })
    push(socket, "presence_state", KodaWeb.Presence.list(socket))
    {:noreply, socket}
  end

  @impl true
  def handle_in("new_message", %{"content" => content}, socket) do
    user       = Guardian.Phoenix.Socket.current_resource(socket)
    channel_id = socket.assigns[:channel_id]

    case Chat.send_message(channel_id, user.id, content) do
      {:ok, msg}  -> {:reply, {:ok, msg}, socket}
      {:error, _} -> {:reply, {:error, %{reason: "send_failed"}}, socket}
    end
  end

  def handle_in("typing", %{"typing" => typing}, socket) do
    user       = Guardian.Phoenix.Socket.current_resource(socket)
    channel_id = socket.assigns[:channel_id]
    broadcast_from(socket, "typing", %{
      user_id:  user.id,
      username: user.username,
      typing:   typing
    })
    {:noreply, socket}
  end

  def handle_in(_, _, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:new_message, msg}, socket) do
    push(socket, "new_message", msg)
    {:noreply, socket}
  end

  def handle_info({:typing, payload}, socket) do
    push(socket, "typing", payload)
    {:noreply, socket}
  end

  def handle_info(_, socket), do: {:noreply, socket}
end
