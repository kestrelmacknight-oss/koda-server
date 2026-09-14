defmodule Koda.Throne do
  @moduledoc """
  Throne.com wishlist-gifting integration.

  Throne has no OAuth/API-key flow for creators -- instead, each creator
  pastes a personal webhook URL (containing an opaque token minted here)
  into their own Throne dashboard. Every event Throne sends is signed
  platform-wide with a single Ed25519 key, independent of which creator
  it's for, so verification only needs that one public key while routing
  still happens per-creator via the token in the URL.

  See: https://help.throne.com/en/articles/15935990-how-do-i-set-up-webhook-integration
  """
  require Logger
  import Ecto.Query
  alias Koda.Repo
  alias Koda.Auth.User

  # Signed events older/newer than this are rejected, guarding against
  # replay of a captured request.
  @max_clock_skew_seconds 300

  defmodule ThroneGift do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "throne_gifts" do
      field :creator_id,        :binary_id
      field :event_id,          :string
      field :event_type,        :string
      field :gifter_username,   :string
      field :amount_cents,      :integer
      field :currency,          :string
      field :item_name,         :string
      field :item_thumbnail_url, :string
      field :message,           :string
      field :is_surprise_gift,  :boolean, default: false
      field :raw_payload,       :map
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    def changeset(g, attrs) do
      g
      |> cast(attrs, [:creator_id, :event_id, :event_type, :gifter_username,
                      :amount_cents, :currency, :item_name, :item_thumbnail_url,
                      :message, :is_surprise_gift, :raw_payload])
      |> validate_required([:creator_id, :event_id, :event_type])
      |> unique_constraint(:event_id)
    end
  end

  # ── Webhook token (identifies which creator a webhook URL belongs to) ──────

  def get_or_create_webhook_token(%User{} = user) do
    if user.throne_webhook_token do
      user.throne_webhook_token
    else
      token = generate_token()
      {:ok, updated} = user |> Ecto.Changeset.change(throne_webhook_token: token) |> Repo.update()
      updated.throne_webhook_token
    end
  end

  def regenerate_webhook_token(%User{} = user) do
    token = generate_token()
    user |> Ecto.Changeset.change(throne_webhook_token: token) |> Repo.update()
  end

  defp generate_token, do: :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)

  def get_creator_by_token(token) do
    Repo.get_by(User, throne_webhook_token: token)
  end

  # ── Signature verification ──────────────────────────────────────────────

  def verify_webhook(raw_body, timestamp, signature_hex)
      when is_binary(raw_body) and is_binary(timestamp) and is_binary(signature_hex) do
    with true          <- fresh_timestamp?(timestamp),
         {:ok, sig}     <- decode_signature(signature_hex) do
      message = timestamp <> "." <> raw_body
      :crypto.verify(:eddsa, :none, message, sig, [public_key(), :ed25519])
    else
      _ -> false
    end
  end
  def verify_webhook(_, _, _), do: false

  defp fresh_timestamp?(ts) do
    case Integer.parse(ts) do
      {seconds, ""} -> abs(System.system_time(:second) - seconds) <= @max_clock_skew_seconds
      _ -> false
    end
  end

  defp decode_signature(hex) do
    case Base.decode16(hex, case: :mixed) do
      {:ok, sig} when byte_size(sig) == 64 -> {:ok, sig}
      _ -> :error
    end
  end

  defp public_key do
    pem = Application.get_env(:koda, :throne, [])[:public_key_pem] || default_pem()
    [{:SubjectPublicKeyInfo, der, _}] = :public_key.pem_decode(pem)
    # RFC 8410: an Ed25519 SubjectPublicKeyInfo is always a fixed 12-byte
    # ASN.1 prefix followed by the raw 32-byte key -- no per-key structure
    # to parse further.
    binary_part(der, byte_size(der) - 32, 32)
  end

  defp default_pem do
    """
    -----BEGIN PUBLIC KEY-----
    MCowBQYDK2VwAyEAPXbUfxh7XL4SYUVcfhmYMIbxvtR9E9LDd8gPJ1PwSD8=
    -----END PUBLIC KEY-----
    """
  end

  # ── Event handling ───────────────────────────────────────────────────────

  @doc """
  Records an inbound event and notifies the creator. Idempotent on
  event_id, since webhook senders (Throne included) retry on timeout.
  """
  def handle_event(%User{} = creator, %{"event_id" => event_id, "event_type" => event_type} = payload) do
    data = Map.get(payload, "data", %{})

    attrs = %{
      creator_id:         creator.id,
      event_id:           event_id,
      event_type:         event_type,
      gifter_username:    Map.get(data, "gifter_username"),
      amount_cents:       Map.get(data, "amount") || Map.get(data, "price"),
      currency:           Map.get(data, "currency"),
      item_name:          Map.get(data, "item_name"),
      item_thumbnail_url: Map.get(data, "item_thumbnail_url"),
      message:            Map.get(data, "message"),
      is_surprise_gift:   Map.get(data, "is_surprise_gift", false),
      raw_payload:        payload
    }

    case %ThroneGift{} |> ThroneGift.changeset(attrs) |> Repo.insert() do
      {:ok, gift} ->
        notify_creator(creator, gift)
        {:ok, gift}
      {:error, %Ecto.Changeset{errors: [event_id: _]}} ->
        # Already processed this event_id -- webhook retry, not an error.
        {:ok, :duplicate}
      {:error, reason} ->
        {:error, reason}
    end
  end
  def handle_event(_, _), do: {:error, :invalid_payload}

  defp notify_creator(creator, gift) do
    gifter = gift.gifter_username || "Someone"
    amount = format_amount(gift.amount_cents, gift.currency)
    title  = "Gift from #{gifter} on Throne"
    body   = if amount, do: "#{gifter} sent #{amount}" <> item_suffix(gift), else: item_suffix(gift)

    {:ok, notif} = Koda.Notifications.create(creator.id, "throne_gift", title, body, %{
      gift_id: gift.id, event_type: gift.event_type, item_name: gift.item_name
    })

    Phoenix.PubSub.broadcast(Koda.PubSub, "user:#{creator.id}", {:notification, %{
      id:          notif.id,
      type:        notif.type,
      title:       notif.title,
      body:        notif.body,
      data:        notif.data,
      inserted_at: DateTime.to_iso8601(notif.inserted_at)
    }})
  end

  defp item_suffix(%{item_name: nil}), do: ""
  defp item_suffix(%{item_name: name}), do: " for #{name}"

  defp format_amount(nil, _), do: nil
  defp format_amount(cents, currency) do
    amount = :erlang.float_to_binary(cents / 100, decimals: 2)
    "#{amount} #{currency || "USD"}"
  end
end
