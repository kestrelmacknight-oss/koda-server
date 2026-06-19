defmodule KodaWeb.InviteController do
  use KodaWeb, :controller
  alias Koda.Invites

  def show(conn, %{"code" => code}) do
    case Invites.get_by_code(code) do
      nil    -> conn |> put_status(404) |> json(%{error: "Invalid invite"})
      invite ->
        json(conn, %{
          valid:        true,
          server:       %{
            id:           invite.server.id,
            name:         invite.server.name,
            description:  invite.server.description,
            icon_url:     invite.server.icon_url,
            member_count: invite.server.member_count
          }
        })
    end
  end

  def index(conn, %{"server_id" => server_id}) do
    invites = Invites.list_server_invites(server_id)
    json(conn, %{invites: Enum.map(invites, fn i ->
      %{id: i.id, code: i.code, is_permanent: i.is_permanent,
        uses: i.uses, max_uses: i.max_uses, expires_at: i.expires_at}
    end)})
  end

  def create(conn, %{"server_id" => server_id} = params) do
    user = Guardian.Plug.current_resource(conn)
    opts = []
    opts = if h = params["expires_in_hours"], do: Keyword.put(opts, :expires_in_hours, h), else: opts
    opts = if m = params["max_uses"],         do: Keyword.put(opts, :max_uses, m), else: opts

    case Invites.create_invite(server_id, user.id, opts) do
      {:ok, invite} -> json(conn, %{invite: %{id: invite.id, code: invite.code}})
      {:error, _}   -> conn |> put_status(422) |> json(%{error: "Could not create invite"})
    end
  end

  def join(conn, %{"code" => code}) do
    user = Guardian.Plug.current_resource(conn)
    case Invites.use_invite(code, user.id) do
      {:ok, invite}              -> json(conn, %{server_id: invite.server_id})
      {:error, :already_member}  -> conn |> put_status(422) |> json(%{error: "Already a member"})
      {:error, :expired}         -> conn |> put_status(422) |> json(%{error: "Invite expired"})
      {:error, :max_uses_reached}-> conn |> put_status(422) |> json(%{error: "Invite is full"})
      {:error, :not_found}       -> conn |> put_status(404) |> json(%{error: "Invalid invite"})
    end
  end

  def delete(conn, %{"id" => id}) do
    Invites.delete_invite(id)
    json(conn, %{ok: true})
  end
end
