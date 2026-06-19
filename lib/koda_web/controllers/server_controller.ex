defmodule KodaWeb.ServerController do
  use KodaWeb, :controller
  alias Koda.Servers

  def index(conn, _) do
    user = Guardian.Plug.current_resource(conn)
    servers = Servers.list_user_servers(user.id)
    json(conn, %{servers: Enum.map(servers, &server_json/1)})
  end

  def show(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)
    case Servers.get_server(id) do
      nil -> conn |> put_status(404) |> json(%{error: "Not found"})
      server ->
        if Servers.get_member(id, user.id) do
          json(conn, %{server: server_json(server)})
        else
          conn |> put_status(403) |> json(%{error: "Not a member"})
        end
    end
  end

  def create(conn, params) do
    user = Guardian.Plug.current_resource(conn)
    case Servers.create_server(user.id, params) do
      {:ok, server} -> conn |> put_status(201) |> json(%{server: server_json(server)})
      {:error, cs}  -> conn |> put_status(422) |> json(%{errors: format_errors(cs)})
    end
  end

  def update(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)
    with server = %{} <- Servers.get_server(id),
         true <- server.owner_id == user.id do
      case Servers.update_server(server, params) do
        {:ok, s}   -> json(conn, %{server: server_json(s)})
        {:error, cs} -> conn |> put_status(422) |> json(%{errors: format_errors(cs)})
      end
    else
      nil  -> conn |> put_status(404) |> json(%{error: "Not found"})
      false -> conn |> put_status(403) |> json(%{error: "Only the owner can update"})
    end
  end

  def delete(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)
    with server = %{} <- Servers.get_server(id),
         true <- server.owner_id == user.id do
      Servers.delete_server(server)
      json(conn, %{ok: true})
    else
      nil   -> conn |> put_status(404) |> json(%{error: "Not found"})
      false -> conn |> put_status(403) |> json(%{error: "Only the owner can delete"})
    end
  end

  def members(conn, %{"id" => id}) do
    case Servers.get_server(id) do
      nil -> conn |> put_status(404) |> json(%{error: "Not found"})
      _   ->
        members = Servers.list_members(id)
        json(conn, %{members: Enum.map(members, fn m ->
          %{member_id: m.id, user_id: m.user_id, username: m.user.username,
            avatar_url: m.user.avatar_url, is_subscriber: m.is_subscriber,
            roles: Enum.map(m.roles, fn r ->
              %{id: r.id, name: r.name, color: r.color}
            end)}
        end)})
    end
  end

  def leave(conn, %{"server_id" => id}) do
    user = Guardian.Plug.current_resource(conn)
    Servers.remove_member(id, user.id)
    json(conn, %{ok: true})
  end

  defp server_json(s) do
    %{id: s.id, name: s.name, description: s.description,
      icon_url: s.icon_url, is_public: s.is_public,
      category: s.category, member_count: s.member_count,
      owner_id: s.owner_id}
  end

  defp format_errors(cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, k ->
        opts |> Keyword.get(String.to_existing_atom(k), k) |> to_string()
      end)
    end)
  end
end
