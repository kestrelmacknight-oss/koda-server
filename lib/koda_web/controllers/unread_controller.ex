defmodule KodaWeb.UnreadController do
  use KodaWeb, :controller
  alias Koda.{Servers, DirectMessages, ReadStates}

  @doc """
  One bulk fetch of unread counts for everything the sidebar shows --
  every text channel across the user's servers, and every DM conversation.
  """
  def index(conn, _params) do
    user = Guardian.Plug.current_resource(conn)

    channel_ids =
      user.id
      |> Servers.list_user_servers()
      |> Enum.flat_map(&Servers.list_channels(&1.id))
      |> Enum.map(& &1.id)

    conversation_ids =
      user.id
      |> DirectMessages.list_conversations()
      |> Enum.map(& &1.id)

    json(conn, %{
      channels: ReadStates.unread_counts_for_channels(user.id, channel_ids),
      dms:      ReadStates.unread_counts_for_conversations(user.id, conversation_ids)
    })
  end
end
