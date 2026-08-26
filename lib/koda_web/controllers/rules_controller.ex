defmodule KodaWeb.RulesController do
  use KodaWeb, :controller
  alias Koda.{Servers, Repo}
  import Ecto.Query

  # Get server rules (rules channel content)
  def get_rules(conn, %{"server_id" => server_id}) do
    channel = Repo.one(
      from c in Koda.Servers.Channel,
      where: c.server_id == ^server_id and c.type == "rules",
      limit: 1
    )
    if channel do
      json(conn, %{
        rules:    Map.get(channel, :rules_content),
        accepted: Servers.rules_accepted?(server_id, Guardian.Plug.current_resource(conn).id)
      })
    else
      json(conn, %{rules: nil, accepted: true})
    end
  end

  # Accept server rules
  def accept_rules(conn, %{"server_id" => server_id}) do
    user = Guardian.Plug.current_resource(conn)
    case Servers.accept_rules(server_id, user.id) do
      {:ok, _}    -> json(conn, %{ok: true})
      {:error, e} -> conn |> put_status(422) |> json(%{error: inspect(e)})
    end
  end

  # Update rules content (admin/mod only)
  def update_rules(conn, %{"server_id" => server_id, "content" => content}) do
    user = Guardian.Plug.current_resource(conn)
    unless Servers.owner?(server_id, user.id) or
           Servers.member_can?(server_id, user.id, "manage_server") do
      conn |> put_status(403) |> json(%{error: "Not authorized"})
    else
      channel = Repo.one(
        from c in Koda.Servers.Channel,
        where: c.server_id == ^server_id and c.type == "rules",
        limit: 1
      )
      if channel do
        channel
        |> Ecto.Changeset.change(rules_content: content)
        |> Repo.update()
        json(conn, %{ok: true})
      else
        conn |> put_status(404) |> json(%{error: "No rules channel found"})
      end
    end
  end

  # List self-assignable roles for a server
  def self_assignable_roles(conn, %{"server_id" => server_id}) do
    roles = Repo.all(
      from r in Koda.Servers.Role,
      where: r.server_id == ^server_id and r.self_assignable == true
    )
    json(conn, %{roles: Enum.map(roles, fn r ->
      %{id: r.id, name: r.name, color: r.color}
    end)})
  end

  # Self-assign a role
  def assign_role(conn, %{"server_id" => server_id, "role_id" => role_id}) do
    user = Guardian.Plug.current_resource(conn)
    case Servers.assign_role(server_id, user.id, role_id) do
      {:ok, _}                   -> json(conn, %{ok: true})
      {:error, :not_found}       -> conn |> put_status(404) |> json(%{error: "Role not found"})
      {:error, :not_self_assignable} -> conn |> put_status(403) |> json(%{error: "Role is not self-assignable"})
      {:error, e}                -> conn |> put_status(422) |> json(%{error: inspect(e)})
    end
  end

  # Remove a self-assigned role
  def unassign_role(conn, %{"server_id" => server_id, "role_id" => role_id}) do
    user = Guardian.Plug.current_resource(conn)
    case Servers.unassign_role(server_id, user.id, role_id) do
      {:ok, _}                   -> json(conn, %{ok: true})
      {:error, :not_self_assignable} -> conn |> put_status(403) |> json(%{error: "Role is not self-assignable"})
      {:error, e}                -> conn |> put_status(422) |> json(%{error: inspect(e)})
    end
  end
end
