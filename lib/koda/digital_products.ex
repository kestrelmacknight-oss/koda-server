defmodule Koda.DigitalProducts do
  import Ecto.Query
  alias Koda.Repo

  defmodule Product do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id
    schema "digital_products" do
      field :creator_id,       :binary_id
      field :server_id,        :binary_id
      field :free_for_tier_id, :binary_id
      field :title,            :string
      field :description,      :string
      field :price_cents,      :integer, default: 0
      field :product_type,     :string, default: "file"
      field :file_url,         :string
      field :file_name,        :string
      field :file_size_bytes,  :integer
      field :scope,            :string, default: "server"
      field :active,           :boolean, default: true
      field :purchase_count,   :integer, default: 0
      timestamps(type: :utc_datetime_usec)
    end
    def changeset(p, attrs) do
      p |> cast(attrs, [:creator_id, :server_id, :free_for_tier_id, :title,
                        :description, :price_cents, :product_type, :file_url,
                        :file_name, :file_size_bytes, :scope, :active])
        |> validate_required([:creator_id, :title, :price_cents, :product_type])
        |> validate_inclusion(:product_type, ["file", "license_key"])
        |> validate_inclusion(:scope, ["server", "creator"])
        |> validate_number(:price_cents, greater_than_or_equal_to: 0)
    end
  end

  defmodule Purchase do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id
    schema "product_purchases" do
      field :product_id,               :binary_id
      field :buyer_id,                 :binary_id
      field :amount_cents,             :integer
      field :stripe_payment_intent_id, :string
      field :license_key,              :string
      field :download_token,           :string
      field :download_token_expires_at, :utc_datetime_usec
      field :download_count,           :integer, default: 0
      field :status,                   :string, default: "pending"
      timestamps(type: :utc_datetime_usec)
    end
    def changeset(p, attrs) do
      p |> cast(attrs, [:product_id, :buyer_id, :amount_cents,
                        :stripe_payment_intent_id, :license_key,
                        :download_token, :download_token_expires_at,
                        :download_count, :status])
        |> validate_required([:product_id, :buyer_id, :amount_cents])
    end
  end

  defmodule LicenseKey do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id
    schema "license_keys" do
      field :product_id,  :binary_id
      field :key,         :string
      field :claimed_by,  :binary_id
      field :claimed_at,  :utc_datetime_usec
      field :purchase_id, :binary_id
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end
    def changeset(k, attrs) do
      k |> cast(attrs, [:product_id, :key, :claimed_by, :claimed_at, :purchase_id])
        |> validate_required([:product_id, :key])
        |> unique_constraint(:key)
    end
  end

  # ── Product CRUD ──────────────────────────────────────────────────────────

  def list_products(opts \\ []) do
    query = from p in Product, where: p.active == true

    query = case Keyword.get(opts, :server_id) do
      nil -> query
      id  -> where(query, [p], p.server_id == ^id or p.scope == "creator")
    end

    query = case Keyword.get(opts, :creator_id) do
      nil -> query
      id  -> where(query, [p], p.creator_id == ^id)
    end

    Repo.all(from p in query, order_by: [desc: p.inserted_at])
    |> Enum.map(&product_json/1)
  end

  def get_product(id), do: Repo.get(Product, id)

  def create_product(attrs) do
    %Product{} |> Product.changeset(attrs) |> Repo.insert()
  end

  def update_product(product, attrs) do
    product |> Product.changeset(attrs) |> Repo.update()
  end

  def delete_product(product) do
    product |> Product.changeset(%{active: false}) |> Repo.update()
  end

  # ── License keys ──────────────────────────────────────────────────────────

  def bulk_add_license_keys(product_id, keys) do
    now = DateTime.utc_now()
    entries = Enum.map(keys, fn key ->
      %{id: Ecto.UUID.generate(), product_id: product_id,
        key: String.trim(key), inserted_at: now}
    end)
    Repo.insert_all(LicenseKey, entries, on_conflict: :nothing)
  end

  def available_license_count(product_id) do
    Repo.aggregate(from(k in LicenseKey,
      where: k.product_id == ^product_id and is_nil(k.claimed_by)), :count)
  end

  defp claim_license_key(product_id, buyer_id, purchase_id) do
    case Repo.one(from k in LicenseKey,
        where: k.product_id == ^product_id and is_nil(k.claimed_by),
        limit: 1, lock: "FOR UPDATE SKIP LOCKED") do
      nil -> {:error, :no_keys_available}
      key ->
        key |> LicenseKey.changeset(%{
          claimed_by:  buyer_id,
          claimed_at:  DateTime.utc_now(),
          purchase_id: purchase_id
        }) |> Repo.update()
    end
  end

  # ── Purchases ────────────────────────────────────────────────────────────

  def already_purchased?(product_id, buyer_id) do
    Repo.exists?(from p in Purchase,
      where: p.product_id == ^product_id and p.buyer_id == ^buyer_id
          and p.status == "complete")
  end

  def free_for_subscriber?(product, user_id) do
    case product.free_for_tier_id do
      nil -> false
      tier_id ->
        Repo.exists?(from s in Koda.ServerSubscriptions.Subscription,
          where: s.tier_id == ^tier_id and s.user_id == ^user_id
              and s.status == "active" and s.expires_at > ^DateTime.utc_now())
    end
  end

  def create_purchase_intent(product_id, buyer_id) do
    product = get_product(product_id)
    unless product && product.active do
      {:error, :product_not_found}
    else
      cond do
        already_purchased?(product_id, buyer_id) ->
          {:error, :already_purchased}

        free_for_subscriber?(product, buyer_id) ->
          # Free for subscriber — skip Stripe
          complete_free_purchase(product, buyer_id)

        product.price_cents == 0 ->
          # Free product
          complete_free_purchase(product, buyer_id)

        true ->
          # Paid — create Stripe PaymentIntent
          stripe_key = Application.get_env(:koda, :stripe_secret_key)
          case Stripe.PaymentIntent.create(%{
            amount:   product.price_cents,
            currency: "usd",
            metadata: %{
              type:       "digital_product",
              product_id: product_id,
              buyer_id:   buyer_id
            }
          }, api_key: stripe_key) do
            {:ok, pi} ->
              {:ok, purchase} = %Purchase{}
              |> Purchase.changeset(%{
                product_id:               product_id,
                buyer_id:                 buyer_id,
                amount_cents:             product.price_cents,
                stripe_payment_intent_id: pi.id,
                status:                   "pending"
              })
              |> Repo.insert()
              {:ok, %{purchase: purchase, client_secret: pi.client_secret,
                      free: false}}
            {:error, err} -> {:error, err}
          end
      end
    end
  end

  defp complete_free_purchase(product, buyer_id) do
    token = generate_download_token()
    expires_at = DateTime.utc_now() |> DateTime.add(24 * 3600, :second)

    {:ok, purchase} = %Purchase{}
    |> Purchase.changeset(%{
      product_id:                product.id,
      buyer_id:                  buyer_id,
      amount_cents:              0,
      download_token:            token,
      download_token_expires_at: expires_at,
      status:                    "complete"
    })
    |> Repo.insert()

    # Claim license key if needed
    license_key = if product.product_type == "license_key" do
      case claim_license_key(product.id, buyer_id, purchase.id) do
        {:ok, k} -> k.key
        _        -> nil
      end
    end

    # Update purchase with license key
    if license_key do
      purchase |> Purchase.changeset(%{license_key: license_key}) |> Repo.update()
    end

    # Increment purchase count
    Repo.update_all(from(p in Product, where: p.id == ^product.id),
      inc: [purchase_count: 1])

    {:ok, %{purchase: purchase, download_token: token,
            license_key: license_key, free: true}}
  end

  def confirm_purchase(stripe_payment_intent_id) do
    case Repo.get_by(Purchase, stripe_payment_intent_id: stripe_payment_intent_id) do
      nil -> {:error, :not_found}
      purchase ->
        product = get_product(purchase.product_id)
        token = generate_download_token()
        expires_at = DateTime.utc_now() |> DateTime.add(24 * 3600, :second)

        # Claim license key if needed
        license_key = if product && product.product_type == "license_key" do
          case claim_license_key(product.id, purchase.buyer_id, purchase.id) do
            {:ok, k} -> k.key
            _        -> nil
          end
        end

        {:ok, updated} = purchase
        |> Purchase.changeset(%{
          status:                    "complete",
          download_token:            token,
          download_token_expires_at: expires_at,
          license_key:               license_key
        })
        |> Repo.update()

        # Increment purchase count
        if product do
          Repo.update_all(from(p in Product, where: p.id == ^product.id),
            inc: [purchase_count: 1])
        end

        # Notify buyer via PubSub
        Phoenix.PubSub.broadcast(Koda.PubSub, "user:#{purchase.buyer_id}",
          {:purchase_complete, %{
            product_id:     purchase.product_id,
            download_token: token,
            license_key:    license_key
          }})

        {:ok, updated}
    end
  end

  def validate_download_token(token) do
    case Repo.get_by(Purchase, download_token: token) do
      nil -> {:error, :invalid_token}
      purchase ->
        if purchase.status != "complete" do
          {:error, :not_purchased}
        else
          case purchase.download_token_expires_at do
            nil -> {:error, :token_expired}
            exp ->
              if DateTime.compare(exp, DateTime.utc_now()) == :gt do
                # Increment download count
                Repo.update_all(
                  from(p in Purchase, where: p.id == ^purchase.id),
                  inc: [download_count: 1])
                product = get_product(purchase.product_id)
                {:ok, product}
              else
                {:error, :token_expired}
              end
          end
        end
    end
  end

  def my_purchases(user_id) do
    Repo.all(from p in Purchase,
      where: p.buyer_id == ^user_id and p.status == "complete",
      order_by: [desc: p.inserted_at])
    |> Enum.map(fn p ->
      product = get_product(p.product_id)
      %{
        id:             p.id,
        product:        product && product_json(product),
        amount_cents:   p.amount_cents,
        license_key:    p.license_key,
        download_token: p.download_token,
        download_expires_at: p.download_token_expires_at &&
          DateTime.to_iso8601(p.download_token_expires_at),
        download_count: p.download_count,
        purchased_at:   DateTime.to_iso8601(p.inserted_at)
      }
    end)
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp generate_download_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  def product_json(p) do
    %{
      id:              p.id,
      creator_id:      p.creator_id,
      server_id:       p.server_id,
      free_for_tier_id: p.free_for_tier_id,
      title:           p.title,
      description:     p.description,
      price_cents:     p.price_cents,
      product_type:    p.product_type,
      file_name:       p.file_name,
      file_size_bytes: p.file_size_bytes,
      scope:           p.scope,
      purchase_count:  p.purchase_count,
      active:          p.active
    }
  end
end
