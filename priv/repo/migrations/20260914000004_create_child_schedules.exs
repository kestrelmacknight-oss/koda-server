defmodule Koda.Repo.Migrations.CreateChildSchedules do
  use Ecto.Migration

  def change do
    create table(:child_schedules, primary_key: false) do
      add :id,       :binary_id, primary_key: true
      add :child_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :timezone, :string, null: false, default: "UTC"
      # Per-weekday allowed windows, minutes-since-midnight in `timezone`:
      # %{"mon" => [[480, 1260]], "tue" => [...], ...}. A window with
      # end < start wraps past midnight (see Koda.Parental.within_window?/2).
      # No row for a child == unrestricted.
      add :windows,  :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:child_schedules, [:child_id])
  end
end
