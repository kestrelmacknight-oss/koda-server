defmodule KodaWeb.CacheBodyReader do
  @moduledoc """
  Caches the raw request body so Stripe webhook signature
  verification can access the original payload.
  """

  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
    conn = Plug.Conn.assign(conn, :raw_body, body)
    {:ok, body, conn}
  end
end
