defmodule KodaWeb.RoleController do
  use KodaWeb, :controller
  alias Koda.Servers

  def index(conn, %{"server_id" => server_id}) do
    roles = Servers.list_roles(server_id)
    json(conn, %{roles: Enum.map(roles, &role_json/1)})
  end

  def create(conn, %{"server_id" => server_id} = params) do
    user = Guardian.Plug.current_resource(conn)

    if Servers.owner?(server_id, user.id) or Servers.member_can?(server_id, user.id, "manage_roles") do
      case Servers.create_role(server_id, params) do
        {:ok, role}  -> conn |> put_status(201) |> json(%{role: role_json(role)})
        {:error, cs} -> conn |> put_status(422) |> json(%{errors: format_errors(cs)})
      end
    else
      conn |> put_status(403) |> json(%{error: "Not authorized to manage roles"})
    end
  end

  def update(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)
    case Servers.get_role(id) do
      nil -> conn |> put_status(404) |> json(%{error: "Not found"})
      role ->
        if Servers.owner?(role.server_id, user.id) or
           Servers.member_can?(role.server_id, user.id, "manage_roles") do
          case Servers.update_role(role, params) do
            {:ok, updated} -> json(conn, %{role: role_json(updated)})
            {:error, cs}   -> conn |> put_status(422) |> json(%{errors: format_errors(cs)})
          end
        else
          conn |> put_status(403) |> json(%{error: "Not authorized to manage roles"})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)
    case Servers.get_role(id) do
      nil -> conn |> put_status(404) |> json(%{error: "Not found"})
      role ->
        if Servers.owner?(role.server_id, user.id) or
           Servers.member_can?(role.server_id, user.id, "manage_roles") do
          case Servers.delete_role(role) do
            {:ok, _}    -> json(conn, %{ok: true})
            {:error, :cannot_delete_default_role} ->
              conn |> put_status(422) |> json(%{error: "Cannot delete the default role"})
          end
        else
          conn |> put_status(403) |> json(%{error: "Not authorized to manage roles"})
        end
    end
  end

  def assign(conn, %{"member_id" => member_id, "role_id" => role_id}) do
    user = Guardian.Plug.current_resource(conn)
    case Servers.get_member_by_id(member_id) do
      nil -> conn |> put_status(404) |> json(%{error: "Member not found"})
      member ->
        if Servers.owner?(member.server_id, user.id) or
           Servers.member_can?(member.server_id, user.id, "manage_roles") do
          Servers.assign_role(member_id, role_id)
          json(conn, %{ok: true})
        else
          conn |> put_status(403) |> json(%{error: "Not authorized to manage roles"})
        end
    end
  end

  def unassign(conn, %{"member_id" => member_id, "role_id" => role_id}) do
    user = Guardian.Plug.current_resource(conn)
    case Servers.get_member_by_id(member_id) do
      nil -> conn |> put_status(404) |> json(%{error: "Member not found"})
      member ->
        if Servers.owner?(member.server_id, user.id) or
           Servers.member_can?(member.server_id, user.id, "manage_roles") do
          Servers.remove_role(member_id, role_id)
          json(conn, %{ok: true})
        else
          conn |> put_status(403) |> json(%{error: "Not authorized to manage roles"})
        end
    end
  end

  defp role_json(r) do
    %{id: r.id, name: r.name, color: r.color, position: r.position,
      is_default: r.is_default, permissions: r.permissions}
  end

  defp format_errors(cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, k ->
        opts |> Keyword.get(String.to_existing_atom(k), k) |> to_string()
      end)
    end)
  end
end
