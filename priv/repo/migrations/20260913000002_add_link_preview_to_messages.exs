defmodule Koda.Repo.Migrations.AddLinkPreviewToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add_if_not_exists :link_preview, :map
    end
  end
end
