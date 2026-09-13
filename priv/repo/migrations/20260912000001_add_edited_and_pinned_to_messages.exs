defmodule Koda.Repo.Migrations.AddEditedAndPinnedToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add_if_not_exists :edited_at, :utc_datetime_usec
      add_if_not_exists :pinned_at, :utc_datetime_usec
    end
  end
end
