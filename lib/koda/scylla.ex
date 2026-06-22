defmodule Koda.Scylla do
  @moduledoc "ScyllaDB connection pool supervisor."
  use Supervisor

  @pool_name :koda_scylla
  @keyspace  "koda"

  def start_link(_), do: Supervisor.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    cfg      = Application.get_env(:koda, :scylla, [])
    nodes    = Keyword.get(cfg, :nodes, ["localhost:9042"])
    size     = Keyword.get(cfg, :pool_size, 5)
    username = Keyword.get(cfg, :username)
    password = Keyword.get(cfg, :password)

    auth =
      if username && password do
        {Xandra.Authenticator.Password, [username: username, password: password]}
      else
        nil
      end

    children = [
      {Xandra.Cluster, [
        name:           @pool_name,
        nodes:          nodes,
        pool_size:      size,
        keyspace:       @keyspace,
        authentication: auth,
        backoff_min:    1_000,
        backoff_max:    5_000
      ]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def pool, do: @pool_name

  @doc """
  Kills and restarts the Xandra.Cluster child specifically, forcing a
  genuinely fresh connection attempt -- as opposed to waiting on
  whatever Cluster's own internal retry state is currently doing.
  Suspected fix for a process that decided early on it can't connect
  and never meaningfully retries discovery again on its own.
  """
  def force_reconnect! do
    case Supervisor.which_children(__MODULE__) do
      [{child_id, _pid, _type, _modules}] ->
        Supervisor.terminate_child(__MODULE__, child_id)
        Supervisor.restart_child(__MODULE__, child_id)

      other ->
        {:error, {:unexpected_children, other}}
    end
  end

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