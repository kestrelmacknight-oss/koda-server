defmodule Koda.Voice.LiveKit do
  @moduledoc "LiveKit JWT generation and RoomService API calls."

  alias Koda.Voice.LiveKit.JWT

  # -- Token generation --------------------------------------------------------

  def generate_token(user, channel_id, opts \\ []) do
    can_publish = Keyword.get(opts, :can_publish, true)
    room        = room_name(channel_id)
    cfg         = livekit_config()

    claims = %{
      "video" => %{
        "roomJoin"       => true,
        "room"           => room,
        "canPublish"     => can_publish,
        "canSubscribe"   => true,
        "canPublishData" => true
      },
      "metadata" => Jason.encode!(%{
        "username" => user.username,
        "user_id"  => user.id
      })
    }

    JWT.sign(cfg[:api_key], cfg[:api_secret], user.id, claims)
  end

  def room_name(channel_id), do: "koda-#{channel_id}"

  def channel_id_from_room("koda-" <> channel_id), do: channel_id
  def channel_id_from_room(_), do: nil

  # -- RoomService API ---------------------------------------------------------

  def list_participants(channel_id) do
    call_room_service("ListParticipants", %{room: room_name(channel_id)})
    |> case do
      {:ok, %{"participants" => ps}} -> {:ok, ps}
      {:ok, _}                       -> {:ok, []}
      err                            -> err
    end
  end

  def remove_participant(channel_id, user_id) do
    call_room_service("RemoveParticipant", %{
      room:     room_name(channel_id),
      identity: user_id
    })
  end

  # Promote or demote a stage participant.
  # can_publish: true  = speaker (mic active)
  # can_publish: false = listener (hear only)
  def update_participant_permission(channel_id, user_id, can_publish) do
    call_room_service("UpdateParticipant", %{
      room:     room_name(channel_id),
      identity: user_id,
      permission: %{
        can_publish:      can_publish,
        can_subscribe:    true,
        can_publish_data: true
      }
    })
  end

  # -- Private -----------------------------------------------------------------

  defp call_room_service(method, body) do
    cfg    = livekit_config()
    url    = "#{internal_url()}/twirp/livekit.RoomService/#{method}"
    token  = admin_token(cfg)

    case Req.post(url,
      json:    body,
      headers: [{"authorization", "Bearer #{token}"}]
    ) do
      {:ok, %{status: s, body: b}} when s in 200..299 -> {:ok, b}
      {:ok, %{status: s, body: b}}                    -> {:error, {s, b}}
      {:error, reason}                                 -> {:error, reason}
    end
  end

  defp admin_token(cfg) do
    claims = %{
      "video" => %{
        "roomCreate" => true,
        "roomList"   => true,
        "roomAdmin"  => true
      }
    }
    JWT.sign(cfg[:api_key], cfg[:api_secret], "koda-server", claims)
  end

  defp livekit_config do
    Application.get_env(:koda, :livekit, [])
  end

  defp internal_url do
    # Use internal LiveKit URL for server-to-server RoomService calls.
    # Falls back to public URL if internal isn't set.
    cfg = livekit_config()
    Keyword.get(cfg, :url, Keyword.get(cfg, :public_url, "http://koda-livekit.internal:7880"))
  end
end