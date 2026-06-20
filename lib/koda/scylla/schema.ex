defmodule Koda.Scylla.Schema do
  @moduledoc """
  Applies the ScyllaDB keyspace and table schema on startup.

  Xandra.Cluster.start_link/1 returns immediately and connects to
  ScyllaDB in the background -- it does not block until connected.
  If this runs before that connection finishes (a real race on boot,
  especially right after ScyllaDB itself was also just restarted),
  every statement fails with {:cluster, :not_connected}. This retries
  with a short backoff instead of giving up after one attempt, and
  only reports success when statements actually succeeded.
  """
  require Logger

  @max_attempts 5
  @retry_delay_ms 2_000

  def setup!, do: attempt(1)

  defp attempt(attempt_number) do
    Logger.info("[Scylla] Applying schema (attempt #{attempt_number}/#{@max_attempts})...")

    statements =
      Application.app_dir(:koda, "priv/cql/schema.cql")
      |> File.read!()
      |> String.split(";")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    results = Enum.map(statements, fn stmt -> {stmt, Koda.Scylla.execute(stmt)} end)
    failures = Enum.filter(results, fn {_, result} -> match?({:error, _}, result) end)

    cond do
      failures == [] ->
        Logger.info("[Scylla] Schema applied successfully -- #{length(statements)} statements.")

      not_connected?(failures) and attempt_number < @max_attempts ->
        Logger.warning(
          "[Scylla] Cluster not yet connected (attempt #{attempt_number}/#{@max_attempts}). " <>
          "Retrying in #{@retry_delay_ms}ms..."
        )
        Process.sleep(@retry_delay_ms)
        attempt(attempt_number + 1)

      true ->
        Logger.error(
          "[Scylla] Schema setup incomplete after #{attempt_number} attempt(s) -- " <>
          "#{length(failures)}/#{length(statements)} statements failed. " <>
          "The app will continue booting; ScyllaDB-backed features (chat) may not " <>
          "work until this is resolved."
        )
        Enum.each(failures, fn {stmt, {:error, reason}} ->
          Logger.error("[Scylla]   Failed: #{inspect(reason)} -- #{String.slice(stmt, 0, 60)}...")
        end)
    end
  end

  defp not_connected?(failures) do
    Enum.any?(failures, fn
      {_, {:error, %Xandra.ConnectionError{reason: {:cluster, :not_connected}}}} -> true
      _ -> false
    end)
  end
end