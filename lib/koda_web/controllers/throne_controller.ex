defmodule KodaWeb.ThroneController do
  use KodaWeb, :controller
  alias Koda.Throne

  # Public -- called by Throne's servers, not a signed-in Koda user.
  # Must respond 2xx within Throne's 10-second timeout.
  def webhook(conn, %{"token" => token} = params) do
    creator = Throne.get_creator_by_token(token)
    raw     = conn.assigns[:raw_body] || ""
    ts      = get_req_header(conn, "x-signature-timestamp") |> List.first()
    sig     = get_req_header(conn, "x-signature-ed25519") |> List.first()

    cond do
      is_nil(creator) ->
        conn |> put_status(404) |> json(%{error: "Unknown webhook token"})

      not Throne.verify_webhook(raw, ts, sig) ->
        conn |> put_status(401) |> json(%{error: "Invalid signature"})

      true ->
        event = Map.drop(params, ["token"])
        case Throne.handle_event(creator, event) do
          {:ok, _} -> json(conn, %{ok: true})
          {:error, reason} ->
            conn |> put_status(422) |> json(%{error: inspect(reason)})
        end
    end
  end

  # Authenticated -- lets a creator find (or generate) the personal URL
  # they paste into their own Throne webhook settings.
  def webhook_url(conn, _params) do
    user  = Guardian.Plug.current_resource(conn)
    token = Throne.get_or_create_webhook_token(user)
    json(conn, %{webhook_url: build_url(token)})
  end

  def regenerate_webhook_url(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    case Throne.regenerate_webhook_token(user) do
      {:ok, updated} -> json(conn, %{webhook_url: build_url(updated.throne_webhook_token)})
      {:error, _}    -> conn |> put_status(500) |> json(%{error: "Could not regenerate"})
    end
  end

  defp build_url(token) do
    KodaWeb.Endpoint.url() <> "/api/v1/webhooks/throne/#{token}"
  end
end
