defmodule KodaWeb.UserSocket do
  use Phoenix.Socket
  channel "channel:*",  KodaWeb.RoomChannel
  channel "dm:*",       KodaWeb.RoomChannel
  channel "user:*",     KodaWeb.RoomChannel

  @impl true
  def connect(%{"token" => token}, socket, _info) do
    case Koda.Auth.Guardian.decode_and_verify(token) do
      {:ok, claims} ->
        case Koda.Auth.Guardian.resource_from_claims(claims) do
          {:ok, user} ->
            {:ok, Phoenix.Socket.assign(socket, :current_user, user)}
          {:error, _} -> :error
        end
      {:error, _} -> :error
    end
  end
  def connect(_, _, _), do: :error

  @impl true
  def id(socket) do
    user = socket.assigns[:current_user]
    if user, do: "user_socket:#{user.id}", else: nil
  end
end
