defmodule KodaWeb.DiscoverController do
  use KodaWeb, :controller

  def index(conn, params) do
    servers = Koda.Servers.discover_servers(
      query:    params["q"],
      category: params["category"],
      limit:    String.to_integer(params["limit"] || "24")
    )
    json(conn, %{servers: servers})
  end
end
