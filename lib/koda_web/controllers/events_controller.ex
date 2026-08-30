defmodule KodaWeb.EventsController do
  use KodaWeb, :controller
  alias Koda.Events

  def index(conn, %{"channel_id" => channel_id}) do
    events = Events.list_events(channel_id)
    user = Guardian.Plug.current_resource(conn)
    events_with_sub = Enum.map(events, fn e ->
      Map.put(e, :subscribed, Events.subscribed?(e.id, user.id))
    end)
    json(conn, %{events: events_with_sub})
  end

  def create(conn, %{"channel_id" => channel_id} = params) do
    user = Guardian.Plug.current_resource(conn)
    channel = Koda.Servers.get_channel(channel_id)
    attrs = %{
      channel_id:  channel_id,
      server_id:   channel.server_id,
      created_by:  user.id,
      title:       params["title"],
      description: params["description"],
      location:    params["location"],
      start_at:    parse_dt(params["start_at"]),
      end_at:      parse_dt(params["end_at"]),
      recurrence:  params["recurrence"] || "none",
      color:       params["color"] || "#2DD4A0"
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

  def update(conn, %{"id" => id} = params) do
    case Events.get_event(id) do
      nil -> conn |> put_status(404) |> json(%{error: "Not found"})
      event ->
        attrs = Map.take(params, ["title","description","location",
                                  "start_at","end_at","recurrence","color"])
                |> Map.new(fn {k,v} -> {String.to_atom(k), v} end)
                |> Map.update(:start_at, nil, &parse_dt/1)
                |> Map.update(:end_at, nil, &parse_dt/1)
        case Events.update_event(event, attrs) do
          {:ok, e}  -> json(conn, %{event: Events.event_json(e)})
          {:error, cs} -> conn |> put_status(422) |> json(%{errors: format_errors(cs)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    case Events.get_event(id) do
      nil -> conn |> put_status(404) |> json(%{error: "Not found"})
      event ->
        Events.delete_event(event)
        json(conn, %{ok: true})
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
