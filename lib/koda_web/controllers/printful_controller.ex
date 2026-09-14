defmodule KodaWeb.PrintfulController do
  use KodaWeb, :controller
  require Logger
  alias Koda.{Printful, Servers}

  defp can_manage?(server_id, user_id) do
    Servers.owner?(server_id, user_id) or
      Servers.member_can?(server_id, user_id, "manage_marketplace")
  end

  def connect(conn, %{"server_id" => server_id}) do
    user = Guardian.Plug.current_resource(conn)
    if can_manage?(server_id, user.id) do
      json(conn, %{authorize_url: Printful.authorize_url(server_id, user.id)})
    else
      conn |> put_status(403) |> json(%{error: "Not authorized"})
    end
  end

  # Public -- Printful redirects the customer's browser here directly,
  # with no Koda auth attached. state (a signed Phoenix.Token, see
  # Koda.Printful.authorize_url/2) is what proves this request actually
  # started from an authorized connect/2 call for a specific server.
  def callback(conn, %{"code" => code, "state" => state}) do
    case Printful.handle_callback(code, state) do
      {:ok, _connection} ->
        redirect(conn, external: "https://koda.fyi/creator/printful-connected")

      {:error, reason} ->
        Logger.warning("[Printful] callback failed: #{inspect(reason)}")
        redirect(conn, external: "https://koda.fyi/creator/printful-failed")
    end
  end

  def callback(conn, _params) do
    redirect(conn, external: "https://koda.fyi/creator/printful-failed")
  end

  def status(conn, %{"server_id" => server_id}) do
    json(conn, %{connected: Printful.connected?(server_id)})
  end

  def disconnect(conn, %{"server_id" => server_id}) do
    user = Guardian.Plug.current_resource(conn)
    if can_manage?(server_id, user.id) do
      Printful.disconnect(server_id)
      json(conn, %{ok: true})
    else
      conn |> put_status(403) |> json(%{error: "Not authorized"})
    end
  end
end
