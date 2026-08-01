defmodule Koda.Repo.Migrations.AddUpdatedAtToInvites do
  use Ecto.Migration

  def change do
    alter table(:invites) do
      add_if_not_exists :updated_at, :utc_datetime
    end
  end
end
