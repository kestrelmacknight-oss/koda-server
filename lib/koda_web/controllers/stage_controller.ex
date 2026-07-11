defmodule KodaWeb.StageController do
  use KodaWeb, :controller
  alias Koda.{Servers, Voice}

  # Join a stage channel as a listener (can_publish: false by default).
  # Speakers are promoted separately via the grant endpoint.
  def join(conn, %{"channel_id" => channel_id}) do
    user    = Guardian.Plug.current_resource(conn)
    channel = Servers.get_channel(channel_id)

    cond do
      is_nil(channel) ->
        conn |> put_status(404) |> json(%{error: "Channel not found"})
      channel.type != "stage" ->
        conn |> put_status(422) |> json(%{error: "Not a stage channel"})
      is_nil(Servers.get_member(channel.server_id, user.id)) ->
        conn |> put_status(403) |> json(%{error: "Not a member"})
      true ->
        is_admin = Servers.owner?(channel.server_id, user.id) or
                   Servers.member_can?(channel.server_id, user.id, "manage_server")

        # Admins and owners join as speakers; everyone else joins as listeners.
        token = Voice.LiveKit.generate_token(user, channel_id,
                  can_publish: is_admin)

        url = Application.get_env(:koda, :livekit, [])
              |> Keyword.get(:public_url, "wss://voice.koda.fyi")

        json(conn, %{
          token:     token,
          url:       url,
          room:      Voice.LiveKit.room_name(channel_id),
          is_speaker: is_admin
        })
    end
  end

  # Listener raises hand to request speaking permission.
  # Broadcasts via PubSub so the stage host sees it in real time.
  def raise_hand(conn, %{"channel_id" => channel_id}) do
    user    = Guardian.Plug.current_resource(conn)
    channel = Servers.get_channel(channel_id)

    if channel && Servers.get_member(channel.server_id, user.id) do
      Phoenix.PubSub.broadcast(Koda.PubSub, "stage:#{channel_id}",
        {:hand_raised, %{user_id: user.id, username: user.username}})
      json(conn, %{ok: true})
    else
      conn |> put_status(403) |> json(%{error: "Not authorized"})
    end
  end

  # Lower hand (cancel request).
  def lower_hand(conn, %{"channel_id" => channel_id}) do
    user = Guardian.Plug.current_resource(conn)
    Phoenix.PubSub.broadcast(Koda.PubSub, "stage:#{channel_id}",
      {:hand_lowered, user.id})
    json(conn, %{ok: true})
  end

  # Grant speaking permission (admin/owner only).
  def grant_speaker(conn, %{"channel_id" => channel_id, "user_id" => target_user_id}) do
    user    = Guardian.Plug.current_resource(conn)
    channel = Servers.get_channel(channel_id)

    if channel && (Servers.owner?(channel.server_id, user.id) or
                   Servers.member_can?(channel.server_id, user.id, "manage_server")) do
      case Voice.LiveKit.update_participant_permission(channel_id, target_user_id, true) do
        {:ok, _} ->
          Phoenix.PubSub.broadcast(Koda.PubSub, "stage:#{channel_id}",
            {:speaker_granted, target_user_id})
          json(conn, %{ok: true})
        {:error, reason} ->
          conn |> put_status(500) |> json(%{error: "Failed: #{inspect(reason)}"})
      end
    else
      conn |> put_status(403) |> json(%{error: "Only admins can grant speaking"})
    end
  end

  # Revoke speaking permission (admin/owner only, or the speaker themselves).
  def revoke_speaker(conn, %{"channel_id" => channel_id, "user_id" => target_user_id}) do
    user    = Guardian.Plug.current_resource(conn)
    channel = Servers.get_channel(channel_id)
    is_self = user.id == target_user_id

    if channel && (is_self or
                   Servers.owner?(channel.server_id, user.id) or
                   Servers.member_can?(channel.server_id, user.id, "manage_server")) do
      case Voice.LiveKit.update_participant_permission(channel_id, target_user_id, false) do
        {:ok, _} ->
          Phoenix.PubSub.broadcast(Koda.PubSub, "stage:#{channel_id}",
            {:speaker_revoked, target_user_id})
          json(conn, %{ok: true})
        {:error, reason} ->
          conn |> put_status(500) |> json(%{error: "Failed: #{inspect(reason)}"})
      end
    else
      conn |> put_status(403) |> json(%{error: "Not authorized"})
    end
  end
end