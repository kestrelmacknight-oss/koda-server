defmodule Koda.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id,                   :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :username,             :string,    null: false
      add :email,                :string,    null: false
      add :hashed_password,      :string,    null: false
      add :display_name,         :string
      add :avatar_url,           :string
      add :bio,                  :text
      add :status,               :string,    default: "offline"
      add :totp_secret,          :string
      add :totp_enabled,         :boolean,   default: false
      add :is_admin,             :boolean,   default: false, null: false
      add :must_change_password, :boolean,   default: false, null: false
      add :email_verified,       :boolean,   default: false, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:username])
    create unique_index(:users, [:email])
    create index(:users, [:is_admin])
  end
end
