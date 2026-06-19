defmodule KodaWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg), do: Supervisor.start_link(__MODULE__, arg, name: __MODULE__)

  @impl true
  def init(_arg) do
    children =
      if Application.get_env(:koda, :env) == :prod do
        # Production: no console spam. Metrics still fire -- attach a
        # real backend (Fly metrics, StatsD, etc.) here when needed.
        []
      else
        [{Telemetry.Metrics.ConsoleReporter, metrics: metrics()}]
      end

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      summary("phoenix.endpoint.start.system_time", unit: {:native, :millisecond}),
      summary("phoenix.endpoint.stop.duration",     unit: {:native, :millisecond}),
      summary("phoenix.router_dispatch.stop.duration", tags: [:route], unit: {:native, :millisecond}),
      summary("koda.repo.query.total_time",         unit: {:native, :millisecond}),
    ]
  end
end
