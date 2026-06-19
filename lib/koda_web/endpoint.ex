defmodule KodaWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :koda

  @session_options [
    store:     :cookie,
    key:       "_koda_key",
    signing_salt: "koda_signing_salt",
    same_site: "Lax"
  ]

  socket "/socket", KodaWeb.UserSocket,
    websocket: [connect_info: [session: @session_options]],
    longpoll:  false

  plug CORSPlug

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers:    [:urlencoded, :multipart, :json],
    pass:       ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head

  plug Plug.Session, @session_options

  plug KodaWeb.Router
end
