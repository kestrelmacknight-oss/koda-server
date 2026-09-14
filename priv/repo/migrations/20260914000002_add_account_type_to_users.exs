defmodule Koda.Repo.Migrations.AddAccountTypeToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # "standard" | "child". Only Koda.Parental.create_child_account/2
      # ever sets "child" -- the public registration changeset never
      # casts this field, so nobody can self-register a child account.
      add_if_not_exists :account_type, :string, default: "standard", null: false
    end
  end
end
