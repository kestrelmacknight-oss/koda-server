defmodule Koda.Repo.Migrations.AddRulesSystem do
  use Ecto.Migration

  def change do
    # Track whether member has accepted server rules
    alter table(:members) do
      add_if_not_exists :rules_accepted, :boolean, default: false
    end

    # Rules content stored on the channel itself
    alter table(:channels) do
      add_if_not_exists :rules_content, :text
      add_if_not_exists :self_assignable, :boolean, default: false
    end
  end
end
