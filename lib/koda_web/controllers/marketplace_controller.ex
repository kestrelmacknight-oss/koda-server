defmodule KodaWeb.MarketplaceController do
  use KodaWeb, :controller
  alias Koda.Marketplace

  # ── Stripe Connect onboarding ─────────────────────────────────────────────

  def connect_account(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    case Marketplace.get_connect_account(user.id) do
      nil ->
        case Marketplace.create_connect_account(user.id) do
          {:ok, acct} -> json(conn, %{account_id: acct.stripe_account_id,
                                      onboarding_complete: false})
          {:error, err} ->
        IO.inspect(err, label: "Stripe Connect error")
        conn |> put_status(422) |> json(%{error: inspect(err)})
        end
      acct ->
        json(conn, %{account_id: acct.stripe_account_id,
                     onboarding_complete: acct.onboarding_complete,
                     payouts_enabled: acct.payouts_enabled,
                     charges_enabled: acct.charges_enabled})
    end
  end

  def onboarding_url(conn, params) do
    user = Guardian.Plug.current_resource(conn)
    return_url  = Map.get(params, "return_url",  "https://koda.fyi/creator/connected")
    refresh_url = Map.get(params, "refresh_url", "https://koda.fyi/creator/refresh")
    case Marketplace.get_onboarding_url(user.id, return_url, refresh_url) do
      {:ok, link}       -> json(conn, %{url: link.url})
      {:error, :no_account} ->
        conn |> put_status(404) |> json(%{error: "No Connect account found"})
      {:error, err}     -> conn |> put_status(422) |> json(%{error: inspect(err)})
    end
  end

  def sync_account(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    case Marketplace.sync_connect_account(user.id) do
      {:ok, acct} ->
        json(conn, %{onboarding_complete: acct.onboarding_complete,
                     payouts_enabled: acct.payouts_enabled,
                     charges_enabled: acct.charges_enabled})
      {:error, err} -> conn |> put_status(422) |> json(%{error: inspect(err)})
    end
  end

  # ── Tips ──────────────────────────────────────────────────────────────────

  def tip_preview(conn, %{"to_user_id" => to_user_id, "amount_cents" => amount_str}) do
    amount_cents = String.to_integer(amount_str)
    calc = Marketplace.calculate_tip(amount_cents)
    json(conn, calc)
  end

  def create_tip(conn, %{"to_user_id" => to_user_id,
                          "amount_cents" => amount_cents,
                          "server_id" => server_id} = params) do
    user = Guardian.Plug.current_resource(conn)
    message = Map.get(params, "message")
    case Marketplace.create_tip_payment_intent(
        user.id, to_user_id, server_id, amount_cents, message) do
      {:ok, %{tip: tip, client_secret: secret}} ->
        conn |> put_status(201) |> json(%{
          tip: Marketplace.tip_json(tip),
          client_secret: secret
        })
      {:error, :creator_not_connected} ->
        conn |> put_status(422) |> json(%{error: "Creator has not connected Stripe"})
      {:error, :creator_not_onboarded} ->
        conn |> put_status(422) |> json(%{error: "Creator has not completed Stripe onboarding"})
      {:error, err} ->
        conn |> put_status(422) |> json(%{error: inspect(err)})
    end
  end

  # ── Subscriptions ─────────────────────────────────────────────────────────

  def subscription_info(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    sub = Marketplace.active_subscription(user.id)
    json(conn, %{
      tier: user.koda_tier || "free",
      subscription: if(sub, do: %{
        tier:       sub.tier,
        expires_at: DateTime.to_iso8601(sub.expires_at),
        active:     sub.active
      }, else: nil),
      prices: %{
        spark: Marketplace.subscription_price("spark"),
        pulse: Marketplace.subscription_price("pulse")
      }
    })
  end

  def create_subscription(conn, %{"tier" => tier} = params) do
    user = Guardian.Plug.current_resource(conn)
    server_id      = Map.get(params, "server_id")
    gifted_to      = Map.get(params, "gifted_to_user_id")
    target_user_id = gifted_to || user.id
    gifted_by      = if gifted_to, do: user.id, else: nil

    case Marketplace.create_subscription_payment_intent(
        target_user_id, tier, server_id, gifted_by) do
      {:ok, client_secret} ->
        conn |> put_status(201) |> json(%{client_secret: client_secret,
                                          tier: tier,
                                          amount_cents: Marketplace.subscription_price(tier)})
      {:error, :invalid_tier} ->
        conn |> put_status(422) |> json(%{error: "Invalid tier. Use spark or pulse"})
      {:error, err} ->
        conn |> put_status(422) |> json(%{error: inspect(err)})
    end
  end

  # ── Server bank ───────────────────────────────────────────────────────────

  def server_bank(conn, %{"server_id" => server_id}) do
    balance = Marketplace.get_server_bank_balance(server_id)
    json(conn, %{server_id: server_id, balance: balance,
                 balance_usd: balance / 100.0})
  end

  # ── Stripe health check ──────────────────────────────────────────────────────

  def stripe_status(conn, _params) do
    stripe_key = Application.get_env(:koda, :stripe_secret_key)
    case Stripe.Balance.retrieve(api_key: stripe_key) do
      {:ok, balance} ->
        available = hd(balance.available)
        json(conn, %{
          connected: true,
          currency: available.currency,
          available_cents: available.amount
        })
      {:error, err} ->
        conn |> put_status(422) |> json(%{connected: false, error: inspect(err)})
    end
  end

  # ── Stripe webhooks ───────────────────────────────────────────────────────

  def webhook(conn, params) do
    webhook_secret = Application.get_env(:koda, :stripe_webhook_secret)
    payload = conn.assigns[:raw_body] || Jason.encode!(params)
    sig = get_req_header(conn, "stripe-signature") |> List.first()

    case Stripe.Webhook.construct_event(payload, sig, webhook_secret) do
      {:ok, event} ->
        type   = event["type"] || event[:type]
        object = get_in(event, ["data", "object"]) || get_in(event, [:data, :object]) || %{}
        Task.start(fn -> Marketplace.handle_webhook(type, object) end)
        json(conn, %{ok: true})
      {:error, _} ->
        conn |> put_status(400) |> json(%{error: "Invalid webhook signature"})
    end
  end
end
