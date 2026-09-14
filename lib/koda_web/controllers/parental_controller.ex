defmodule KodaWeb.ParentalController do
  use KodaWeb, :controller
  alias Koda.Parental

  # ── Child account creation & linking ────────────────────────────────────

  def create_child(conn, params) do
    parent = Guardian.Plug.current_resource(conn)
    case Parental.create_child_account(parent, params) do
      {:ok, child} -> conn |> put_status(201) |> json(%{child: child_json(child)})
      {:error, cs} -> conn |> put_status(422) |> json(%{errors: format_errors(cs)})
    end
  end

  def list_children(conn, _params) do
    parent = Guardian.Plug.current_resource(conn)
    children = Parental.list_children(parent.id)
    json(conn, %{children: Enum.map(children, &child_json/1)})
  end

  # ── Friends (read-only, remove-only -- never message content) ──────────

  def child_friends(conn, %{"child_id" => child_id}) do
    parent = Guardian.Plug.current_resource(conn)
    case Parental.list_child_friends(parent.id, child_id) do
      {:ok, friends} -> json(conn, %{friends: Enum.map(friends, &child_json/1)})
      {:error, :not_authorized} -> conn |> put_status(403) |> json(%{error: "Not authorized"})
    end
  end

  def remove_child_friend(conn, %{"child_id" => child_id, "friend_id" => friend_id}) do
    parent = Guardian.Plug.current_resource(conn)
    case Parental.remove_child_friend(parent.id, child_id, friend_id) do
      :ok -> json(conn, %{ok: true})
      {:error, :not_authorized} -> conn |> put_status(403) |> json(%{error: "Not authorized"})
    end
  end

  # ── Servers (read-only, remove-only) ────────────────────────────────────

  def child_servers(conn, %{"child_id" => child_id}) do
    parent = Guardian.Plug.current_resource(conn)
    case Parental.list_child_servers(parent.id, child_id) do
      {:ok, servers} -> json(conn, %{servers: Enum.map(servers, &server_json/1)})
      {:error, :not_authorized} -> conn |> put_status(403) |> json(%{error: "Not authorized"})
    end
  end

  def remove_child_from_server(conn, %{"child_id" => child_id, "server_id" => server_id}) do
    parent = Guardian.Plug.current_resource(conn)
    case Parental.remove_child_from_server(parent.id, child_id, server_id) do
      :ok -> json(conn, %{ok: true})
      {:error, :not_authorized} -> conn |> put_status(403) |> json(%{error: "Not authorized"})
      {:error, :not_found} -> conn |> put_status(404) |> json(%{error: "Not a member"})
    end
  end

  # ── Schedule ─────────────────────────────────────────────────────────────

  def get_schedule(conn, %{"child_id" => child_id}) do
    parent = Guardian.Plug.current_resource(conn)
    if Parental.parent_of?(parent.id, child_id) do
      json(conn, %{schedule: schedule_json(Parental.get_schedule(child_id))})
    else
      conn |> put_status(403) |> json(%{error: "Not authorized"})
    end
  end

  def put_schedule(conn, %{"child_id" => child_id} = params) do
    parent = Guardian.Plug.current_resource(conn)
    case Parental.upsert_schedule(parent.id, child_id, params) do
      {:ok, schedule} -> json(conn, %{schedule: schedule_json(schedule)})
      {:error, :not_authorized} -> conn |> put_status(403) |> json(%{error: "Not authorized"})
      {:error, cs} -> conn |> put_status(422) |> json(%{errors: format_errors(cs)})
    end
  end

  def delete_schedule(conn, %{"child_id" => child_id}) do
    parent = Guardian.Plug.current_resource(conn)
    case Parental.delete_schedule(parent.id, child_id) do
      :ok -> json(conn, %{ok: true})
      {:error, :not_authorized} -> conn |> put_status(403) |> json(%{error: "Not authorized"})
    end
  end

  # ── Overrides ────────────────────────────────────────────────────────────

  def create_override(conn, %{"child_id" => child_id} = params) do
    parent = Guardian.Plug.current_resource(conn)
    case Parental.grant_override(parent.id, child_id, params) do
      {:ok, override} -> conn |> put_status(201) |> json(%{override: override_json(override)})
      {:error, :not_authorized} -> conn |> put_status(403) |> json(%{error: "Not authorized"})
      {:error, cs} -> conn |> put_status(422) |> json(%{errors: format_errors(cs)})
    end
  end

  def delete_override(conn, %{"child_id" => child_id}) do
    parent = Guardian.Plug.current_resource(conn)
    case Parental.revoke_override(parent.id, child_id) do
      :ok -> json(conn, %{ok: true})
      {:error, :not_authorized} -> conn |> put_status(403) |> json(%{error: "Not authorized"})
    end
  end

  # ── JSON helpers ─────────────────────────────────────────────────────────

  defp child_json(u) do
    %{id: u.id, username: u.username, avatar_url: u.avatar_url,
      account_type: u.account_type || "standard"}
  end

  defp server_json(s) do
    %{id: s.id, name: s.name, icon_url: s.icon_url, member_count: s.member_count}
  end

  defp schedule_json(nil), do: nil
  defp schedule_json(s), do: %{timezone: s.timezone, windows: s.windows}

  defp override_json(o) do
    %{id: o.id, expires_at: DateTime.to_iso8601(o.expires_at), reason: o.reason}
  end

  defp format_errors(cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, k ->
        opts |> Keyword.get(String.to_existing_atom(k), k) |> to_string()
      end)
    end)
  end
end
