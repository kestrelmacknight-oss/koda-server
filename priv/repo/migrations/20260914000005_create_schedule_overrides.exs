defmodule Koda.Repo.Migrations.CreateScheduleOverrides do
  use Ecto.Migration

  def change do
    create table(:schedule_overrides, primary_key: false) do
      add :id,         :binary_id, primary_key: true
      add :child_id,   references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :granted_by, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :expires_at, :utc_datetime_usec, null: false
      add :reason,     :string
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # The hot query for every schedule check and the Oban sweep.
    create index(:schedule_overrides, [:child_id, :expires_at])
  end
end
