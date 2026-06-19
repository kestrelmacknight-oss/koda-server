defmodule Koda.Repo.Migrations.CreateVerificationCodes do
  use Ecto.Migration

  def change do
    create table(:verification_codes, primary_key: false) do
      add :id,         :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id,    references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :code,       :string,  null: false
      add :type,       :string,  null: false   # email_verification | password_reset
      add :used,       :boolean, default: false
      add :expires_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:verification_codes, [:user_id, :type])
    create index(:verification_codes, [:code])
  end
end
