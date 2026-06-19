defmodule KodaWeb.UserSocket do
  use Phoenix.Socket

  channel "channel:*",  KodaWeb.RoomChannel
  channel "dm:*",       KodaWeb.RoomChannel
  channel "user:*",     KodaWeb.RoomChannel

  @impl true
  def connect(%{"token" => token}, socket, _info) do
    case Guardian.Phoenix.Socket.authenticate(socket, Koda.Auth.Guardian, token) do
      {:ok, authed_socket} -> {:ok, authed_socket}
      {:error, _}          -> :error
    end
  end

  def connect(_, _, _), do: :error

  @impl true
  def id(socket) do
    "user_socket:#{Guardian.Phoenix.Socket.current_resource(socket).id}"
  end
end
