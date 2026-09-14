defmodule Koda.Parental.ParentalLink do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "parental_links" do
    belongs_to :parent, Koda.Auth.User
    belongs_to :child,  Koda.Auth.User
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(link, attrs) do
    link
    |> cast(attrs, [:parent_id, :child_id])
    |> validate_required([:parent_id, :child_id])
    |> unique_constraint(:child_id)
  end
end
