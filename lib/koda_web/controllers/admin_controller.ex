defmodule KodaWeb.AdminController do
  use KodaWeb, :controller
  import Ecto.Query
  alias Koda.{Repo, Auth}

  def search_users(conn, %{"q" => query}) do
    user = Guardian.Plug.current_resource(conn)

    unless user.is_admin do
      conn |> put_status(403) |> json(%{error: "Admin only"})
    else
      results = Repo.all(
        from u in Auth.User,
        where: ilike(u.username, ^"%#{query}%") or ilike(u.email, ^"%#{query}%"),
        limit: 20,
        select: %{
          id:         u.id,
          username:   u.username,
          email:      u.email,
          avatar_url: u.avatar_url,
          flags:      u.flags,
          is_admin:   u.is_admin
        }
      )
      json(conn, %{users: results})
    end
  end

  def search_users(conn, _), do: conn |> put_status(400) |> json(%{error: "q parameter required"})
end
