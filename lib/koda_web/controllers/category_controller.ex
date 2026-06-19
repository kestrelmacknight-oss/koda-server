defmodule KodaWeb.CategoryController do
  use KodaWeb, :controller
  alias Koda.Servers

  def index(conn, %{"server_id" => server_id}) do
    categories = Servers.list_categories(server_id)
    json(conn, %{categories: Enum.map(categories, &category_json/1)})
  end

  def create(conn, %{"server_id" => server_id} = params) do
    user = Guardian.Plug.current_resource(conn)
    if Servers.owner?(server_id, user.id) or Servers.member_can?(server_id, user.id, "manage_channels") do
      case Servers.create_category(server_id, params) do
        {:ok, cat}   -> conn |> put_status(201) |> json(%{category: category_json(cat)})
        {:error, cs} -> conn |> put_status(422) |> json(%{errors: format_errors(cs)})
      end
    else
      conn |> put_status(403) |> json(%{error: "Not authorized"})
    end
  end

  def update(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)
    case Servers.get_category(id) do
      nil -> conn |> put_status(404) |> json(%{error: "Not found"})
      cat ->
        if Servers.owner?(cat.server_id, user.id) or
           Servers.member_can?(cat.server_id, user.id, "manage_channels") do
          case Servers.update_category(cat, params) do
            {:ok, updated} -> json(conn, %{category: category_json(updated)})
            {:error, cs}   -> conn |> put_status(422) |> json(%{errors: format_errors(cs)})
          end
        else
          conn |> put_status(403) |> json(%{error: "Not authorized"})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)
    case Servers.get_category(id) do
      nil -> conn |> put_status(404) |> json(%{error: "Not found"})
      cat ->
        if Servers.owner?(cat.server_id, user.id) or
           Servers.member_can?(cat.server_id, user.id, "manage_channels") do
          Servers.delete_category(cat)
          json(conn, %{ok: true})
        else
          conn |> put_status(403) |> json(%{error: "Not authorized"})
        end
    end
  end

  defp category_json(c) do
    %{id: c.id, name: c.name, position: c.position, server_id: c.server_id}
  end

  defp format_errors(cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, k ->
        opts |> Keyword.get(String.to_existing_atom(k), k) |> to_string()
      end)
    end)
  end
end
