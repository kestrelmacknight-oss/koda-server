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
      field :edited_at,   :utc_datetime_usec
      field :pinned_at,   :utc_datetime_usec
      field :attachment_url,          :string
      field :attachment_content_type, :string
      field :link_preview,            :map
      # Which shared channel-key epoch this was encrypted with (nil for
      # legacy/unencrypted history), and the AES-GCM nonce used -- see
      # Koda.ChannelCrypto for the epoch key distribution this relies on.
      field :epoch, :integer
      field :nonce,  :string
      # Mentions are computed client-side against the plaintext before
      # encryption and sent as explicit IDs instead of the server
      # regex-scanning content -- see process_mentions/4 below, which
      # only takes this path when encrypted is true.
      field :mentioned_user_ids, {:array, :binary_id}, default: []
      field :mentioned_role_ids, {:array, :binary_id}, default: []
      field :mention_everyone,   :boolean, default: false
    end

    def changeset(m, attrs) do
      m
      |> cast(attrs, [:id, :channel_id, :sender_id, :content, :encrypted, :reply_to_id,
                      :inserted_at, :attachment_url, :attachment_content_type, :link_preview,
                      :epoch, :nonce, :mentioned_user_ids, :mentioned_role_ids, :mention_everyone])
      |> validate_required([:channel_id, :sender_id])
      |> validate_content_or_attachment()
    end

    defp validate_content_or_attachment(changeset) do
      content    = get_field(changeset, :content)
      attachment = get_field(changeset, :attachment_url)
      if (content && content != "") || attachment do
        changeset
      else
        add_error(changeset, :content, "can't be blank without an attachment")
      end
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
      field :attachment_url,          :string
      field :attachment_content_type, :string
      # Double Ratchet message header -- nil for legacy/plaintext rows.
      field :ratchet_key, :string
      field :msg_number,  :integer
      field :prev_chain,  :integer
      field :nonce,       :string
      # X3DH handshake header, present only on a session-establishing message.
      field :x3dh_header, :map
    end

    def changeset(m, attrs) do
      m
      |> cast(attrs, [:id, :conversation_id, :sender_id, :content, :encrypted,
                      :inserted_at, :attachment_url, :attachment_content_type,
                      :ratchet_key, :msg_number, :prev_chain, :nonce, :x3dh_header])
      |> validate_required([:conversation_id, :sender_id, :content])
    end
  end

  # ── Channel messages ──────────────────────────────────────────────────────

  def send_message(channel_id, sender_id, content, opts \\ []) do
    server_id = Keyword.get(opts, :server_id)
    if server_id && Koda.Moderation.RateLimiter.check_send(server_id, channel_id, sender_id) == :rate_limited do
      {:error, :rate_limited}
    else
      do_send_message(channel_id, sender_id, content, opts)
    end
  end

  defp do_send_message(channel_id, sender_id, content, opts) do
    sender_username    = Keyword.get(opts, :sender_username, sender_id)
    encrypted          = Keyword.get(opts, :encrypted, false)
    reply_to_id        = Keyword.get(opts, :reply_to_id, nil)
    attachment_url     = Keyword.get(opts, :attachment_url, nil)
    attachment_type    = Keyword.get(opts, :attachment_content_type, nil)
    epoch              = Keyword.get(opts, :epoch, nil)
    nonce              = Keyword.get(opts, :nonce, nil)
    mentioned_user_ids = Keyword.get(opts, :mentioned_user_ids, [])
    mentioned_role_ids = Keyword.get(opts, :mentioned_role_ids, [])
    mention_everyone   = Keyword.get(opts, :mention_everyone, false)
    message_id         = Ecto.UUID.generate()
    now                = DateTime.utc_now() |> DateTime.truncate(:second)

    case %Message{}
         |> Message.changeset(%{
              id:          message_id,
              channel_id:  channel_id,
              sender_id:   sender_id,
              content:     content,
              encrypted:   encrypted,
              reply_to_id: reply_to_id,
              inserted_at: now,
              attachment_url:          attachment_url,
              attachment_content_type: attachment_type,
              epoch:              epoch,
              nonce:              nonce,
              mentioned_user_ids: mentioned_user_ids,
              mentioned_role_ids: mentioned_role_ids,
              mention_everyone:   mention_everyone
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
          inserted_at: DateTime.to_iso8601(now),
          attachment_url:          attachment_url,
          attachment_content_type: attachment_type,
          epoch: epoch,
          nonce: nonce
        }
        Phoenix.PubSub.broadcast(Koda.PubSub, "channel:#{channel_id}", {:new_message, msg})
        # Process mentions and sidebar unread badges asynchronously --
        # neither blocks the sender's own send from completing. An
        # encrypted message carries its mentions as explicit IDs (the
        # server can't regex plaintext it never sees); a legacy/plaintext
        # message still gets the old content-scan path.
        mention_meta = %{
          encrypted:          encrypted,
          mentioned_user_ids: mentioned_user_ids,
          mentioned_role_ids: mentioned_role_ids,
          mention_everyone:   mention_everyone
        }
        Task.start(fn -> process_mentions(channel_id, sender_id, content, msg, mention_meta) end)
        Task.start(fn -> broadcast_unread_bump(channel_id, sender_id) end)
        {:ok, msg}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_messages(channel_id, opts \\ []) do
    limit     = Keyword.get(opts, :limit, 50)
    before_id = Keyword.get(opts, :before_id)

    # Cursor pagination for scrolling/searching further back in history --
    # everything strictly older than the given message.
    before_ts =
      case before_id && Repo.get(Message, before_id) do
        %Message{inserted_at: ts} -> ts
        _ -> nil
      end

    messages =
      if before_ts do
        from(m in Message,
          where: m.channel_id == ^channel_id and m.inserted_at < ^before_ts,
          order_by: [desc: m.inserted_at],
          limit: ^limit
        )
        |> Repo.all()
      else
        from(m in Message,
          where: m.channel_id == ^channel_id,
          order_by: [desc: m.inserted_at],
          limit: ^limit
        )
        |> Repo.all()
      end

    enrich_with_authors(Enum.map(messages, fn m ->
      %{
        "id"          => m.id,
        "channel_id"  => m.channel_id,
        "sender_id"   => m.sender_id,
        "content"     => m.content,
        "encrypted"   => m.encrypted,
        "reply_to_id" => Map.get(m, :reply_to_id),
        "reply_to"    => get_reply_preview(Map.get(m, :reply_to_id)),
        "reactions"   => get_reactions(m.id),
        "inserted_at" => DateTime.to_iso8601(m.inserted_at),
        "edited_at"   => format_ts(m.edited_at),
        "pinned_at"   => format_ts(m.pinned_at),
        "attachment_url"          => Map.get(m, :attachment_url),
        "attachment_content_type" => Map.get(m, :attachment_content_type),
        "link_preview"            => Map.get(m, :link_preview),
        "epoch"                   => Map.get(m, :epoch),
        "nonce"                   => Map.get(m, :nonce)
      }
    end))
  end

  # Attaches OG preview data the sender's own client already fetched for a
  # URL in their message. The server never fetches link URLs itself --
  # message content can be end-to-end encrypted, so the server usually
  # can't even see the URL, and having it fetch arbitrary user-supplied
  # URLs would be an SSRF hole against Fly's internal network anyway.
  def set_link_preview(channel_id, message_id, sender_id, preview) do
    case Repo.get_by(Message, id: message_id, channel_id: channel_id, sender_id: sender_id) do
      nil -> {:error, :not_found}
      msg ->
        case msg |> Ecto.Changeset.change(link_preview: preview) |> Repo.update() do
          {:ok, _} ->
            payload = %{id: message_id, channel_id: channel_id, link_preview: preview}
            Phoenix.PubSub.broadcast(Koda.PubSub, "channel:#{channel_id}",
              {:link_preview_updated, payload})
            {:ok, payload}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # Only the original sender may edit their own message. An encrypted
  # message's edit must carry a fresh nonce -- the editor re-encrypts
  # under the *same* epoch the message was originally sent with (see
  # ChannelKeyManager.encryptForEpoch client-side), never the channel's
  # current epoch, since reusing a nonce with AES-GCM is unsafe and a
  # message's readability shouldn't change out from under an edit.
  def edit_message(channel_id, message_id, sender_id, content, opts \\ []) do
    nonce = Keyword.get(opts, :nonce)
    case Repo.get_by(Message, id: message_id, channel_id: channel_id, sender_id: sender_id) do
      nil -> {:error, :not_found}
      msg ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        changes = %{content: content, edited_at: now}
        changes = if nonce, do: Map.put(changes, :nonce, nonce), else: changes

        case msg |> Ecto.Changeset.change(changes) |> Repo.update() do
          {:ok, updated} ->
            payload = %{id: updated.id, channel_id: channel_id, content: content,
                        nonce: updated.nonce, edited_at: DateTime.to_iso8601(now)}
            Phoenix.PubSub.broadcast(Koda.PubSub, "channel:#{channel_id}",
              {:message_edited, payload})
            {:ok, payload}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def pin_message(channel_id, message_id), do: set_pinned(channel_id, message_id, DateTime.utc_now() |> DateTime.truncate(:second))
  def unpin_message(channel_id, message_id), do: set_pinned(channel_id, message_id, nil)

  defp set_pinned(channel_id, message_id, pinned_at) do
    case Repo.get_by(Message, id: message_id, channel_id: channel_id) do
      nil -> {:error, :not_found}
      msg ->
        case msg |> Ecto.Changeset.change(pinned_at: pinned_at) |> Repo.update() do
          {:ok, _} ->
            event = if pinned_at, do: :message_pinned, else: :message_unpinned
            Phoenix.PubSub.broadcast(Koda.PubSub, "channel:#{channel_id}",
              {event, %{id: message_id, channel_id: channel_id}})
            :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def list_pinned(channel_id) do
    messages =
      from(m in Message,
        where: m.channel_id == ^channel_id and not is_nil(m.pinned_at),
        order_by: [desc: m.pinned_at]
      )
      |> Repo.all()

    enrich_with_authors(Enum.map(messages, fn m ->
      %{
        "id"          => m.id,
        "channel_id"  => m.channel_id,
        "sender_id"   => m.sender_id,
        "content"     => m.content,
        "encrypted"   => m.encrypted,
        "inserted_at" => DateTime.to_iso8601(m.inserted_at),
        "edited_at"   => format_ts(m.edited_at),
        "pinned_at"   => format_ts(m.pinned_at)
      }
    end))
  end

  defp format_ts(nil), do: nil
  defp format_ts(dt), do: DateTime.to_iso8601(dt)

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
    ratchet_key     = Keyword.get(opts, :ratchet_key, nil)
    msg_number      = Keyword.get(opts, :msg_number, nil)
    prev_chain      = Keyword.get(opts, :prev_chain, nil)
    nonce           = Keyword.get(opts, :nonce, nil)
    x3dh_header     = Keyword.get(opts, :x3dh_header, nil)
    message_id      = Ecto.UUID.generate()
    now             = DateTime.utc_now() |> DateTime.truncate(:second)

    case %DmMessage{}
         |> DmMessage.changeset(%{
              id:              message_id,
              conversation_id: conversation_id,
              sender_id:       sender_id,
              content:         content,
              encrypted:       encrypted,
              inserted_at:     now,
              ratchet_key:     ratchet_key,
              msg_number:      msg_number,
              prev_chain:      prev_chain,
              nonce:           nonce,
              x3dh_header:     x3dh_header
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
          inserted_at:     DateTime.to_iso8601(now),
          ratchet_key:     ratchet_key,
          msg_number:      msg_number,
          prev_chain:      prev_chain,
          nonce:           nonce,
          x3dh_header:     x3dh_header
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
        "inserted_at"     => DateTime.to_iso8601(m.inserted_at),
        "ratchet_key"     => Map.get(m, :ratchet_key),
        "msg_number"      => Map.get(m, :msg_number),
        "prev_chain"      => Map.get(m, :prev_chain),
        "nonce"           => Map.get(m, :nonce),
        "x3dh_header"     => Map.get(m, :x3dh_header)
      }
    end))
  end

  # ── Reactions ─────────────────────────────────────────────────────────────

  defp to_uuid_binary(uuid) do
    case Ecto.UUID.dump(uuid) do
      {:ok, bin} -> bin
      _ -> uuid
    end
  end

  def add_reaction(message_id, emoji, user_id) do
    Repo.query(
      "INSERT INTO message_reactions (id, message_id, emoji, user_id) VALUES (gen_random_uuid(), $1, $2, $3) ON CONFLICT DO NOTHING",
      [to_uuid_binary(message_id), emoji, to_uuid_binary(user_id)]
    )
  end

  def remove_reaction(message_id, emoji, user_id) do
    Repo.query(
      "DELETE FROM message_reactions WHERE message_id = $1 AND emoji = $2 AND user_id = $3",
      [to_uuid_binary(message_id), emoji, to_uuid_binary(user_id)]
    )
  end

  def get_reactions(message_id) do
    binary_id = case Ecto.UUID.dump(message_id) do
      {:ok, bin} -> bin
      _ -> message_id
    end
    {:ok, result} = Repo.query(
      "SELECT emoji, user_id::text FROM message_reactions WHERE message_id = $1",
      [binary_id]
    )
    result.rows
    |> Enum.group_by(fn [emoji, _] -> emoji end, fn [_, user_id] -> user_id end)
    |> Enum.map(fn {emoji, user_ids} -> %{emoji: emoji, count: length(user_ids), user_ids: user_ids} end)
  end

  def get_reactions_for_messages(message_ids) do
    ids = Enum.join(Enum.map(message_ids, &"'#{&1}'"), ",")
    {:ok, result} = Repo.query(
      "SELECT message_id::text, emoji, user_id::text FROM message_reactions WHERE message_id = ANY($1::uuid[])",
      [message_ids]
    )
    result.rows
    |> Enum.group_by(fn [msg_id, _, _] -> msg_id end)
    |> Enum.map(fn {msg_id, rows} ->
      reactions = rows
        |> Enum.group_by(fn [_, emoji, _] -> emoji end, fn [_, _, uid] -> uid end)
        |> Enum.map(fn {emoji, uids} -> %{emoji: emoji, count: length(uids), user_ids: uids} end)
      {msg_id, reactions}
    end)
    |> Map.new()
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

  # Pushes a lightweight "this channel has a new message" signal to
  # every other server member's per-user socket topic, so the sidebar
  # can bump an unread badge for a channel the member isn't currently
  # viewing (and therefore isn't subscribed to "channel:<id>" for) --
  # see RoomChannel.handle_info({:unread_bump, _}, _). Doesn't filter by
  # per-channel role visibility: a member who can't see this channel
  # just receives a bump for a channel_id their client never rendered
  # in the first place, which is harmless (matches how @everyone below
  # already broadcasts to the full member list rather than computing
  # per-channel visibility).
  defp broadcast_unread_bump(channel_id, sender_id) do
    import Ecto.Query
    case Repo.get(Koda.Servers.Channel, channel_id) do
      nil -> :ok
      channel ->
        member_ids = Repo.all(
          from m in Koda.Servers.Member,
          where: m.server_id == ^channel.server_id and m.user_id != ^sender_id,
          select: m.user_id
        )
        Enum.each(member_ids, fn user_id ->
          Phoenix.PubSub.broadcast(Koda.PubSub, "user:#{user_id}",
            {:unread_bump, %{channel_id: channel_id, server_id: channel.server_id}})
        end)
    end
  end

  # ── Mention processing ────────────────────────────────────────────────────

  defp process_mentions(channel_id, sender_id, content, msg, mention_meta) do
    channel = Koda.Repo.get(Koda.Servers.Channel, channel_id)
    if is_nil(channel), do: :ok, else: do_process_mentions(channel, sender_id, content, msg, mention_meta)
  end

  # Encrypted messages carry their mentions as explicit IDs computed
  # client-side against the plaintext before encryption -- the server
  # never sees enough to regex-scan content for them. Every ID is still
  # re-validated against real server membership/roles here rather than
  # trusted outright, and @everyone still goes through the same
  # mention_everyone permission gate as the legacy path below.
  defp do_process_mentions(channel, sender_id, _content, msg,
         %{encrypted: true} = mention_meta) do
    import Ecto.Query
    server_id    = channel.server_id
    channel_name = channel.name
    sender       = Koda.Repo.get(Koda.Auth.User, sender_id)
    sender_name  = if sender, do: sender.username, else: "Someone"
    title        = "Mentioned in ##{channel_name}"
    notif_data   = %{channel_id: channel.id, server_id: server_id,
                      message_id: msg.id, sender: sender_name}

    if mention_meta.mention_everyone and
         Koda.Servers.member_can?(server_id, sender_id, "mention_everyone") do
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
    end

    role_ids = mention_meta.mentioned_role_ids || []
    if role_ids != [] do
      members = Koda.Repo.all(
        from mr in Koda.Servers.MemberRole,
        join: m in Koda.Servers.Member,
          on: m.id == mr.member_id and m.server_id == ^server_id,
        join: r in Koda.Servers.Role,
          on: r.id == mr.role_id and r.server_id == ^server_id,
        where: mr.role_id in ^role_ids and m.user_id != ^sender_id,
        select: {m.user_id, r.name}
      )
      Enum.each(members, fn {user_id, role_name} ->
        {:ok, notif} = Koda.Notifications.create(user_id, "role_mention",
          title, "@#{role_name} in ##{channel_name}", notif_data)
        push_notification(user_id, notif)
      end)
    end

    user_ids = mention_meta.mentioned_user_ids || []
    if user_ids != [] do
      valid_member_ids =
        Koda.Repo.all(
          from m in Koda.Servers.Member,
          where: m.server_id == ^server_id and m.user_id in ^user_ids and m.user_id != ^sender_id,
          select: m.user_id
        )
      Enum.each(valid_member_ids, fn user_id ->
        {:ok, notif} = Koda.Notifications.create(user_id, "mention",
          title, "Mentioned in ##{channel_name}", notif_data)
        push_notification(user_id, notif)
      end)
    end
  end

  # Legacy path for unencrypted messages -- the server still has the
  # plaintext content, so it can keep resolving @word tokens itself.
  defp do_process_mentions(channel, sender_id, content, msg, _mention_meta) do
    import Ecto.Query
    server_id   = channel.server_id
    channel_name = channel.name
    sender      = Koda.Repo.get(Koda.Auth.User, sender_id)
    sender_name = if sender, do: sender.username, else: "Someone"
    title       = "Mentioned in ##{channel_name}"
    notif_data  = %{channel_id: channel.id, server_id: server_id,
                    message_id: msg.id, sender: sender_name}

    cond do
      # @everyone -- notify all server members except sender. Gated on
      # the mention_everyone permission (same flag member_can?/3 already
      # checks elsewhere) -- without this, anyone could type the literal
      # text "@everyone" and trigger a full-server notification blast
      # regardless of their role. A sender who lacks the permission just
      # falls through to individual/role @mention scanning below, same
      # as if they'd typed any other plain text.
      String.contains?(content, "@everyone") and
          Koda.Servers.member_can?(server_id, sender_id, "mention_everyone") ->
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
