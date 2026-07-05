defmodule Koda.Repo.Migrations.CreateGallery do
  use Ecto.Migration

  def change do
    create table(:gallery_collections, primary_key: false) do
      add :id,          :binary_id, primary_key: true
      add :channel_id,  references(:channels, type: :binary_id, on_delete: :delete_all), null: false
      add :name,        :string, null: false
      add :description, :string
      add :cover_url,   :string
      add :position,    :integer, default: 0, null: false
      add :creator_id,  references(:users, type: :binary_id), null: false
      timestamps(type: :utc_datetime)
    end

    create index(:gallery_collections, [:channel_id])
    create index(:gallery_collections, [:channel_id, :position])

    create table(:gallery_posts, primary_key: false) do
      add :id,            :binary_id, primary_key: true
      add :channel_id,    references(:channels, type: :binary_id, on_delete: :delete_all), null: false
      # collection_id is nullable -- posts can exist directly in a channel
      # without belonging to any collection (shown in the feed view).
      add :collection_id, references(:gallery_collections, type: :binary_id, on_delete: :nilify_all)
      add :creator_id,    references(:users, type: :binary_id), null: false
      add :caption,       :text
      # media stored as a JSONB array of {url, type, width, height, alt} maps.
      # type is "image" or "video". width/height/alt are optional metadata.
      # No separate media table -- a post typically has 1-4 images and
      # keeping them inline avoids a join on every gallery page load.
      add :media,         {:array, :map}, default: [], null: false
      timestamps(type: :utc_datetime)
    end

    create index(:gallery_posts, [:channel_id])
    create index(:gallery_posts, [:collection_id])
    create index(:gallery_posts, [:channel_id, :inserted_at])
  end
end