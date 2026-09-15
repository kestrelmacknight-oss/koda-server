defmodule KodaWeb.RoomChannel do
  use KodaWeb, :channel
  alias Koda.{Servers, Chat}

  @impl true
  def join("channel:" <> channel_id, _payload, socket) do
    user    = socket.assigns[:current_user]
    channel = Servers.get_channel(channel_id)

    cond do
      is_nil(channel) ->
        {:error, %{reason: "channel_not_found"}}

      not Servers.member_can_view_channel?(channel, user.id) ->
        {:error, %{reason: "not_authorized"}}

      true ->
        send(self(), {:after_join, channel_id})
        {:ok, assign(socket, :channel_id, channel_id)}
    end
  end

  # Presence-only topic for "who's in this voice channel" -- separate from
  # the LiveKit media connection, this just relays the participant_joined/
  # participant_left events LiveKit's webhook already broadcasts (see
  # Koda.Voice.handle_webhook) to anyone watching the channel list.
  def join("voice:" <> channel_id, _payload, socket) do
    user    = socket.assigns[:current_user]
    channel = Servers.get_channel(channel_id)

    cond do
      is_nil(channel) ->
        {:error, %{reason: "channel_not_found"}}

      not Servers.member_can_view_channel?(channel, user.id) ->
        {:error, %{reason: "not_authorized"}}

      true ->
        send(self(), {:after_join_voice, channel_id})
        {:ok, socket}
    end
  end

  def join("dm:" <> conversation_id, _payload, socket) do
    user  = socket.assigns[:current_user]
    convo = Koda.DirectMessages.get_conversation(conversation_id, user.id)

    if convo do
      {:ok, assign(socket, :conversation_id, conversation_id)}
    else
      {:error, %{reason: "not_authorized"}}
    end
  end

  def join("user:" <> user_id, _payload, socket) do
    current = socket.assigns[:current_user]
    if current.id == user_id do
      {:ok, socket}
    else
      {:error, %{reason: "not_authorized"}}
    end
  end

  @impl true
  def handle_info({:after_join, channel_id}, socket) do
    KodaWeb.Presence.track(socket, socket.assigns[:channel_id], %{
      user_id:    socket.assigns[:current_user].id,
      joined_at:  DateTime.utc_now() |> DateTime.to_iso8601()
    })
    push(socket, "presence_state", KodaWeb.Presence.list(socket))
    {:noreply, socket}
  end

  def handle_info({:after_join_voice, channel_id}, socket) do
    participants =
      case Koda.Voice.list_participants(channel_id) do
        {:ok, ps} ->
          ps
          # "-view" identities are subscribe-only pop-out windows (see
          # Koda.Voice.join_token), not real participants.
          |> Enum.reject(fn p -> String.ends_with?(p["identity"] || "", "-view") end)
          |> Enum.map(&normalize_participant/1)
        _ -> []
      end
    push(socket, "voice_state", %{participants: participants})
    {:noreply, socket}
  end

  # Raw LiveKit participants vs. the webhook's already-flat
  # %{user_id:, username:} -- normalized to the same shape here so the
  # client only ever handles one participant format.
  defp normalize_participant(p) do
    meta =
      case p["metadata"] do
        s when is_binary(s) and s != "" ->
          case Jason.decode(s) do
            {:ok, m} -> m
            _ -> %{}
          end
        _ -> %{}
      end

    %{user_id: p["identity"], username: meta["username"]}
  end

  @impl true
  def handle_in("new_message", %{"content" => content} = params, socket) do
    user       = socket.assigns[:current_user]
    channel_id = socket.assigns[:channel_id]
    channel    = Servers.get_channel(channel_id)

    if channel && Servers.member_can_send_message?(channel, user.id) do
      case Chat.send_message(channel_id, user.id, content,
          sender_username: user.username,
          encrypted: Map.get(params, "encrypted", false),
          reply_to_id: Map.get(params, "reply_to_id"),
          epoch: Map.get(params, "epoch"),
          nonce: Map.get(params, "nonce"),
          mentioned_user_ids: Map.get(params, "mentioned_user_ids", []),
          mentioned_role_ids: Map.get(params, "mentioned_role_ids", []),
          mention_everyone: Map.get(params, "mention_everyone", false)) do
        {:ok, msg}  -> {:reply, {:ok, msg}, socket}
        {:error, _} -> {:reply, {:error, %{reason: "send_failed"}}, socket}
      end
    else
      {:reply, {:error, %{reason: "not_authorized"}}, socket}
    end
  end

  def handle_in("typing", %{"typing" => typing}, socket) do
    user       = socket.assigns[:current_user]
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

  def handle_info({:message_deleted, message_id}, socket) do
    push(socket, "message_deleted", %{id: message_id})
    {:noreply, socket}
  end

  def handle_info({:message_edited, payload}, socket) do
    push(socket, "message_edited", payload)
    {:noreply, socket}
  end

  def handle_info({:message_pinned, payload}, socket) do
    push(socket, "message_pinned", payload)
    {:noreply, socket}
  end

  def handle_info({:message_unpinned, payload}, socket) do
    push(socket, "message_unpinned", payload)
    {:noreply, socket}
  end

  def handle_info({:link_preview_updated, payload}, socket) do
    push(socket, "link_preview_updated", payload)
    {:noreply, socket}
  end

  def handle_info({:conversation_read, payload}, socket) do
    push(socket, "conversation_read", payload)
    {:noreply, socket}
  end

  def handle_info({:participant_joined, payload}, socket) do
    push(socket, "voice_participant_joined", payload)
    {:noreply, socket}
  end

  def handle_info({:participant_left, identity}, socket) do
    push(socket, "voice_participant_left", %{user_id: identity})
    {:noreply, socket}
  end

  # Mention notifications (see Koda.Chat.push_notification/2) -- pushed
  # on the per-user "user:<id>" topic, which every connected client
  # already joins on login (see home_screen.dart's
  # _subscribeToUserNotifications). This clause was missing entirely
  # until now, so every {:notification, _} broadcast was silently
  # dropped by the catch-all below -- mentions were detected and stored
  # server-side but never actually delivered live.
  def handle_info({:notification, notif}, socket) do
    push(socket, "notification", notif)
    {:noreply, socket}
  end

  # Lightweight "a channel you can see got a new message" signal, also
  # on the per-user topic -- lets the client bump a channel's unread
  # badge in the sidebar without having to join every channel's own
  # topic just to watch for activity (see Koda.Chat.send_message/4).
  def handle_info({:unread_bump, payload}, socket) do
    push(socket, "unread_bump", payload)
    {:noreply, socket}
  end

  def handle_info(_, socket), do: {:noreply, socket}
end
