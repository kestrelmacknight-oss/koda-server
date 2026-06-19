defmodule Koda.Auth.Pipeline do
  use Guardian.Plug.Pipeline,
    otp_app:          :koda,
    error_handler:    Koda.Auth.ErrorHandler,
    module:           Koda.Auth.Guardian

  plug Guardian.Plug.VerifyHeader, scheme: "Bearer"
  plug Guardian.Plug.EnsureAuthenticated
  plug Guardian.Plug.LoadResource, allow_blank: false
end
