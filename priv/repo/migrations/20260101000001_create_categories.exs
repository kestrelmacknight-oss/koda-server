defmodule Koda.Repo.Migrations.CreateCategories do
  use Ecto.Migration

  def change do
    create table(:categories, primary_key: false) do
      add :id,        :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :server_id, references(:servers, type: :binary_id, on_delete: :delete_all), null: false
      add :name,       :string,  null: false
      add :position,   :integer, default: 0
      timestamps(type: :utc_datetime)
    end

    create index(:categories, [:server_id])
    create index(:categories, [:server_id, :position])
  end
end
