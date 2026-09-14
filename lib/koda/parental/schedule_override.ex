defmodule Koda.Parental.ScheduleOverride do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "schedule_overrides" do
    field :expires_at, :utc_datetime_usec
    field :reason,     :string
    belongs_to :child,      Koda.Auth.User
    belongs_to :granted_by, Koda.Auth.User
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(override, attrs) do
    override
    |> cast(attrs, [:child_id, :granted_by_id, :expires_at, :reason])
    |> validate_required([:child_id, :granted_by_id, :expires_at])
    |> validate_length(:reason, max: 200)
  end
end
