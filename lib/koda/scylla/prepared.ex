defmodule Koda.Scylla.Prepared do
  @moduledoc "Caches prepared ScyllaDB statements at startup."
  use GenServer
  require Logger

  @statements %{
    insert_message:    "INSERT INTO koda.messages (channel_id, bucket, id, sender_id, content, encrypted, inserted_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
    get_messages:      "SELECT * FROM koda.messages WHERE channel_id = ? AND bucket = ? ORDER BY id DESC LIMIT ?",
    insert_dm_message: "INSERT INTO koda.dm_messages (conversation_id, bucket, id, sender_id, content, encrypted, inserted_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
    get_dm_messages:   "SELECT * FROM koda.dm_messages WHERE conversation_id = ? AND bucket = ? ORDER BY id DESC LIMIT ?",
    add_reaction:      "INSERT INTO koda.message_reactions (message_id, emoji, user_id) VALUES (?, ?, ?)",
    remove_reaction:   "DELETE FROM koda.message_reactions WHERE message_id = ? AND emoji = ? AND user_id = ?",
    get_reactions:     "SELECT * FROM koda.message_reactions WHERE message_id = ?",
    set_last_read:     "INSERT INTO koda.last_read (user_id, channel_id, message_id) VALUES (?, ?, ?)",
    get_last_read:     "SELECT message_id FROM koda.last_read WHERE user_id = ? AND channel_id = ?",
  }

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    {:ok, %{}, {:continue, :prepare}}
  end

  @impl true
  def handle_continue(:prepare, _) do
    statements = Map.new(@statements, fn {key, cql} ->
      case Koda.Scylla.execute("USE koda") do
        _ ->
          prepared = Koda.Scylla.prepare!(cql)
          Logger.debug("[Scylla] Prepared: #{key}")
          {key, prepared}
      end
    end)

    {:noreply, statements}
  rescue
    e ->
      Logger.warning("[Scylla] Could not prepare statements: #{inspect(e)}. Will retry on use.")
      {:noreply, %{}}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    {:reply, Map.get(state), state}
  end

  def get(key), do: GenServer.call(__MODULE__, {:get, key})
end
