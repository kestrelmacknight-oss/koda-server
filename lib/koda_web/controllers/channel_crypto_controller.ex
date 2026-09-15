defmodule KodaWeb.ChannelCryptoController do
  use KodaWeb, :controller
  alias Koda.{ChannelCrypto, Servers}

  defp channel_or_404(conn, channel_id, then) do
    case Servers.get_channel(channel_id) do
      nil -> conn |> put_status(404) |> json(%{error: "Channel not found"})
      channel -> then.(channel)
    end
  end

  defp require_view!(conn, channel, user_id, then) do
    if Servers.member_can_view_channel?(channel, user_id) do
      then.()
    else
      conn |> put_status(403) |> json(%{error: "Not authorized"})
    end
  end

  @doc "The channel's current epoch. 0 means it's never been encrypted -- the caller should bootstrap one."
  def show(conn, %{"channel_id" => channel_id}) do
    user = Guardian.Plug.current_resource(conn)
    channel_or_404(conn, channel_id, fn channel ->
      require_view!(conn, channel, user.id, fn ->
        json(conn, %{epoch: ChannelCrypto.current_epoch(channel_id)})
      end)
    end)
  end

  @doc "Starts a new epoch (bootstrap, or a post-departure rotation). See ChannelCrypto.start_new_epoch/2."
  def start_epoch(conn, %{"channel_id" => channel_id}) do
    user = Guardian.Plug.current_resource(conn)
    channel_or_404(conn, channel_id, fn channel ->
      require_view!(conn, channel, user.id, fn ->
        case ChannelCrypto.start_new_epoch(channel_id, user.id) do
          {:ok, epoch} ->
            # `created: true` tells the caller it's the one that has to
            # generate the actual key material and distribute it -- the
            # server never generates or sees the key itself.
            conn |> put_status(201) |> json(%{epoch: epoch, created: true})
          {:error, _} ->
            # Lost the race to bootstrap/rotate -- not an error from the
            # caller's point of view, just tell them what actually won,
            # and that they should wait for a delivery instead of
            # minting their own competing key.
            json(conn, %{epoch: ChannelCrypto.current_epoch(channel_id), created: false})
        end
      end)
    end)
  end

  @doc "Members who still need a delivery for the given epoch."
  def pending(conn, %{"channel_id" => channel_id, "epoch" => epoch_str}) do
    user = Guardian.Plug.current_resource(conn)
    channel_or_404(conn, channel_id, fn channel ->
      require_view!(conn, channel, user.id, fn ->
        epoch = String.to_integer(epoch_str)
        json(conn, %{user_ids: ChannelCrypto.pending_recipients(channel_id, epoch)})
      end)
    end)
  end

  @doc """
  Bulk-records this sender's encrypted deliveries for one epoch, one per
  recipient. Each entry uses the same envelope shape as a DM message
  since that's exactly what it is under the hood -- see
  DmSessionManager.encryptForSend client-side.
  """
  def deliver(conn, %{"channel_id" => channel_id, "epoch" => epoch, "deliveries" => deliveries}) do
    user = Guardian.Plug.current_resource(conn)
    channel_or_404(conn, channel_id, fn channel ->
      require_view!(conn, channel, user.id, fn ->
        results =
          Enum.map(deliveries, fn d ->
            ChannelCrypto.record_delivery(%{
              channel_id:   channel_id,
              epoch:        epoch,
              sender_id:    user.id,
              recipient_id: d["recipient_id"],
              content:      d["content"],
              ratchet_key:  d["ratchet_key"],
              msg_number:   d["msg_number"],
              prev_chain:   d["prev_chain"],
              nonce:        d["nonce"],
              x3dh_header:  d["x3dh_header"]
            })
          end)

        if Enum.all?(results, &match?({:ok, _}, &1)) do
          json(conn, %{ok: true, delivered: length(results)})
        else
          conn |> put_status(422) |> json(%{error: "One or more deliveries were malformed"})
        end
      end)
    end)
  end

  @doc "Every epoch delivery addressed to the current user in this channel -- no extra permission check beyond being authenticated, since it's intrinsically scoped to their own recipient_id."
  def my_deliveries(conn, %{"channel_id" => channel_id}) do
    user = Guardian.Plug.current_resource(conn)
    deliveries = ChannelCrypto.my_deliveries(channel_id, user.id)
    json(conn, %{deliveries: Enum.map(deliveries, &ChannelCrypto.delivery_json/1)})
  end
end
