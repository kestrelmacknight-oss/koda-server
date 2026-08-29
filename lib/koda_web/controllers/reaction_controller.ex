defmodule KodaWeb.ReactionController do
  use KodaWeb, :controller
  alias Koda.Chat

  def add(conn, %{"message_id" => message_id, "emoji" => emoji}) do
    user = Guardian.Plug.current_resource(conn)
    Chat.add_reaction(message_id, emoji, user.id)
    reactions = Chat.get_reactions(message_id)
    # Broadcast to channel
    channel_id = get_channel_id(message_id)
    if channel_id do
      Phoenix.PubSub.broadcast(Koda.PubSub, "channel:#{channel_id}",
        {:reaction_update, %{message_id: message_id, reactions: reactions}})
    end
    json(conn, %{ok: true, reactions: reactions})
  end

  def remove(conn, %{"message_id" => message_id, "emoji" => emoji}) do
    user = Guardian.Plug.current_resource(conn)
    Chat.remove_reaction(message_id, emoji, user.id)
    reactions = Chat.get_reactions(message_id)
    channel_id = get_channel_id(message_id)
    if channel_id do
      Phoenix.PubSub.broadcast(Koda.PubSub, "channel:#{channel_id}",
        {:reaction_update, %{message_id: message_id, reactions: reactions}})
    end
    json(conn, %{ok: true, reactions: reactions})
  end

  defp get_channel_id(message_id) do
    import Ecto.Query
    case Koda.Repo.one(from m in Koda.Chat.Message, where: m.id == ^message_id, select: m.channel_id) do
      nil -> nil
      id  -> id
    end
  end
end
