defmodule Koda.ReadStates do
  @moduledoc """
  Per-user "last read" watermark for channels and DM conversations. Drives
  unread badges (count messages newer than the watermark, sent by
  someone else) and DM "Seen" receipts (compare the other participant's
  watermark against the last message).
  """
  import Ecto.Query
  alias Koda.Repo
  alias Koda.Chat.{Message, DmMessage}

  @epoch ~U[1970-01-01 00:00:00.000000Z]

  defmodule ReadState do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "read_states" do
      field :user_id,      :binary_id
      field :scope,        :string
      field :scope_id,     :string
      field :last_read_at, :utc_datetime_usec
    end

    def changeset(r, attrs) do
      r
      |> cast(attrs, [:user_id, :scope, :scope_id, :last_read_at])
      |> validate_required([:user_id, :scope, :scope_id, :last_read_at])
      |> unique_constraint([:user_id, :scope, :scope_id])
    end
  end

  def mark_read(user_id, scope, scope_id) when scope in ["channel", "dm"] do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %ReadState{}
    |> ReadState.changeset(%{user_id: user_id, scope: scope, scope_id: scope_id, last_read_at: now})
    |> Repo.insert(
      on_conflict: [set: [last_read_at: now]],
      conflict_target: [:user_id, :scope, :scope_id]
    )
    |> case do
      {:ok, _}         -> {:ok, now}
      {:error, reason} -> {:error, reason}
    end
  end

  def last_read_at(user_id, scope, scope_id) do
    Repo.one(
      from r in ReadState,
      where: r.user_id == ^user_id and r.scope == ^scope and r.scope_id == ^scope_id,
      select: r.last_read_at
    )
  end

  def unread_counts_for_channels(user_id, channel_ids) do
    Map.new(channel_ids, fn channel_id ->
      since = last_read_at(user_id, "channel", channel_id) || @epoch
      count = Repo.one(
        from m in Message,
        where: m.channel_id == ^channel_id and m.sender_id != ^user_id and m.inserted_at > ^since,
        select: count(m.id)
      )
      {channel_id, count}
    end)
  end

  def unread_counts_for_conversations(user_id, conversation_ids) do
    Map.new(conversation_ids, fn conversation_id ->
      since = last_read_at(user_id, "dm", conversation_id) || @epoch
      count = Repo.one(
        from m in DmMessage,
        where: m.conversation_id == ^conversation_id and m.sender_id != ^user_id and m.inserted_at > ^since,
        select: count(m.id)
      )
      {conversation_id, count}
    end)
  end
end
