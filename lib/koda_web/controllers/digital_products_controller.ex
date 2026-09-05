defmodule KodaWeb.DigitalProductsController do
  use KodaWeb, :controller
  alias Koda.DigitalProducts

  # ── Product listing ───────────────────────────────────────────────────────

  def index(conn, params) do
    user = Guardian.Plug.current_resource(conn)
    opts = []
    opts = if params["server_id"], do: [{:server_id, params["server_id"]} | opts], else: opts
    opts = if params["creator_id"], do: [{:creator_id, params["creator_id"]} | opts], else: opts
    products = DigitalProducts.list_products(opts)

    # Annotate with purchase status and free eligibility
    products = Enum.map(products, fn p ->
      product = DigitalProducts.get_product(p.id)
      p
      |> Map.put(:already_purchased, DigitalProducts.already_purchased?(p.id, user.id))
      |> Map.put(:free_for_you, product && DigitalProducts.free_for_subscriber?(product, user.id))
    end)

    json(conn, %{products: products})
  end

  def show(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)
    case DigitalProducts.get_product(id) do
      nil -> conn |> put_status(404) |> json(%{error: "Not found"})
      product ->
        json(conn, %{
          product: DigitalProducts.product_json(product),
          already_purchased: DigitalProducts.already_purchased?(id, user.id),
          free_for_you: DigitalProducts.free_for_subscriber?(product, user.id),
          license_key_count: if(product.product_type == "license_key",
            do: DigitalProducts.available_license_count(id), else: nil)
        })
    end
  end

  # ── Creator product management ────────────────────────────────────────────

  def create(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    # Must have Stripe Connect to sell paid products
    price_cents = params["price_cents"] || 0
    if price_cents > 0 do
      case Koda.Marketplace.get_connect_account(user.id) do
        nil ->
          conn |> put_status(422) |> json(%{error: "Connect Stripe to sell paid products"})
          |> halt()
        acct ->
          unless acct.charges_enabled do
            conn |> put_status(422) |> json(%{error: "Complete Stripe onboarding first"})
            |> halt()
          end
      end
    end

    attrs = %{
      creator_id:       user.id,
      server_id:        params["server_id"],
      free_for_tier_id: params["free_for_tier_id"],
      title:            params["title"],
      description:      params["description"],
      price_cents:      price_cents,
      product_type:     params["product_type"] || "file",
      file_url:         params["file_url"],
      file_name:        params["file_name"],
      file_size_bytes:  params["file_size_bytes"],
      scope:            params["scope"] || "server"
    }

    case DigitalProducts.create_product(attrs) do
      {:ok, product} ->
        conn |> put_status(201) |> json(%{product: DigitalProducts.product_json(product)})
      {:error, cs} ->
        conn |> put_status(422) |> json(%{errors: format_errors(cs)})
    end
  end

  def update(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)
    case DigitalProducts.get_product(id) do
      nil -> conn |> put_status(404) |> json(%{error: "Not found"})
      product ->
        unless product.creator_id == user.id do
          conn |> put_status(403) |> json(%{error: "Not your product"})
        else
          attrs = Map.take(params, ["title", "description", "price_cents",
                                    "free_for_tier_id", "scope", "active"])
                  |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)
          case DigitalProducts.update_product(product, attrs) do
            {:ok, p}     -> json(conn, %{product: DigitalProducts.product_json(p)})
            {:error, cs} -> conn |> put_status(422) |> json(%{errors: format_errors(cs)})
          end
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)
    case DigitalProducts.get_product(id) do
      nil -> conn |> put_status(404) |> json(%{error: "Not found"})
      product ->
        unless product.creator_id == user.id do
          conn |> put_status(403) |> json(%{error: "Not your product"})
        else
          DigitalProducts.delete_product(product)
          json(conn, %{ok: true})
        end
    end
  end

  # ── License keys ──────────────────────────────────────────────────────────

  def add_license_keys(conn, %{"id" => id, "keys" => keys}) do
    user = Guardian.Plug.current_resource(conn)
    case DigitalProducts.get_product(id) do
      nil -> conn |> put_status(404) |> json(%{error: "Not found"})
      product ->
        unless product.creator_id == user.id do
          conn |> put_status(403) |> json(%{error: "Not your product"})
        else
          key_list = String.split(keys, "\n") |> Enum.filter(&(String.trim(&1) != ""))
          {count, _} = DigitalProducts.bulk_add_license_keys(id, key_list)
          json(conn, %{ok: true, added: count,
                       available: DigitalProducts.available_license_count(id)})
        end
    end
  end

  # ── Purchases ─────────────────────────────────────────────────────────────

  def purchase(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)
    case DigitalProducts.create_purchase_intent(id, user.id) do
      {:ok, %{free: true, download_token: token, license_key: key}} ->
        json(conn, %{free: true, download_token: token, license_key: key})
      {:ok, %{client_secret: secret}} ->
        json(conn, %{free: false, client_secret: secret})
      {:error, :already_purchased} ->
        conn |> put_status(422) |> json(%{error: "Already purchased"})
      {:error, :product_not_found} ->
        conn |> put_status(404) |> json(%{error: "Product not found"})
      {:error, :no_keys_available} ->
        conn |> put_status(422) |> json(%{error: "No license keys available"})
      {:error, err} ->
        conn |> put_status(422) |> json(%{error: inspect(err)})
    end
  end

  def my_purchases(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    purchases = DigitalProducts.my_purchases(user.id)
    json(conn, %{purchases: purchases})
  end

  def download(conn, %{"token" => token}) do
    case DigitalProducts.validate_download_token(token) do
      {:ok, product} ->
        # Redirect to R2 signed URL or serve file URL
        redirect(conn, external: product.file_url)
      {:error, :invalid_token} ->
        conn |> put_status(404) |> json(%{error: "Invalid download token"})
      {:error, :token_expired} ->
        conn |> put_status(410) |> json(%{error: "Download link expired"})
      {:error, reason} ->
        conn |> put_status(422) |> json(%{error: inspect(reason)})
    end
  end

  defp format_errors(cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, _} -> msg end)
  end
end
