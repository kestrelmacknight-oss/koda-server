defmodule Koda.Voice do
  alias Koda.Voice.LiveKit
  alias Koda.Servers

  def join_token(channel_id, user) do
    channel = Servers.get_channel(channel_id)

    cond do
      is_nil(channel)                            -> {:error, :channel_not_found}
      is_nil(Servers.get_member(channel.server_id, user.id)) -> {:error, :unauthorized}
      not Koda.Servers.Channel.voice?(channel)  -> {:error, :not_a_voice_channel}
      true ->
        token = LiveKit.generate_token(user, channel_id)
        url   = Application.get_env(:koda, :livekit, [])
                |> Keyword.get(:public_url, "ws://localhost:7880")
        {:ok, %{token: token, url: url, room: LiveKit.room_name(channel_id)}}
    end
  end

  def kick(channel_id, user_id), do: LiveKit.remove_participant(channel_id, user_id)

  def list_participants(channel_id), do: LiveKit.list_participants(channel_id)

  def handle_webhook(%{"event" => "participant_joined"} = event) do
    room       = get_in(event, ["room", "name"])
    identity   = get_in(event, ["participant", "identity"])
    channel_id = LiveKit.channel_id_from_room(room)
    if channel_id && identity do
      meta = get_in(event, ["participant", "metadata"])
             |> case do
               nil -> %{}
               s   -> Jason.decode!(s)
             end
      Phoenix.PubSub.broadcast(Koda.PubSub, "voice:#{channel_id}",
        {:participant_joined, %{user_id: identity, username: meta["username"]}})
    end
    :ok
  end

  def handle_webhook(%{"event" => "participant_left"} = event) do
    room       = get_in(event, ["room", "name"])
    identity   = get_in(event, ["participant", "identity"])
    channel_id = LiveKit.channel_id_from_room(room)
    if channel_id && identity do
      Phoenix.PubSub.broadcast(Koda.PubSub, "voice:#{channel_id}",
        {:participant_left, identity})
    end
    :ok
  end

  def handle_webhook(_), do: :ok
end
