defmodule KodaWeb.ServerSubscriptionController do
  use KodaWeb, :controller
  alias Koda.ServerSubscriptions

  # ── Tier management (owner only) ──────────────────────────────────────────

  def list_tiers(conn, %{"server_id" => server_id}) do
    tiers = ServerSubscriptions.list_tiers(server_id)
    json(conn, %{tiers: tiers})
  end

  def create_tier(conn, %{"server_id" => server_id} = params) do
    user = Guardian.Plug.current_resource(conn)
    unless Koda.Servers.owner?(server_id, user.id) do
      conn |> put_status(403) |> json(%{error: "Only server owners can manage tiers"})
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
          conn |> put_status(201) |> json(%{tier: ServerSubscriptions.tier_json(tier)})
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
        unless Koda.Servers.owner?(tier.server_id, user.id) do
          conn |> put_status(403) |> json(%{error: "Only server owners can manage tiers"})
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
        unless Koda.Servers.owner?(tier.server_id, user.id) do
          conn |> put_status(403) |> json(%{error: "Only server owners can manage tiers"})
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
      {:error, err} ->
        conn |> put_status(422) |> json(%{error: inspect(err)})
    end
  end

  defp format_errors(cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, _} -> msg end)
  end
end
