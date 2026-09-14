defmodule Koda.Parental.ChildSchedule do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_weekdays ~w(mon tue wed thu fri sat sun)

  schema "child_schedules" do
    field :timezone, :string, default: "UTC"
    field :windows,  :map, default: %{}
    belongs_to :child, Koda.Auth.User
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(schedule, attrs) do
    schedule
    |> cast(attrs, [:child_id, :timezone, :windows])
    |> validate_required([:child_id, :timezone, :windows])
    |> validate_timezone()
    |> validate_windows()
  end

  defp validate_timezone(changeset) do
    validate_change(changeset, :timezone, fn :timezone, tz ->
      if Tzdata.zone_exists?(tz), do: [], else: [timezone: "is not a recognized timezone"]
    end)
  end

  defp validate_windows(changeset) do
    validate_change(changeset, :windows, fn :windows, windows ->
      if windows |> Map.keys() |> Enum.all?(&(&1 in @valid_weekdays)) &&
           windows |> Map.values() |> Enum.all?(&valid_window_list?/1) do
        []
      else
        [windows: "must map weekday keys (mon..sun) to lists of [start_minute, end_minute] pairs"]
      end
    end)
  end

  defp valid_window_list?(list) when is_list(list), do: Enum.all?(list, &valid_window?/1)
  defp valid_window_list?(_), do: false

  defp valid_window?([start_min, end_min])
       when is_integer(start_min) and is_integer(end_min) and
            start_min >= 0 and start_min < 1440 and
            end_min >= 0 and end_min < 1440,
       do: true

  defp valid_window?(_), do: false
end
