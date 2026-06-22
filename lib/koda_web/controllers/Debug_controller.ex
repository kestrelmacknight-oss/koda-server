defmodule KodaWeb.DebugController do
  use KodaWeb, :controller

  # TEMPORARY -- added specifically to inspect the live Koda.Scylla /
  # Xandra.Cluster connection state via a normal HTTPS request,
  # sidestepping the need for distributed-Erlang remote console access
  # (which hit its own IPv6 node-naming complication). Remove this
  # controller and its route once the Scylla connection issue is
  # actually resolved -- this is a diagnostic tool, not a real feature.

  def scylla(conn, _params) do
    scylla_pid   = Process.whereis(Koda.Scylla)
    cluster_pid  = Process.whereis(:koda_scylla)

    query_result =
      try do
        Xandra.Cluster.execute(:koda_scylla, "SELECT now() FROM system.local")
      rescue
        e -> {:rescued, Exception.format(:error, e, __STACKTRACE__)}
      catch
        kind, reason -> {:caught, kind, inspect(reason)}
      end

    config = Application.get_env(:koda, :scylla, [])

    json(conn, %{
      koda_scylla_supervisor_pid: inspect(scylla_pid),
      xandra_cluster_pid:         inspect(cluster_pid),
      config:                     inspect(config),
      query_result:               inspect(query_result)
    })
  end

  @doc """
  TEMPORARY -- kills and restarts the Xandra.Cluster child specifically,
  to test whether the persistent connection issue is a process stuck in
  a bad internal state rather than a real config/network problem.
  """
  def force_reconnect(conn, _params) do
    result = Koda.Scylla.force_reconnect!()
    # Give the freshly-restarted Cluster a moment to actually connect
    # before immediately querying it.
    Process.sleep(3_000)

    query_result =
      try do
        Xandra.Cluster.execute(:koda_scylla, "SELECT now() FROM system.local")
      rescue
        e -> {:rescued, Exception.format(:error, e, __STACKTRACE__)}
      catch
        kind, reason -> {:caught, kind, inspect(reason)}
      end

    json(conn, %{
      restart_result: inspect(result),
      query_result_after_restart: inspect(query_result)
    })
  end
end