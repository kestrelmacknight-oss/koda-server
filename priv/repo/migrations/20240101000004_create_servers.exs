defmodule Koda.Repo.Migrations.CreateServers do
  use Ecto.Migration

  def change do
    create table(:servers, primary_key: false) do
      add :id,           :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :name,         :string,    null: false
      add :description,  :text
      add :icon_url,     :string
      add :banner_url,   :string
      add :owner_id,     references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :is_public,    :boolean,   default: false
      add :category,     :string
      add :member_count, :integer,   default: 1
      timestamps(type: :utc_datetime)
    end

    create index(:servers, [:owner_id])
    create index(:servers, [:is_public])
  end
end
