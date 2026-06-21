defmodule Koda.Scylla do
  @moduledoc "ScyllaDB connection pool supervisor."
  use Supervisor

  @pool_name :koda_scylla
  @keyspace  "koda"

  def start_link(_), do: Supervisor.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    cfg   = Application.get_env(:koda, :scylla, [])
    nodes = Keyword.get(cfg, :nodes, ["localhost:9042"])
    size  = Keyword.get(cfg, :pool_size, 5)
    transport_opts = Keyword.get(cfg, :transport_options, [])

    children = [
      {Xandra.Cluster, [
        name:              @pool_name,
        nodes:             nodes,
        pool_size:         size,
        keyspace:          @keyspace,
        transport_options: transport_opts,
        backoff_min:       1_000,
        backoff_max:       5_000
      ]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def pool, do: @pool_name

  def execute!(query, params \\ [], opts \\ []) do
    Xandra.Cluster.execute!(@pool_name, query, params, opts)
  end

  def execute(query, params \\ [], opts \\ []) do
    Xandra.Cluster.execute(@pool_name, query, params, opts)
  end

  def prepare!(query) do
    Xandra.Cluster.prepare!(@pool_name, query)
  end

  def run(fun) do
    Xandra.Cluster.run(@pool_name, fun)
  end

  # Bucket key for time-partitioned message storage (YYYYMM integer)
  def month_bucket(datetime \\ nil) do
    dt = datetime || DateTime.utc_now()
    dt.year * 100 + dt.month
  end
end