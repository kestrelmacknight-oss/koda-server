defmodule Koda.Parental.ScheduleSweeper do
  @moduledoc """
  Runs every minute (see config :koda, Oban's Cron plugin). A child's JWT
  and any already-open socket stay valid past the moment their allowed
  window closes -- ScheduleGate stops new REST calls immediately, but a
  live Phoenix socket has no per-message re-auth, so this is what
  actually disconnects an open session the moment the window ends (or an
  override expires). Broadcasting to a user's socket id is a harmless
  no-op if they aren't currently connected.
  """
  use Oban.Worker, queue: :default

  import Ecto.Query
  alias Koda.{Repo, Parental}
  alias Koda.Auth.User

  @impl Oban.Worker
  def perform(_job) do
    from(u in User, where: u.account_type == "child")
    |> Repo.all()
    |> Enum.each(fn child ->
      unless Parental.allowed_now?(child) do
        KodaWeb.Endpoint.broadcast("user_socket:#{child.id}", "disconnect", %{})
      end
    end)

    :ok
  end
end
