defmodule Koda.Gallery do
  @moduledoc "Gallery collections and posts for gallery-type channels."
  import Ecto.Query
  alias Koda.Repo

  # -- Schemas -----------------------------------------------------------------

  defmodule Collection do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "gallery_collections" do
      field :name,        :string
      field :description, :string
      field :cover_url,   :string
      field :position,    :integer, default: 0
      belongs_to :channel, Koda.Servers.Channel
      belongs_to :creator, Koda.Auth.User
      has_many :posts, Koda.Gallery.Post, foreign_key: :collection_id
      timestamps(type: :utc_datetime)
    end

    def changeset(c, attrs) do
      c
      |> cast(attrs, [:name, :description, :cover_url, :position, :channel_id, :creator_id])
      |> validate_required([:name, :channel_id, :creator_id])
      |> validate_length(:name, min: 1, max: 100)
    end
  end

  defmodule Post do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "gallery_posts" do
      field :caption,       :string
      # Array of maps: [{url, type, width, height, alt}]
      # type is "image" | "video"; width/height/alt are optional.
      field :media,         {:array, :map}, default: []
      belongs_to :channel,    Koda.Servers.Channel
      belongs_to :collection, Koda.Gallery.Collection
      belongs_to :creator,    Koda.Auth.User
      timestamps(type: :utc_datetime)
    end

    def changeset(p, attrs) do
      p
      |> cast(attrs, [:caption, :media, :channel_id, :collection_id, :creator_id])
      |> validate_required([:channel_id, :creator_id, :media])
      |> validate_length(:media, min: 1, max: 10,
           message: "must include at least one media item (max 10)")
    end
  end

  # -- Collections -------------------------------------------------------------

  def list_collections(channel_id) do
    Repo.all(
      from c in Collection,
      where: c.channel_id == ^channel_id,
      order_by: [asc: c.position, asc: c.inserted_at],
      preload: [:creator]
    )
  end

  def get_collection(id), do: Repo.get(Collection, id)

  def create_collection(channel_id, creator_id, attrs) do
    %Collection{}
    |> Collection.changeset(Map.merge(attrs, %{
        "channel_id" => channel_id,
        "creator_id" => creator_id
      }))
    |> Repo.insert()
  end

  def update_collection(collection, attrs) do
    collection |> Collection.changeset(attrs) |> Repo.update()
  end

  def delete_collection(collection) do
    Repo.delete(collection)
  end

  # -- Posts -------------------------------------------------------------------

  # Feed view: all posts in a channel, newest first, page of 24.
  def list_posts(channel_id, opts \\ []) do
    limit  = Keyword.get(opts, :limit, 24)
    before = Keyword.get(opts, :before)

    query =
      from p in Post,
      where: p.channel_id == ^channel_id,
      order_by: [desc: p.inserted_at],
      limit: ^limit,
      preload: [:creator, :collection]

    query =
      if before do
        from p in query, where: p.inserted_at < ^before
      else
        query
      end

    Repo.all(query)
  end

  # Collection view: posts in a specific collection.
  def list_collection_posts(collection_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 24)

    Repo.all(
      from p in Post,
      where: p.collection_id == ^collection_id,
      order_by: [desc: p.inserted_at],
      limit: ^limit,
      preload: [:creator]
    )
  end

  def get_post(id), do: Repo.get(Post, id)

  def create_post(channel_id, creator_id, attrs) do
    %Post{}
    |> Post.changeset(Map.merge(attrs, %{
        "channel_id" => channel_id,
        "creator_id" => creator_id
      }))
    |> Repo.insert()
  end

  def delete_post(post) do
    Repo.delete(post)
  end

  # -- Serialization -----------------------------------------------------------

  def collection_json(c) do
    %{
      id:          c.id,
      name:        c.name,
      description: c.description,
      cover_url:   c.cover_url,
      position:    c.position,
      creator:     %{id: c.creator.id, username: c.creator.username},
      inserted_at: c.inserted_at
    }
  end

  def post_json(p) do
    %{
      id:            p.id,
      caption:       p.caption,
      media:         p.media,
      channel_id:    p.channel_id,
      collection_id: p.collection_id,
      creator:       %{id: p.creator.id, username: p.creator.username},
      inserted_at:   p.inserted_at
    }
  end
end