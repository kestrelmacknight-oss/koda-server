defmodule Koda.Repo.Migrations.AddSelfAssignableToRoles do
  use Ecto.Migration

  def change do
    alter table(:roles) do
      add_if_not_exists :self_assignable, :boolean, default: false
    end

    alter table(:channels) do
      add_if_not_exists :rules_content, :text
    end

    alter table(:server_members) do
      add_if_not_exists :rules_accepted, :boolean, default: false
    end
  end
end
