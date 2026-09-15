defmodule KodaWeb.ServerSubscriptionController do
  use KodaWeb, :controller
  alias Koda.ServerSubscriptions

  # ── Tier management (owner, or a role with manage_marketplace) ─────────────

  defp can_manage_marketplace?(server_id, user_id) do
    Koda.Servers.owner?(server_id, user_id) or
      Koda.Servers.member_can?(server_id, user_id, "manage_marketplace")
  end

  def list_tiers(conn, %{"server_id" => server_id}) do
    tiers = ServerSubscriptions.list_tiers(server_id)
    json(conn, %{tiers: tiers})
  end

  def create_tier(conn, %{"server_id" => server_id} = params) do
    user = Guardian.Plug.current_resource(conn)
    unless can_manage_marketplace?(server_id, user.id) do
      conn |> put_status(403) |> json(%{error: "Not authorized to manage this server's marketplace"})
    else
      attrs = %{
        server_id:                    server_id,
        name:                         params["name"],
        description:                  params["description"],
        price_cents:                  params["price_cents"],
        role_id:                      params["role_id"],
        marketplace_discount_percent: params["marketplace_discount_percent"] || 0,
        position:                     params["position"] || 1
      }
      case ServerSubscriptions.create_tier(attrs) do
        {:ok, tier} ->
          conn |> put_status(201) |> json(%{
            tier: ServerSubscriptions.tier_json(tier),
            # Surfaced so the client can warn the owner up front rather
            # than members hitting a checkout error later -- members
            # literally cannot pay into this tier until the owner
            # connects Stripe (see create_subscription_intent/2).
            owner_payable: ServerSubscriptions.owner_payable?(server_id)
          })
        {:error, :max_tiers_reached} ->
          conn |> put_status(422) |> json(%{error: "Maximum of 3 tiers per server"})
        {:error, cs} ->
          conn |> put_status(422) |> json(%{errors: format_errors(cs)})
      end
    end
  end

  def update_tier(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)
    case ServerSubscriptions.get_tier(id) do
      nil -> conn |> put_status(404) |> json(%{error: "Not found"})
      tier ->
        unless can_manage_marketplace?(tier.server_id, user.id) do
          conn |> put_status(403) |> json(%{error: "Not authorized to manage this server's marketplace"})
        else
          attrs = Map.take(params, ["name", "description", "price_cents",
                                    "role_id", "marketplace_discount_percent",
                                    "position", "active"])
                  |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)
          case ServerSubscriptions.update_tier(tier, attrs) do
            {:ok, t}     -> json(conn, %{tier: ServerSubscriptions.tier_json(t)})
            {:error, cs} -> conn |> put_status(422) |> json(%{errors: format_errors(cs)})
          end
        end
    end
  end

  def delete_tier(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)
    case ServerSubscriptions.get_tier(id) do
      nil -> conn |> put_status(404) |> json(%{error: "Not found"})
      tier ->
        unless can_manage_marketplace?(tier.server_id, user.id) do
          conn |> put_status(403) |> json(%{error: "Not authorized to manage this server's marketplace"})
        else
          ServerSubscriptions.delete_tier(tier)
          json(conn, %{ok: true})
        end
    end
  end

  # ── User subscriptions ────────────────────────────────────────────────────

  def my_subscription(conn, %{"server_id" => server_id}) do
    user = Guardian.Plug.current_resource(conn)
    sub = ServerSubscriptions.active_subscription(server_id, user.id)
    tiers = ServerSubscriptions.list_tiers(server_id)
    json(conn, %{
      tiers: tiers,
      active_subscription: sub && %{
        tier_id:    sub.tier_id,
        expires_at: DateTime.to_iso8601(sub.expires_at),
        status:     sub.status
      }
    })
  end

  def subscribe(conn, %{"tier_id" => tier_id}) do
    user = Guardian.Plug.current_resource(conn)
    case ServerSubscriptions.create_subscription_intent(tier_id, user.id) do
      {:ok, result} ->
        conn |> put_status(201) |> json(result)
      {:error, :tier_not_found} ->
        conn |> put_status(404) |> json(%{error: "Tier not found"})
      {:error, :owner_not_connected} ->
        conn |> put_status(422) |> json(%{error: "This server's owner hasn't connected Stripe yet"})
      {:error, :owner_not_onboarded} ->
        conn |> put_status(422) |> json(%{error: "This server's owner hasn't finished Stripe onboarding"})
      {:error, err} ->
        conn |> put_status(422) |> json(%{error: inspect(err)})
    end
  end

  defp format_errors(cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, _} -> msg end)
  end
end
