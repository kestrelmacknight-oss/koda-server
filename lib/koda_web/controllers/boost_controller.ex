defmodule KodaWeb.BoostController do
  use KodaWeb, :controller
  alias Koda.Boosts

  def my_tokens(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    tokens = Boosts.list_available_tokens(user.id)
    json(conn, %{
      tokens: Enum.map(tokens, fn t ->
        %{id: t.id, expires_at: DateTime.to_iso8601(t.expires_at)}
      end)
    })
  end

  def boost(conn, %{"server_id" => server_id}) do
    user = Guardian.Plug.current_resource(conn)

    case Koda.Servers.get_member(server_id, user.id) do
      nil ->
        conn |> put_status(403) |> json(%{error: "You must be a member of this server to boost it"})

      _member ->
        case Boosts.redeem_boost(user.id, server_id) do
          {:ok, boost} ->
            conn |> put_status(201) |> json(%{
              boost: %{
                id: boost.id,
                server_id: boost.server_id,
                expires_at: DateTime.to_iso8601(boost.expires_at)
              },
              status: Boosts.server_boost_status(server_id)
            })

          {:error, :no_tokens_available} ->
            conn |> put_status(422) |> json(%{error: "You have no boost tokens available"})
        end
    end
  end

  def status(conn, %{"server_id" => server_id}) do
    json(conn, Boosts.server_boost_status(server_id))
  end
end
