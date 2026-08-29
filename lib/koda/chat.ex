defmodule Koda.Chat do
  @moduledoc """
  Chat message storage using PostgreSQL via Ecto.
  Replaces the previous ScyllaDB implementation.
  """
  import Ecto.Query
  alias Koda.Repo

  # ── Schemas ──────────────────────────────────────────────────────────────

  defmodule Message do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "messages" do
      field :channel_id,  :binary_id
      field :sender_id,   :binary_id
      field :content,     :string
      field :encrypted,   :boolean, default: false
      field :reply_to_id, :binary_id
      field :inserted_at, :utc_datetime_usec
    end

    def changeset(m, attrs) do
      m
      |> cast(attrs, [:id, :channel_id, :sender_id, :content, :encrypted, :reply_to_id, :inserted_at])
      |> validate_required([:channel_id, :sender_id, :content])
    end
  end

  defmodule DmMessage do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "dm_messages" do
      field :conversation_id, :string
      field :sender_id,       :binary_id
      field :content,         :string
      field :encrypted,       :boolean, default: false
      field :inserted_at,     :utc_datetime_usec
    end

    def changeset(m, attrs) do
      m
      |> cast(attrs, [:id, :conversation_id, :sender_id, :content, :encrypted, :inserted_at])
      |> validate_required([:conversation_id, :sender_id, :content])
    end
  end

  # ── Channel messages ──────────────────────────────────────────────────────

  def send_message(channel_id, sender_id, content, opts \\ []) do
    sender_username = Keyword.get(opts, :sender_username, sender_id)
    encrypted       = Keyword.get(opts, :encrypted, false)
    reply_to_id     = Keyword.get(opts, :reply_to_id, nil)
    message_id      = Ecto.UUID.generate()
    now             = DateTime.utc_now() |> DateTime.truncate(:second)

    case %Message{}
         |> Message.changeset(%{
              id:          message_id,
              channel_id:  channel_id,
              sender_id:   sender_id,
              content:     content,
              encrypted:   encrypted,
              reply_to_id: reply_to_id,
              inserted_at: now
            })
         |> Repo.insert() do
      {:ok, _} ->
        avatar_url = case Repo.get(Koda.Auth.User, sender_id) do
          %{avatar_url: url} -> url
          _ -> nil
        end
        msg = %{
          id:          message_id,
          channel_id:  channel_id,
          sender_id:   sender_id,
          author:      %{id: sender_id, username: sender_username, avatar_url: avatar_url},
          content:     content,
          encrypted:   encrypted,
          reply_to_id: reply_to_id,
          reply_to:    get_reply_preview(reply_to_id),
          inserted_at: DateTime.to_iso8601(now)
        }
        Phoenix.PubSub.broadcast(Koda.PubSub, "channel:#{channel_id}", {:new_message, msg})
        # Process mentions asynchronously
        Task.start(fn -> process_mentions(channel_id, sender_id, content, msg) end)
        {:ok, msg}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_messages(channel_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    messages =
      from(m in Message,
        where: m.channel_id == ^channel_id,
        order_by: [desc: m.inserted_at],
        limit: ^limit
      )
      |> Repo.all()

    enrich_with_authors(Enum.map(messages, fn m ->
      %{
        "id"          => m.id,
        "channel_id"  => m.channel_id,
        "sender_id"   => m.sender_id,
        "content"     => m.content,
        "encrypted"   => m.encrypted,
        "reply_to_id" => Map.get(m, :reply_to_id),
        "reply_to"    => get_reply_preview(Map.get(m, :reply_to_id)),
        "inserted_at" => DateTime.to_iso8601(m.inserted_at)
      }
    end))
  end

  def delete_message(channel_id, message_id) do
    case Repo.get_by(Message, id: message_id, channel_id: channel_id) do
      nil -> {:error, :not_found}
      msg ->
        case Repo.delete(msg) do
          {:ok, _}    -> :ok
          {:error, e} -> {:error, e}
        end
    end
  end

  # ── DM messages ───────────────────────────────────────────────────────────

  def send_dm_message(conversation_id, sender_id, content, opts \\ []) do
    sender_username = Keyword.get(opts, :sender_username, sender_id)
    encrypted       = Keyword.get(opts, :encrypted, false)
    message_id      = Ecto.UUID.generate()
    now             = DateTime.utc_now() |> DateTime.truncate(:second)

    case %DmMessage{}
         |> DmMessage.changeset(%{
              id:              message_id,
              conversation_id: conversation_id,
              sender_id:       sender_id,
              content:         content,
              encrypted:       encrypted,
              inserted_at:     now
            })
         |> Repo.insert() do
      {:ok, _} ->
        msg = %{
          id:              message_id,
          conversation_id: conversation_id,
          sender_id:       sender_id,
          author:          %{id: sender_id, username: sender_username},
          content:         content,
          encrypted:       encrypted,
          inserted_at:     DateTime.to_iso8601(now)
        }
        Phoenix.PubSub.broadcast(Koda.PubSub, "dm:#{conversation_id}", {:new_message, msg})
        {:ok, msg}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_dm_messages(conversation_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    messages =
      from(m in DmMessage,
        where: m.conversation_id == ^conversation_id,
        order_by: [desc: m.inserted_at],
        limit: ^limit
      )
      |> Repo.all()

    enrich_with_authors(Enum.map(messages, fn m ->
      %{
        "id"              => m.id,
        "conversation_id" => m.conversation_id,
        "sender_id"       => m.sender_id,
        "content"         => m.content,
        "encrypted"       => m.encrypted,
        "inserted_at"     => DateTime.to_iso8601(m.inserted_at)
      }
    end))
  end

  # ── Reactions ─────────────────────────────────────────────────────────────

  def add_reaction(message_id, emoji, user_id) do
    Repo.query(
      "INSERT INTO message_reactions (id, message_id, emoji, user_id) VALUES (gen_random_uuid(), $1::uuid, $2, $3::uuid) ON CONFLICT DO NOTHING",
      [message_id, emoji, user_id]
    )
  end

  def remove_reaction(message_id, emoji, user_id) do
    Repo.query(
      "DELETE FROM message_reactions WHERE message_id = $1::uuid AND emoji = $2 AND user_id = $3::uuid",
      [message_id, emoji, user_id]
    )
  end

  # ── Author enrichment ─────────────────────────────────────────────────────

  defp enrich_with_authors(msgs) do
    sender_ids =
      msgs
      |> Enum.map(& &1["sender_id"])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    users =
      from(u in Koda.Auth.User,
        where: u.id in ^sender_ids,
        select: {u.id, u.username, u.avatar_url}
      )
      |> Repo.all()
      |> Map.new(fn {id, username, avatar_url} ->
           {Ecto.UUID.cast!(id), %{username: username, avatar_url: avatar_url}}
         end)

    Enum.map(msgs, fn msg ->
      sender_id = msg["sender_id"]
      info = Map.get(users, sender_id, %{username: sender_id, avatar_url: nil})
      Map.put(msg, "author", %{
        "id"         => sender_id,
        "username"   => info.username,
        "avatar_url" => info.avatar_url
      })
    end)
  end
  defp get_reply_preview(nil), do: nil
  defp get_reply_preview(reply_to_id) do
    case Repo.get(Message, reply_to_id) do
      nil -> nil
      msg ->
        author = case Repo.get(Koda.Auth.User, msg.sender_id) do
          nil -> %{username: "Unknown"}
          u   -> %{username: u.username}
        end
        content = if msg.encrypted, do: "[encrypted message]", else: msg.content
        %{id: msg.id, content: content, author: author, encrypted: msg.encrypted}
    end
  end

  # ── Mention processing ────────────────────────────────────────────────────

  defp process_mentions(channel_id, sender_id, content, msg) do
    channel = Koda.Repo.get(Koda.Servers.Channel, channel_id)
    if is_nil(channel), do: :ok, else: do_process_mentions(channel, sender_id, content, msg)
  end

  defp do_process_mentions(channel, sender_id, content, msg) do
    import Ecto.Query
    server_id   = channel.server_id
    channel_name = channel.name
    sender      = Koda.Repo.get(Koda.Auth.User, sender_id)
    sender_name = if sender, do: sender.username, else: "Someone"
    title       = "Mentioned in ##{channel_name}"
    notif_data  = %{channel_id: channel.id, server_id: server_id,
                    message_id: msg.id, sender: sender_name}

    cond do
      # @everyone -- notify all server members except sender
      String.contains?(content, "@everyone") ->
        members = Koda.Repo.all(
          from m in Koda.Servers.Member,
          where: m.server_id == ^server_id and m.user_id != ^sender_id,
          select: m.user_id
        )
        Enum.each(members, fn user_id ->
          {:ok, notif} = Koda.Notifications.create(user_id, "mention", title,
            "@everyone in ##{channel_name}", notif_data)
          push_notification(user_id, notif)
        end)

      # @roleName or @username mentions
      true ->
        # Extract all @mentions from content
        mentions = Regex.scan(~r/@([A-Za-z0-9_]+)/, content, capture: :all_but_first)
          |> List.flatten()
          |> Enum.uniq()

        Enum.each(mentions, fn mention ->
          # Check if it matches a role
          role = Koda.Repo.one(
            from r in Koda.Servers.Role,
            where: r.server_id == ^server_id and
                   fragment("lower(?)", r.name) == ^String.downcase(mention)
          )

          if role do
            # Notify all members with this role
            members = Koda.Repo.all(
              from mr in Koda.Servers.MemberRole,
              join: m in Koda.Servers.Member,
                on: m.id == mr.member_id and m.server_id == ^server_id,
              where: mr.role_id == ^role.id and m.user_id != ^sender_id,
              select: m.user_id
            )
            Enum.each(members, fn user_id ->
              {:ok, notif} = Koda.Notifications.create(user_id, "role_mention",
                title, "@#{mention} in ##{channel_name}", notif_data)
              push_notification(user_id, notif)
            end)
          else
            # Check if it matches a username
            user = Koda.Repo.one(
              from u in Koda.Auth.User,
              where: fragment("lower(?)", u.username) == ^String.downcase(mention)
            )
            if user && user.id != sender_id do
              {:ok, notif} = Koda.Notifications.create(user.id, "mention",
                title, "@#{mention} in ##{channel_name}", notif_data)
              push_notification(user.id, notif)
            end
          end
        end)
    end
  end

  defp push_notification(user_id, notif) do
    Phoenix.PubSub.broadcast(
      Koda.PubSub,
      "user:#{user_id}",
      {:notification, %{
        id:         notif.id,
        type:       notif.type,
        title:      notif.title,
        body:       notif.body,
        data:       notif.data,
        inserted_at: DateTime.to_iso8601(notif.inserted_at)
      }}
    )
  end
end
