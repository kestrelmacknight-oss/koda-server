defmodule Koda.DirectMessages do
  import Ecto.Query
  alias Koda.Repo

  defmodule Conversation do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "dm_conversations" do
      belongs_to :initiator, Koda.Auth.User, foreign_key: :initiator_id
      belongs_to :recipient, Koda.Auth.User, foreign_key: :recipient_id
      timestamps(type: :utc_datetime)
    end

    def changeset(c, attrs) do
      c |> cast(attrs, [:initiator_id, :recipient_id])
        |> validate_required([:initiator_id, :recipient_id])
        |> unique_constraint([:initiator_id, :recipient_id])
    end
  end

  def open_conversation(user_id, other_id) do
    case Repo.one(
      from c in Conversation,
      where: (c.initiator_id == ^user_id and c.recipient_id == ^other_id)
          or (c.initiator_id == ^other_id and c.recipient_id == ^user_id)
    ) do
      nil ->
        %Conversation{}
        |> Conversation.changeset(%{initiator_id: user_id, recipient_id: other_id})
        |> Repo.insert()
      existing ->
        {:ok, existing}
    end
  end

  def list_conversations(user_id) do
    Repo.all(
      from c in Conversation,
      where: c.initiator_id == ^user_id or c.recipient_id == ^user_id,
      preload: [:initiator, :recipient],
      order_by: [desc: c.updated_at]
    )
  end

  def get_conversation(id, user_id) do
    Repo.one(
      from c in Conversation,
      where: c.id == ^id
         and (c.initiator_id == ^user_id or c.recipient_id == ^user_id)
    )
  end

  def participant?(conversation, user_id) do
    conversation.initiator_id == user_id or conversation.recipient_id == user_id
  end

  # Messages for DMs are stored in ScyllaDB (dm_messages table)
  # See Koda.Chat for the ScyllaDB-backed message functions
  def get_messages(conversation_id, opts \\ []) do
    Koda.Chat.get_dm_messages(conversation_id, opts)
  end

  # opts forwarded to Chat.send_dm_message -- primarily used to pass
  # sender_username: so the author field is populated correctly, matching
  # the same pattern as channel messages via ChannelController.
  def send_message(conversation_id, sender_id, content, opts \\ []) do
    Koda.Chat.send_dm_message(conversation_id, sender_id, content, opts)
  end
end