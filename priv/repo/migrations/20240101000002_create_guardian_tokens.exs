defmodule Koda.Repo.Migrations.CreateGuardianTokens do
  use Ecto.Migration

  def change do
    create table(:guardian_tokens, primary_key: false) do
      add :jti,     :string,    primary_key: true
      add :aud,     :string,    null: false
      add :typ,     :string
      add :iss,     :string
      add :sub,     :string
      add :exp,     :bigint
      add :jwt,     :text
      add :claims,  :map
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:guardian_tokens, [:jti])
    create index(:guardian_tokens, [:sub])
  end
end
