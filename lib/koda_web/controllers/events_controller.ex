defmodule KodaWeb.EventsController do
  use KodaWeb, :controller
  alias Koda.{Events, Servers}

  defp can_manage_marketplace?(server_id, user_id) do
    Servers.owner?(server_id, user_id) or Servers.member_can?(server_id, user_id, "manage_marketplace")
  end

  # The event's own creator can always edit/delete it; otherwise it
  # takes the same authority as pricing/ticketing it in the first
  # place. Not gated by anything narrower (e.g. manage_channels) since
  # nothing like that existed here before this client UI made
  # update/delete actually reachable -- previously anyone could edit or
  # delete any event via the API with no check at all.
  defp can_manage_event?(event, user_id) do
    event.created_by == user_id or can_manage_marketplace?(event.server_id, user_id)
  end

  def index(conn, %{"channel_id" => channel_id} = params) do
    opts = [from: parse_dt(params["from"]), to: parse_dt(params["to"])]
           |> Enum.reject(fn {_, v} -> is_nil(v) end)
    events = Events.list_events(channel_id, opts)
    user = Guardian.Plug.current_resource(conn)
    ticket_event_ids = MapSet.new(Events.my_ticket_event_ids(user.id))
    events_with_sub = Enum.map(events, fn e ->
      e
      |> Map.put(:subscribed, Events.subscribed?(e.id, user.id))
      |> Map.put(:has_ticket, MapSet.member?(ticket_event_ids, e.id))
    end)
    json(conn, %{events: events_with_sub})
  end

  def create(conn, %{"channel_id" => channel_id} = params) do
    user = Guardian.Plug.current_resource(conn)
    channel = Koda.Servers.get_channel(channel_id)
    price_cents = params["price_cents"] || 0

    if price_cents > 0 and not can_manage_marketplace?(channel.server_id, user.id) do
      conn |> put_status(403) |> json(%{error: "Not authorized to sell tickets for this server"})
    else
      attrs = %{
        channel_id:       channel_id,
        server_id:        channel.server_id,
        created_by:       user.id,
        title:            params["title"],
        description:      params["description"],
        location:         params["location"],
        start_at:         parse_dt(params["start_at"]),
        end_at:           parse_dt(params["end_at"]),
        recurrence:       params["recurrence"] || "none",
        color:            params["color"] || "#2DD4A0",
        price_cents:      price_cents,
        stage_channel_id: params["stage_channel_id"]
      }
      case Events.create_event(attrs) do
        {:ok, event} ->
          # Notify channel subscribers
          Phoenix.PubSub.broadcast(Koda.PubSub, "channel:#{channel_id}",
            {:new_event, Events.event_json(event)})
          conn |> put_status(201) |> json(%{event: Events.event_json(event)})
        {:error, cs} ->
          conn |> put_status(422) |> json(%{errors: format_errors(cs)})
      end
    end
  end

  def update(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)
    case Events.get_event(id) do
      nil -> conn |> put_status(404) |> json(%{error: "Not found"})
      event ->
        new_price = if Map.has_key?(params, "price_cents"), do: params["price_cents"], else: event.price_cents
        cond do
          not can_manage_event?(event, user.id) ->
            conn |> put_status(403) |> json(%{error: "Not authorized to edit this event"})
          new_price > 0 and not can_manage_marketplace?(event.server_id, user.id) ->
            conn |> put_status(403) |> json(%{error: "Not authorized to sell tickets for this server"})
          true ->
            # Map.update/4 inserts its default when the key is absent
            # rather than leaving it untouched -- using it unconditionally
            # here (as this previously did) meant *any* partial update
            # that didn't resend start_at/end_at would force those to nil
            # and fail validate_required(:start_at), rejecting otherwise
            # valid requests (e.g. an update that only changes price_cents
            # or color). Only transform the date fields when the caller
            # actually sent them.
            attrs = Map.take(params, ["title","description","location","start_at","end_at",
                                      "recurrence","color","price_cents","stage_channel_id"])
                    |> Map.new(fn {k,v} -> {String.to_atom(k), v} end)
            attrs = if Map.has_key?(attrs, :start_at),
              do: Map.update!(attrs, :start_at, &parse_dt/1), else: attrs
            attrs = if Map.has_key?(attrs, :end_at),
              do: Map.update!(attrs, :end_at, &parse_dt/1), else: attrs
            case Events.update_event(event, attrs) do
              {:ok, e}  -> json(conn, %{event: Events.event_json(e)})
              {:error, cs} -> conn |> put_status(422) |> json(%{errors: format_errors(cs)})
            end
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)
    case Events.get_event(id) do
      nil -> conn |> put_status(404) |> json(%{error: "Not found"})
      event ->
        if can_manage_event?(event, user.id) do
          Events.delete_event(event)
          json(conn, %{ok: true})
        else
          conn |> put_status(403) |> json(%{error: "Not authorized to delete this event"})
        end
    end
  end

  def purchase_ticket(conn, %{"event_id" => event_id}) do
    user = Guardian.Plug.current_resource(conn)
    case Events.create_ticket_intent(event_id, user.id) do
      {:ok, %{free: true} = result} ->
        json(conn, %{free: true, ticket_id: result.ticket.id})
      {:ok, %{client_secret: secret}} ->
        json(conn, %{free: false, client_secret: secret})
      {:error, :event_not_found} ->
        conn |> put_status(404) |> json(%{error: "Event not found"})
      {:error, :already_has_ticket} ->
        conn |> put_status(422) |> json(%{error: "You already have a ticket"})
      {:error, err} ->
        conn |> put_status(422) |> json(%{error: inspect(err)})
    end
  end

  def subscribe(conn, %{"event_id" => event_id}) do
    user = Guardian.Plug.current_resource(conn)
    Events.subscribe(event_id, user.id)
    json(conn, %{ok: true, subscribed: true})
  end

  def unsubscribe(conn, %{"event_id" => event_id}) do
    user = Guardian.Plug.current_resource(conn)
    Events.unsubscribe(event_id, user.id)
    json(conn, %{ok: true, subscribed: false})
  end

  defp parse_dt(nil), do: nil
  defp parse_dt(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp format_errors(cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, _} -> msg end)
  end
end
