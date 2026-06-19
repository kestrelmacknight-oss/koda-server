defmodule Koda.Repo.Migrations.AddCategoryIdToChannels do
  use Ecto.Migration

  def change do
    alter table(:channels) do
      add :category_id, references(:categories, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:channels, [:category_id])
  end
end
