defmodule KodaWeb.InviteController do
  use KodaWeb, :controller
  alias Koda.{Invites, Servers}

  # -- Server invites ----------------------------------------------------------

  def create(conn, %{"server_id" => server_id} = params) do
    user = Guardian.Plug.current_resource(conn)

    if Servers.owner?(server_id, user.id) or
       Servers.member_can?(server_id, user.id, "manage_server") do
      opts = []
      opts = if params["max_uses"],  do: [{:max_uses, params["max_uses"]}  | opts], else: opts
      opts = if params["expires_at"], do: [{:expires_at, parse_dt(params["expires_at"])} | opts], else: opts

      case Invites.create_invite(server_id, user.id, opts) do
        {:ok, invite} ->
          conn |> put_status(201) |> json(%{invite: invite_json(invite)})
        {:error, cs} ->
          conn |> put_status(422) |> json(%{error: format_errors(cs)})
      end
    else
      conn |> put_status(403) |> json(%{error: "Not authorized"})
    end
  end

  def list(conn, %{"server_id" => server_id}) do
    user = Guardian.Plug.current_resource(conn)

    if Servers.owner?(server_id, user.id) or
       Servers.member_can?(server_id, user.id, "manage_server") do
      invites = Invites.list_invites(server_id)
      json(conn, %{invites: Enum.map(invites, &invite_json/1)})
    else
      conn |> put_status(403) |> json(%{error: "Not authorized"})
    end
  end

  def delete(conn, %{"server_id" => _server_id, "code" => code}) do
    user = Guardian.Plug.current_resource(conn)

    case Invites.get_invite_by_code(code) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Invite not found"})
      invite ->
        if Servers.owner?(invite.server_id, user.id) or
           Servers.member_can?(invite.server_id, user.id, "manage_server") do
          Invites.delete_invite(invite)
          json(conn, %{ok: true})
        else
          conn |> put_status(403) |> json(%{error: "Not authorized"})
        end
    end
  end

  # -- Invite redemption (joining a server via code) ---------------------------

  def redeem(conn, %{"code" => code}) do
    user = Guardian.Plug.current_resource(conn)

    case Invites.redeem_invite(code, user.id) do
      {:ok, server} ->
        json(conn, %{ok: true, server: %{
          id:   server.id,
          name: server.name
        }})
      {:error, :invalid_code}    -> conn |> put_status(404) |> json(%{error: "Invalid invite code"})
      {:error, :expired}         -> conn |> put_status(410) |> json(%{error: "This invite has expired"})
      {:error, :max_uses_reached}-> conn |> put_status(410) |> json(%{error: "This invite has reached its maximum uses"})
      {:error, _}                -> conn |> put_status(500) |> json(%{error: "Could not join server"})
    end
  end

  # -- Backer code redemption --------------------------------------------------

  def redeem_backer(conn, %{"code" => code}) do
    user = Guardian.Plug.current_resource(conn)

    case Invites.redeem_backer_code(code, user.id) do
      {:ok, _} ->
        json(conn, %{ok: true, message: "Code redeemed successfully"})
      {:error, :invalid_code}    -> conn |> put_status(404) |> json(%{error: "Invalid code"})
      {:error, :already_redeemed}-> conn |> put_status(409) |> json(%{error: "You have already redeemed this code"})
      {:error, :expired}         -> conn |> put_status(410) |> json(%{error: "This code has expired"})
      {:error, :max_uses_reached}-> conn |> put_status(410) |> json(%{error: "This code has reached its maximum uses"})
      {:error, _}                -> conn |> put_status(500) |> json(%{error: "Could not redeem code"})
    end
  end

  # -- Admin: backer code management -------------------------------------------

  def create_backer(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    unless user.is_admin do
      conn |> put_status(403) |> json(%{error: "Admin only"})
    else
      attrs = [
        flags:      params["flags"]      || %{},
        note:       params["note"],
        max_uses:   params["max_uses"],
        code:       params["code"],
        expires_at: params["expires_at"] && parse_dt(params["expires_at"])
      ]

      case Invites.create_backer_code(user.id, attrs) do
        {:ok, code} ->
          conn |> put_status(201) |> json(%{backer_code: %{
            id:       code.id,
            code:     code.code,
            flags:    code.flags,
            note:     code.note,
            max_uses: code.max_uses,
            uses:     code.uses
          }})
        {:error, cs} ->
          conn |> put_status(422) |> json(%{error: format_errors(cs)})
      end
    end
  end

  def list_backer(conn, _params) do
    user = Guardian.Plug.current_resource(conn)

    unless user.is_admin do
      conn |> put_status(403) |> json(%{error: "Admin only"})
    else
      codes = Invites.list_backer_codes()
      json(conn, %{backer_codes: Enum.map(codes, fn c ->
        %{id: c.id, code: c.code, flags: c.flags,
          note: c.note, uses: c.uses, max_uses: c.max_uses}
      end)})
    end
  end

  # -- Helpers -----------------------------------------------------------------

  defp invite_json(invite) do
    %{
      code:       invite.code,
      server_id:  invite.server_id,
      uses:       invite.uses,
      max_uses:   invite.max_uses,
      expires_at: invite.expires_at,
      url:        "https://koda.fyi/invite/#{invite.code}"
    }
  end

  defp parse_dt(nil), do: nil
  defp parse_dt(s) when is_binary(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _} -> dt
      _            -> nil
    end
  end

  defp format_errors(cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, _} -> msg end)
  end
end