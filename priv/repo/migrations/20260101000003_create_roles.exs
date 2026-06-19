defmodule Koda.Repo.Migrations.CreateRoles do
  use Ecto.Migration

  def change do
    create table(:roles, primary_key: false) do
      add :id,          :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :server_id,   references(:servers, type: :binary_id, on_delete: :delete_all), null: false
      add :name,        :string,  null: false
      add :color,       :string,  default: "#9BA5C8"   # hex color, shown in member list / mentions
      add :position,    :integer, default: 0            # higher position = higher in hierarchy
      add :is_default,  :boolean, default: false         # the auto-created "@everyone" equivalent
      # Fixed set of named permissions stored as a boolean map.
      # Keeping this as a flat map (rather than a bitfield) trades a
      # little storage efficiency for being trivial to read, query,
      # and extend without touching old data.
      add :permissions, :map, default: %{}
      timestamps(type: :utc_datetime)
    end

    create index(:roles, [:server_id])
    create index(:roles, [:server_id, :position])
    create unique_index(:roles, [:server_id, :is_default],
      where: "is_default = true",
      name: :roles_one_default_per_server)
  end
end
