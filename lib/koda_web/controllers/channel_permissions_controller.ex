defmodule KodaWeb.ChannelPermissionsController do
  use KodaWeb, :controller
  alias Koda.Servers

  def index(conn, %{"channel_id" => channel_id}) do
    allowed_role_ids = Servers.get_channel_allowed_roles(channel_id)
    json(conn, %{allowed_role_ids: allowed_role_ids})
  end

  def update(conn, %{"channel_id" => channel_id, "role_ids" => role_ids}) do
    user = Guardian.Plug.current_resource(conn)
    channel = Servers.get_channel(channel_id)

    unless channel && (Servers.owner?(channel.server_id, user.id) ||
           Servers.member_can?(channel.server_id, user.id, "manage_channels")) do
      conn |> put_status(403) |> json(%{error: "Not authorized"})
    else
      Servers.set_channel_allowed_roles(channel_id, role_ids)
      json(conn, %{ok: true})
    end
  end
end
