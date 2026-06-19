defmodule KodaWeb.LiveKitWebhookController do
  use KodaWeb, :controller
  alias Koda.Voice.LiveKit
  alias Koda.Voice

  def webhook(conn, _params) do
    {:ok, body, _} = Plug.Conn.read_body(conn)
    authorization  = conn |> get_req_header("authorization") |> List.first("") 

    case LiveKit.verify_webhook(body, authorization) do
      {:ok, event} ->
        Task.start(fn -> Voice.handle_webhook(event) end)
        json(conn, %{received: true})

      {:error, _} ->
        conn |> put_status(401) |> json(%{error: "Unauthorized"})
    end
  end
end
