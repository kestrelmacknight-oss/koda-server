defmodule Koda.Repo.Migrations.CreateParentalLinks do
  use Ecto.Migration

  def change do
    create table(:parental_links, primary_key: false) do
      add :id,        :binary_id, primary_key: true
      add :parent_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :child_id,  references(:users, type: :binary_id, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime_usec)
    end

    # Exactly one parent per child; a parent may have many children.
    create unique_index(:parental_links, [:child_id])
    create index(:parental_links, [:parent_id])
  end
end
