defmodule Koda.Voice.LiveKit do
  @moduledoc "LiveKit token generation and room management API."
  require Logger

  @default_ttl 3600

  # -- Token generation --------------------------------------------------------

  def generate_token(user, channel_id, opts \\ []) do
    cfg        = config()
    api_key    = cfg[:api_key]
    api_secret = cfg[:api_secret]
    now        = System.system_time(:second)
    can_publish = Keyword.get(opts, :can_publish, true)

    claims = %{
      "exp"  => now + Keyword.get(opts, :ttl, @default_ttl),
      "nbf"  => now,
      "iss"  => api_key,
      "sub"  => user.id,
      "video"=> %{
        "room"           => room_name(channel_id),
        "roomJoin"       => true,
        "canPublish"     => can_publish,
        "canSubscribe"   => true,
        "canPublishData" => true
      },
      "metadata" => Jason.encode!(%{
        user_id:    user.id,
        username:   user.username,
        avatar_url: user.avatar_url
      })
    }

    sign_token(claims, api_secret)
  end

  def generate_admin_token do
    cfg = config()
    now = System.system_time(:second)

    claims = %{
      "exp"   => now + 300,
      "nbf"   => now,
      "iss"   => cfg[:api_key],
      "sub"   => "koda-server",
      "video" => %{"roomAdmin" => true, "roomCreate" => true}
    }

    sign_token(claims, cfg[:api_secret])
  end

  # -- Room management ---------------------------------------------------------

  def list_participants(channel_id) do
    api_post("livekit.RoomService/ListParticipants", %{room: room_name(channel_id)})
    |> case do
      {:ok, %{"participants" => p}} -> {:ok, p}
      {:ok, _}                     -> {:ok, []}
      err                          -> err
    end
  end

  def remove_participant(channel_id, user_id) do
    api_post("livekit.RoomService/RemoveParticipant", %{
      room:     room_name(channel_id),
      identity: user_id
    })
  end

  # Promote or demote a stage participant.
  # can_publish: true  = speaker (mic active)
  # can_publish: false = listener (hear only)
  def update_participant_permission(channel_id, user_id, can_publish) do
    api_post("livekit.RoomService/UpdateParticipant", %{
      room:     room_name(channel_id),
      identity: user_id,
      permission: %{
        can_publish:      can_publish,
        can_subscribe:    true,
        can_publish_data: true
      }
    })
  end

  # -- Webhook verification ----------------------------------------------------

  def verify_webhook(body, "Bearer " <> token) do
    case verify_token(token, config()[:api_secret]) do
      {:ok, _}    -> Jason.decode(body)
      {:error, _} -> {:error, :invalid_signature}
    end
  end

  def verify_webhook(_, _), do: {:error, :missing_authorization}

  # -- Helpers -----------------------------------------------------------------

  def room_name(channel_id), do: "koda-#{channel_id}"

  def channel_id_from_room("koda-" <> id), do: id
  def channel_id_from_room(_), do: nil

  # -- Private -----------------------------------------------------------------

  defp api_post(method, body) do
    cfg   = config()
    url   = "#{cfg[:url]}/twirp/#{method}"
    token = generate_admin_token()

    case Req.post(url,
           json: body,
           headers: [{"authorization", "Bearer #{token}"}],
           receive_timeout: 5_000) do
      {:ok, %{status: 200, body: resp}} -> {:ok, resp}
      {:ok, %{status: s, body: b}}      ->
        Logger.warning("[LiveKit] #{method} returned #{s}: #{inspect(b)}")
        {:error, {:http_error, s}}
      {:error, reason} ->
        Logger.error("[LiveKit] #{method} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp sign_token(claims, secret) do
    h = %{"alg" => "HS256", "typ" => "JWT"} |> Jason.encode!() |> Base.url_encode64(padding: false)
    p = claims |> Jason.encode!() |> Base.url_encode64(padding: false)
    unsigned = "#{h}.#{p}"
    sig = :crypto.mac(:hmac, :sha256, secret, unsigned) |> Base.url_encode64(padding: false)
    "#{unsigned}.#{sig}"
  end

  defp verify_token(token, secret) do
    case String.split(token, ".") do
      [h, p, sig] ->
        unsigned = "#{h}.#{p}"
        expected = :crypto.mac(:hmac, :sha256, secret, unsigned) |> Base.url_encode64(padding: false)
        if Plug.Crypto.secure_compare(expected, sig) do
          claims = p |> Base.url_decode64!(padding: false) |> Jason.decode!()
          {:ok, claims}
        else
          {:error, :invalid_signature}
        end
      _ -> {:error, :malformed}
    end
  end

  defp config do
    cfg = Application.get_env(:koda, :livekit, [])
    [
      url:        Keyword.get(cfg, :url,        "http://localhost:7880"),
      api_key:    Keyword.get(cfg, :api_key,    "devkey"),
      api_secret: Keyword.get(cfg, :api_secret, "devsecret")
    ]
  end
end