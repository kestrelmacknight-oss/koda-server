defmodule KodaWeb.CategoryPermissionsController do
  use KodaWeb, :controller
  alias Koda.Servers

  def index(conn, %{"category_id" => category_id}) do
    allowed_role_ids = Servers.get_category_allowed_roles(category_id)
    json(conn, %{allowed_role_ids: allowed_role_ids})
  end

  def update(conn, %{"category_id" => category_id, "role_ids" => role_ids}) do
    user = Guardian.Plug.current_resource(conn)
    category = Servers.get_category(category_id)

    unless category && (Servers.owner?(category.server_id, user.id) ||
           Servers.member_can?(category.server_id, user.id, "manage_channels")) do
      conn |> put_status(403) |> json(%{error: "Not authorized"})
    else
      Servers.set_category_allowed_roles(category_id, role_ids)
      json(conn, %{ok: true})
    end
  end
end
