defmodule Koda.Repo.Migrations.CreatePrintfulConnections do
  use Ecto.Migration

  def change do
    create table(:printful_connections, primary_key: false) do
      add :id,                  :binary_id, primary_key: true
      add :server_id,           references(:servers, type: :binary_id, on_delete: :delete_all), null: false
      add :connected_by_id,     references(:users, type: :binary_id, on_delete: :nilify_all)
      add :access_token,        :string, null: false
      add :refresh_token,       :string
      add :token_expires_at,    :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    # One Printful store connected per server.
    create unique_index(:printful_connections, [:server_id])
  end
end
