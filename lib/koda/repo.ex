defmodule Koda.Repo do
  use Ecto.Repo,
    otp_app: :koda,
    adapter: Ecto.Adapters.Postgres
end
