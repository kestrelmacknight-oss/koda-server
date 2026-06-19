defmodule Koda.Repo.Migrations.CreateChannels do
  use Ecto.Migration

  def change do
    create table(:channels, primary_key: false) do
      add :id,                  :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :server_id,           references(:servers, type: :binary_id, on_delete: :delete_all), null: false
      add :name,                :string,  null: false
      add :type,                :string,  default: "text"    # text | voice
      add :description,         :text
      add :position,            :integer, default: 0
      add :is_subscriber_only,  :boolean, default: false
      add :is_read_only,        :boolean, default: false
      timestamps(type: :utc_datetime)
    end

    create index(:channels, [:server_id])
    create index(:channels, [:server_id, :position])
  end
end
