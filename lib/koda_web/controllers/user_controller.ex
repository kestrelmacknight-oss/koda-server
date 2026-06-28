defmodule KodaWeb.UserController do
  use KodaWeb, :controller

  def get_settings(conn, _) do
    user = Guardian.Plug.current_resource(conn)
    json(conn, %{settings: user.settings || %{}})
  end

  # The client (SettingsNotifier.patch) merges section updates locally
  # and sends the complete, already-merged settings object every time --
  # so this just stores whatever map it receives wholesale, with no
  # server-side merge logic needed.
  def update_settings(conn, %{"settings" => settings}) when is_map(settings) do
    user = Guardian.Plug.current_resource(conn)

    case user |> Koda.Auth.User.settings_changeset(%{settings: settings}) |> Koda.Repo.update() do
      {:ok, updated} -> json(conn, %{settings: updated.settings})
      {:error, _}    -> conn |> put_status(422) |> json(%{error: "Update failed"})
    end
  end

  def update_settings(conn, _params) do
    conn |> put_status(400) |> json(%{error: "Missing settings object"})
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