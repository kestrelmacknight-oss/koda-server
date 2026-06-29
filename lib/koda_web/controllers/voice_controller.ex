defmodule KodaWeb.VoiceController do
  use KodaWeb, :controller
  alias Koda.Voice

  def token(conn, %{"channel_id" => channel_id}) do
    user = Guardian.Plug.current_resource(conn)
    case Voice.join_token(channel_id, user) do
      {:ok, payload}              -> json(conn, payload)
      {:error, :channel_not_found}-> conn |> put_status(404) |> json(%{error: "Channel not found"})
      {:error, :unauthorized}     -> conn |> put_status(403) |> json(%{error: "Not a member"})
      {:error, :not_a_voice_channel}-> conn |> put_status(422) |> json(%{error: "Not a voice channel"})
    end
  end

  def participants(conn, %{"channel_id" => channel_id}) do
    case Voice.list_participants(channel_id) do
      {:ok, ps} -> json(conn, %{participants: ps})
      {:error, _} -> json(conn, %{participants: []})
    end
  end

  # Private, user-scoped room for the device test screen -- not tied to
  # any real channel, so it skips the channel/membership checks join_token
  # does. Room name is unique per user ("koda-selftest-<user_id>"), so no
  # one else would ever join it.
  def self_test_token(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    synthetic_id = "selftest-#{user.id}"
    token = Koda.Voice.LiveKit.generate_token(user, synthetic_id)
    url = Application.get_env(:koda, :livekit, [])
          |> Keyword.get(:public_url, "ws://localhost:7880")
    json(conn, %{token: token, url: url, room: Koda.Voice.LiveKit.room_name(synthetic_id)})
  end
end