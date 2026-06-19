defmodule KodaWeb.NotificationController do
  use KodaWeb, :controller
  alias Koda.Notifications

  def index(conn, params) do
    user = Guardian.Plug.current_resource(conn)
    unread_only = Map.get(params, "unread_only", false)
    notifs = Notifications.list(user.id, unread_only: unread_only)
    json(conn, %{notifications: notifs, unread_count: Notifications.unread_count(user.id)})
  end

  def mark_read(conn, %{"id" => id}) do
    Notifications.mark_read(id)
    json(conn, %{ok: true})
  end

  def mark_all_read(conn, _) do
    user = Guardian.Plug.current_resource(conn)
    Notifications.mark_all_read(user.id)
    json(conn, %{ok: true})
  end
end
