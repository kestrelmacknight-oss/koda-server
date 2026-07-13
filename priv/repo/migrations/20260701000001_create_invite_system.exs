defmodule Koda.Repo.Migrations.CreateInviteSystem do
  use Ecto.Migration

  def change do
    # User account flags -- flexible JSONB map for backer rewards,
    # early access, feature unlocks, etc. Keys are defined by admins.
    # Example: %{"backer_tier" => "founding", "early_access" => true}
    alter table(:users) do
      add :flags, :map, default: %{}
    end

    # Server invite codes -- short random codes that let anyone join
    # a specific server. Optional expiry and use limit.
    create table(:invites, primary_key: false) do
      add :id,         :binary_id, primary_key: true
      add :code,       :string,    null: false
      add :server_id,  references(:servers, type: :binary_id, on_delete: :delete_all), null: false
      add :creator_id, references(:users,   type: :binary_id), null: false
      add :uses,       :integer, default: 0, null: false
      add :max_uses,   :integer             # null = unlimited
      add :expires_at, :utc_datetime        # null = never expires
      timestamps(type: :utc_datetime)
    end

    create unique_index(:invites, [:code])
    create index(:invites, [:server_id])

    # Backer/redemption codes -- admin-generated codes that apply
    # account flags when redeemed. One use per code per user.
    create table(:backer_codes, primary_key: false) do
      add :id,          :binary_id, primary_key: true
      add :code,        :string, null: false
      add :flags,       :map, default: %{}, null: false  # flags to apply on redemption
      add :note,        :string          # admin memo (e.g. "Kickstarter Tier 2")
      add :max_uses,    :integer         # null = unlimited
      add :uses,        :integer, default: 0, null: false
      add :expires_at,  :utc_datetime    # null = never expires
      add :created_by,  references(:users, type: :binary_id)
      timestamps(type: :utc_datetime)
    end

    create unique_index(:backer_codes, [:code])

    # Track which users have redeemed which backer codes
    create table(:backer_code_redemptions, primary_key: false) do
      add :id,      :binary_id, primary_key: true
      add :code_id, references(:backer_codes, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :redeemed_at, :utc_datetime, null: false
    end

    create unique_index(:backer_code_redemptions, [:code_id, :user_id])
    create index(:backer_code_redemptions, [:user_id])
  end
end