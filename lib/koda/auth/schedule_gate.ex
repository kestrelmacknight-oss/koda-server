defmodule Koda.Auth.ScheduleGate do
  @moduledoc """
  Authoritative gate for a child account's weekly access schedule,
  applied to every already-authenticated request. Login-time rejection
  (Koda.Auth.login/2) only stops a *new* login outside the window -- a
  JWT issued before the window closed stays valid, so this plug is what
  actually enforces the boundary for the rest of a session's REST calls.

  Runs after Koda.Auth.Pipeline in the :auth pipeline, so
  Guardian.Plug.current_resource/1 is already populated.
  """
  import Plug.Conn

  # A forced password change must always be reachable, even outside the
  # child's allowed hours -- narrow, non-content-bearing, and otherwise
  # a child with must_change_password set could be permanently stuck.
  @exempt_suffix "/auth/password/force_change"

  def init(opts), do: opts

  def call(conn, _opts) do
    if String.ends_with?(conn.request_path, @exempt_suffix) do
      conn
    else
      case Guardian.Plug.current_resource(conn) do
        %{account_type: "child"} = user ->
          if Koda.Parental.allowed_now?(user), do: conn, else: reject(conn)

        _ ->
          conn
      end
    end
  end

  defp reject(conn) do
    body = Jason.encode!(%{error: "outside_allowed_hours"})
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(403, body)
    |> halt()
  end
end
