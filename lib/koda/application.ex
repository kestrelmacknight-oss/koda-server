defmodule Koda.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Telemetry
      KodaWeb.Telemetry,
      # Database
      Koda.Repo,
      # Guardian token sweeper
      Guardian.DB.Token.SweeperServer,
      # PubSub
      {Phoenix.PubSub, name: Koda.PubSub},
      # Presence
      KodaWeb.Presence,
      # HTTP client
      {Finch, name: Koda.Finch},
      # Background jobs
      {Oban, Application.fetch_env!(:koda, Oban)},
      # DNS clustering (multi-node Fly deployments)
      {DNSCluster, query: Application.get_env(:koda, :dns_cluster_query) || :ignore},
      # ScyllaDB connection pool
      Koda.Scylla,
      Koda.Scylla.Prepared,
      # Web endpoint
      KodaWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Koda.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Apply ScyllaDB schema on first boot (idempotent)
    if Application.get_env(:koda, :env) == :prod do
      Koda.Scylla.Schema.setup!()
    end

    result
  end

  @impl true
  def config_change(changed, _new, removed) do
    KodaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
