defmodule Koda.Scylla.Schema do
  @moduledoc "Applies the ScyllaDB keyspace and table schema on startup."
  require Logger

  def setup! do
    Logger.info("[Scylla] Applying schema...")
    cql_file = Application.app_dir(:koda, "priv/cql/schema.cql")

    cql_file
    |> File.read!()
    |> String.split(";")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.each(fn stmt ->
      case Koda.Scylla.execute(stmt) do
        {:ok, _}    -> :ok
        {:error, e} ->
          Logger.warning("[Scylla] Schema statement warning: #{inspect(e)}")
      end
    end)

    Logger.info("[Scylla] Schema ready.")
  end
end
