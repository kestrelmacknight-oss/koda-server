defmodule Koda.Chat do
  @moduledoc "Message storage via ScyllaDB."
  require Logger

  @page_size 50

  # CQL's uuid/timeuuid types need the 16-byte binary wire format, not
  # the human-readable dashed string ("8ecdd2b9-...") that arrives from
  # URL params, JSON bodies, or UUID.uuid1()/uuid4() calls. Without this
  # conversion, Xandra raises FunctionClauseError trying to encode the
  # string directly. Ecto.UUID.dump!/1 does exactly this conversion --
  # it's already a dependency for the Postgres side of the app, so no
  # new dependency needed.
  defp to_uuid_binary(uuid_string) when is_binary(uuid_string) do
    Ecto.UUID.dump!(uuid_string)
  end

  # -- Channel messages --------------------------------------------------------

  def send_message(channel_id, sender_id, content, opts \\ []) do
    bucket          = Koda.Scylla.month_bucket()
    message_id      = UUID.uuid1()
    encrypted       = Keyword.get(opts, :encrypted, true)
    sender_username = Keyword.get(opts, :sender_username)
    now             = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

    cql = """
    INSERT INTO koda.messages
      (channel_id, bucket, id, sender_id, content, encrypted, inserted_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    """

    case Koda.Scylla.execute(cql, [
      to_uuid_binary(channel_id),
      bucket,
      to_uuid_binary(message_id),
      to_uuid_binary(sender_id),
      content,
      encrypted,
      now
    ]) do
      {:ok, _} ->
        msg = %{
          id:          message_id,
          channel_id:  channel_id,
          sender_id:   sender_id,
          author:      %{id: sender_id, username: sender_username},
          content:     content,
          encrypted:   encrypted,
          inserted_at: DateTime.utc_now() |> DateTime.to_iso8601()
        }
        Phoenix.PubSub.broadcast(Koda.PubSub, "channel:#{channel_id}", {:new_message, msg})
        {:ok, msg}

      {:error, reason} ->
        Logger.error("[Chat] Failed to insert message: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def get_messages(channel_id, opts \\ []) do
    bucket = Keyword.get(opts, :bucket, Koda.Scylla.month_bucket())
    limit  = Keyword.get(opts, :limit, @page_size)

    cql = "SELECT * FROM koda.messages WHERE channel_id = ? AND bucket = ? ORDER BY id DESC LIMIT ?"

    case Koda.Scylla.execute(cql, [to_uuid_binary(channel_id), bucket, limit]) do
      {:ok, page}     -> {:ok, enrich_with_authors(Enum.to_list(page))}
      {:error, reason}-> {:error, reason}
    end
  end

  # -- DM messages ------------------------------------------------------------

  def send_dm_message(conversation_id, sender_id, content, opts \\ []) do
    bucket          = Koda.Scylla.month_bucket()
    message_id      = UUID.uuid1()
    encrypted       = Keyword.get(opts, :encrypted, true)
    sender_username = Keyword.get(opts, :sender_username)
    now             = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

    cql = """
    INSERT INTO koda.dm_messages
      (conversation_id, bucket, id, sender_id, content, encrypted, inserted_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    """

    case Koda.Scylla.execute(cql, [
      to_uuid_binary(conversation_id),
      bucket,
      to_uuid_binary(message_id),
      to_uuid_binary(sender_id),
      content,
      encrypted,
      now
    ]) do
      {:ok, _} ->
        msg = %{
          id:              message_id,
          conversation_id: conversation_id,
          sender_id:       sender_id,
          author:          %{id: sender_id, username: sender_username},
          content:         content,
          encrypted:       encrypted,
          inserted_at:     DateTime.utc_now() |> DateTime.to_iso8601()
        }
        Phoenix.PubSub.broadcast(Koda.PubSub, "dm:#{conversation_id}", {:new_message, msg})
        {:ok, msg}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_dm_messages(conversation_id, opts \\ []) do
    bucket = Keyword.get(opts, :bucket, Koda.Scylla.month_bucket())
    limit  = Keyword.get(opts, :limit, @page_size)

    cql = "SELECT * FROM koda.dm_messages WHERE conversation_id = ? AND bucket = ? ORDER BY id DESC LIMIT ?"

    case Koda.Scylla.execute(cql, [to_uuid_binary(conversation_id), bucket, limit]) do
      {:ok, page}      -> {:ok, enrich_with_authors(Enum.to_list(page))}
      {:error, reason} -> {:error, reason}
    end
  end

  # -- Reactions --------------------------------------------------------------

  def add_reaction(message_id, emoji, user_id) do
    cql = "INSERT INTO koda.message_reactions (message_id, emoji, user_id) VALUES (?, ?, ?)"
    Koda.Scylla.execute(cql, [to_uuid_binary(message_id), emoji, to_uuid_binary(user_id)])
  end

  def remove_reaction(message_id, emoji, user_id) do
    cql = "DELETE FROM koda.message_reactions WHERE message_id = ? AND emoji = ? AND user_id = ?"
    Koda.Scylla.execute(cql, [to_uuid_binary(message_id), emoji, to_uuid_binary(user_id)])
  end

  # -- Author enrichment --------------------------------------------------------
  #
  # Scylla only stores sender_id -- it has no username. History fetches
  # need one batched Postgres lookup across every distinct sender_id in
  # the page, rather than a query per message.

  defp enrich_with_authors(msgs) do
    sender_ids =
      msgs
      |> Enum.map(& &1["sender_id"])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    usernames = fetch_usernames(sender_ids)

    Enum.map(msgs, fn msg ->
      sender_id = msg["sender_id"]
      info = Map.get(usernames, sender_id) || %{}
      Map.put(msg, "author", %{"id" => sender_id, "username" => info[:username], "avatar_url" => info[:avatar_url]})
    end)
  end

  defp fetch_usernames([]), do: %{}
  defp fetch_usernames(sender_ids) do
    binary_ids = Enum.map(sender_ids, &to_uuid_binary/1)

    case Koda.Repo.query("SELECT id, username, avatar_url FROM users WHERE id = ANY($1::uuid[])", [binary_ids]) do
      {:ok, %{rows: rows}} ->
        Map.new(rows, fn [id, username, avatar_url] -> {Ecto.UUID.load!(id), %{username: username, avatar_url: avatar_url}} end)

      {:error, reason} ->
        Logger.error("[Chat] Failed to fetch usernames: #{inspect(reason)}")
        %{}
    end
  end
end