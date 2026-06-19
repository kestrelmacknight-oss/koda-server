defmodule KodaWeb.UserController do
  use KodaWeb, :controller

  def get_settings(conn, _) do
    json(conn, %{settings: %{
      notifications_enabled: true,
      theme: "dark",
      language: "en"
    }})
  end

  def update_settings(conn, _params) do
    json(conn, %{ok: true})
  end

  def update_profile(conn, params) do
    user = Guardian.Plug.current_resource(conn)
    allowed = Map.take(params, ["display_name", "avatar_url", "bio", "status"])
    case user |> Koda.Auth.User.update_changeset(allowed) |> Koda.Repo.update() do
      {:ok, updated} ->
        json(conn, %{user: %{
          id: updated.id, username: updated.username,
          display_name: updated.display_name, avatar_url: updated.avatar_url,
          bio: updated.bio, status: updated.status
        }})
      {:error, _} -> conn |> put_status(422) |> json(%{error: "Update failed"})
    end
  end
end
