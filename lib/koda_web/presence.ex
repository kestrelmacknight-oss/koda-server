defmodule KodaWeb.Presence do
  use Phoenix.Presence,
    otp_app: :koda,
    pubsub_server: Koda.PubSub
end
