defmodule Koda.Repo.Migrations.AddModerationTier1 do
  use Ecto.Migration

  def change do
    alter table(:server_members) do
      add_if_not_exists :muted_until, :utc_datetime_usec
    end

    alter table(:servers) do
      # Set automatically when raid detection fires (a burst of joins in
      # a short window); cleared only by a human owner/admin once they've
      # confirmed it's safe -- see Koda.Moderation.RateLimiter.
      add_if_not_exists :invites_locked, :boolean, default: false
    end

    # Everything Tier 1 (metadata-only) moderation does -- kicks, bans,
    # mutes, and automated rate-limit/flood/raid responses -- writes one
    # row here. Never touches message content, only who/what/when: the
    # whole point of a zero-knowledge-safe audit trail.
    create table(:moderation_actions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :server_id, references(:servers, type: :binary_id, on_delete: :delete_all), null: false
      # nil actor_id means the system itself took this action (e.g. an
      # automated flood-triggered mute), not a human moderator.
      add :actor_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :target_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :action, :string, null: false
      add :reason, :string
      add :metadata, :map, default: %{}
      add :inserted_at, :utc_datetime_usec, null: false
    end
    create index(:moderation_actions, [:server_id, :inserted_at])
    create index(:moderation_actions, [:target_user_id])
  end
end
