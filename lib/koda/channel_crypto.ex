defmodule Koda.ChannelCrypto do
  @moduledoc """
  Server-side half of channel group encryption: a registry of per-channel
  key "epochs," and, per epoch, one encrypted copy of that epoch's shared
  symmetric key for each current member -- delivered over that member's
  existing pairwise DM Double Ratchet session (same envelope shape as a
  DM message, see Koda.Chat.DmMessage). The server never sees a
  channel's actual key material, only these per-recipient ciphertexts
  and the bookkeeping of who has received which epoch.

  Epoch 1 is bootstrapped by whoever creates a channel (or the first
  client that notices an existing channel has none yet). Later epochs
  are started by whichever client performs a membership-removing action
  (kick/ban/leave) -- that client already has the full remaining-member
  list right there, so it can generate the new key and distribute it
  without needing some other online member to coordinate through. New
  joins never rotate the epoch; the joining member is simply queued as a
  pending recipient of the *current* epoch, which is why a new member
  can read channel history back to whenever that epoch started but not
  further -- by design, not a gap.
  """
  import Ecto.Query
  alias Koda.Repo

  defmodule EpochKey do
    use Ecto.Schema
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id
    schema "channel_epoch_keys" do
      field :channel_id, :binary_id
      field :epoch,      :integer
      field :created_by, :binary_id
      field :inserted_at, :utc_datetime_usec
    end
  end

  defmodule Delivery do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id
    schema "channel_key_deliveries" do
      field :channel_id,   :binary_id
      field :epoch,        :integer
      field :sender_id,    :binary_id
      field :recipient_id, :binary_id
      field :content,      :string
      field :ratchet_key,  :string
      field :msg_number,   :integer
      field :prev_chain,   :integer
      field :nonce,        :string
      field :x3dh_header,  :map
      field :inserted_at,  :utc_datetime_usec
    end

    def changeset(d, attrs) do
      d
      |> cast(attrs, [:channel_id, :epoch, :sender_id, :recipient_id, :content, :ratchet_key,
                      :msg_number, :prev_chain, :nonce, :x3dh_header])
      |> validate_required([:channel_id, :epoch, :sender_id, :recipient_id, :content,
                             :ratchet_key, :msg_number, :prev_chain, :nonce])
      |> unique_constraint([:channel_id, :epoch, :recipient_id])
    end
  end

  @doc "The highest epoch established for a channel, or 0 if it's never been encrypted."
  def current_epoch(channel_id) do
    Repo.one(from k in EpochKey, where: k.channel_id == ^channel_id, select: max(k.epoch)) || 0
  end

  @doc """
  Starts a new epoch (1 if the channel has none yet, otherwise
  current+1). Two clients racing to bootstrap/rotate the same channel at
  once are resolved by the unique (channel_id, epoch) index -- the
  loser's insert fails here and should re-fetch current_epoch/1 and
  distribute to *that* instead of minting yet another one.
  """
  def start_new_epoch(channel_id, created_by_user_id) do
    epoch = current_epoch(channel_id) + 1

    %EpochKey{}
    |> Ecto.Changeset.change(%{channel_id: channel_id, epoch: epoch, created_by: created_by_user_id})
    |> Ecto.Changeset.validate_required([:channel_id, :epoch])
    |> Ecto.Changeset.unique_constraint([:channel_id, :epoch])
    |> Repo.insert()
    |> case do
      {:ok, _} -> {:ok, epoch}
      {:error, _} = err -> err
    end
  end

  @doc "Current channel members who don't yet have a delivery for this epoch."
  def pending_recipients(channel_id, epoch) do
    case Koda.Servers.get_channel(channel_id) do
      nil ->
        []

      channel ->
        delivered =
          Repo.all(
            from d in Delivery,
            where: d.channel_id == ^channel_id and d.epoch == ^epoch,
            select: d.recipient_id
          )
          |> MapSet.new()

        Koda.Servers.list_members(channel.server_id)
        |> Enum.map(& &1.user_id)
        |> Enum.uniq()
        |> Enum.filter(fn user_id ->
          Koda.Servers.member_can_view_channel?(channel, user_id) and
            not MapSet.member?(delivered, user_id)
        end)
    end
  end

  @doc """
  Records one recipient's encrypted copy of an epoch key. Idempotent --
  a duplicate delivery for the same (channel, epoch, recipient) is
  silently ignored rather than erroring, since two online members can
  race to fill the same gap in pending_recipients/2.
  """
  def record_delivery(attrs) do
    %Delivery{}
    |> Delivery.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:channel_id, :epoch, :recipient_id])
  end

  @doc """
  Every delivery ever addressed to this user in this channel, oldest
  epoch first. The client keeps whichever epochs it doesn't already
  have stored locally and ignores the rest -- cheap enough (one small
  row per epoch a member has actually needed) not to bother with a
  since-epoch cursor.
  """
  def my_deliveries(channel_id, user_id) do
    Repo.all(
      from d in Delivery,
      where: d.channel_id == ^channel_id and d.recipient_id == ^user_id,
      order_by: [asc: d.epoch]
    )
  end

  def delivery_json(d) do
    %{
      epoch:       d.epoch,
      sender_id:   d.sender_id,
      content:     d.content,
      ratchet_key: d.ratchet_key,
      msg_number:  d.msg_number,
      prev_chain:  d.prev_chain,
      nonce:       d.nonce,
      x3dh_header: d.x3dh_header
    }
  end
end
