defmodule KodaWeb.GalleryController do
  use KodaWeb, :controller
  alias Koda.{Gallery, Servers}

  # -- Collections -------------------------------------------------------------

  def list_collections(conn, %{"channel_id" => channel_id}) do
    user    = Guardian.Plug.current_resource(conn)
    channel = Servers.get_channel(channel_id)
    if channel && Servers.get_member(channel.server_id, user.id) do
      collections = Gallery.list_collections(channel_id)
      json(conn, %{collections: Enum.map(collections, &Gallery.collection_json/1)})
    else
      conn |> put_status(403) |> json(%{error: "Not authorized"})
    end
  end

  def create_collection(conn, %{"channel_id" => channel_id} = params) do
    user    = Guardian.Plug.current_resource(conn)
    channel = Servers.get_channel(channel_id)
    if channel && (Servers.owner?(channel.server_id, user.id) or
                   Servers.member_can?(channel.server_id, user.id, "manage_channels")) do
      attrs = Map.take(params, ["name", "description", "cover_url", "position"])
      case Gallery.create_collection(channel_id, user.id, attrs) do
        {:ok, c}    ->
          c = Koda.Repo.preload(c, :creator)
          conn |> put_status(201) |> json(%{collection: Gallery.collection_json(c)})
        {:error, cs} ->
          conn |> put_status(422) |> json(%{errors: format_errors(cs)})
      end
    else
      conn |> put_status(403) |> json(%{error: "Only admins can create collections"})
    end
  end

  def update_collection(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)
    case Gallery.get_collection(id) do
      nil -> conn |> put_status(404) |> json(%{error: "Not found"})
      c   ->
        channel = Servers.get_channel(c.channel_id)
        if channel && (Servers.owner?(channel.server_id, user.id) or
                       Servers.member_can?(channel.server_id, user.id, "manage_channels")) do
          attrs = Map.take(params, ["name", "description", "cover_url", "position"])
          case Gallery.update_collection(c, attrs) do
            {:ok, updated} ->
              updated = Koda.Repo.preload(updated, :creator)
              json(conn, %{collection: Gallery.collection_json(updated)})
            {:error, cs} ->
              conn |> put_status(422) |> json(%{errors: format_errors(cs)})
          end
        else
          conn |> put_status(403) |> json(%{error: "Not authorized"})
        end
    end
  end

  def delete_collection(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)
    case Gallery.get_collection(id) do
      nil -> conn |> put_status(404) |> json(%{error: "Not found"})
      c   ->
        channel = Servers.get_channel(c.channel_id)
        if channel && (Servers.owner?(channel.server_id, user.id) or
                       Servers.member_can?(channel.server_id, user.id, "manage_channels")) do
          Gallery.delete_collection(c)
          json(conn, %{ok: true})
        else
          conn |> put_status(403) |> json(%{error: "Not authorized"})
        end
    end
  end

  # -- Posts -------------------------------------------------------------------

  def list_posts(conn, %{"channel_id" => channel_id} = params) do
    user    = Guardian.Plug.current_resource(conn)
    channel = Servers.get_channel(channel_id)
    if channel && Servers.get_member(channel.server_id, user.id) do
      opts = []
      opts = if params["before"], do: [{:before, params["before"]} | opts], else: opts
      posts = Gallery.list_posts(channel_id, opts)
      json(conn, %{posts: Enum.map(posts, &Gallery.post_json/1)})
    else
      conn |> put_status(403) |> json(%{error: "Not authorized"})
    end
  end

  def list_collection_posts(conn, %{"collection_id" => collection_id}) do
    user = Guardian.Plug.current_resource(conn)
    case Gallery.get_collection(collection_id) do
      nil -> conn |> put_status(404) |> json(%{error: "Not found"})
      c   ->
        channel = Servers.get_channel(c.channel_id)
        if channel && Servers.get_member(channel.server_id, user.id) do
          posts = Gallery.list_collection_posts(collection_id)
          json(conn, %{posts: Enum.map(posts, &Gallery.post_json/1)})
        else
          conn |> put_status(403) |> json(%{error: "Not authorized"})
        end
    end
  end

  def create_post(conn, %{"channel_id" => channel_id} = params) do
    user    = Guardian.Plug.current_resource(conn)
    channel = Servers.get_channel(channel_id)
    if channel && (Servers.owner?(channel.server_id, user.id) or
                   Servers.member_can?(channel.server_id, user.id, "post_media")) do
      attrs = Map.take(params, ["caption", "media", "collection_id"])
      case Gallery.create_post(channel_id, user.id, attrs) do
        {:ok, p}    ->
          p = Koda.Repo.preload(p, [:creator, :collection])
          conn |> put_status(201) |> json(%{post: Gallery.post_json(p)})
        {:error, cs} ->
          conn |> put_status(422) |> json(%{errors: format_errors(cs)})
      end
    else
      conn |> put_status(403) |> json(%{error: "Not authorized to post media"})
    end
  end

  def delete_post(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)
    case Gallery.get_post(id) do
      nil -> conn |> put_status(404) |> json(%{error: "Not found"})
      p   ->
        channel = Servers.get_channel(p.channel_id)
        can_delete = p.creator_id == user.id ||
                     (channel && (Servers.owner?(channel.server_id, user.id) or
                                  Servers.member_can?(channel.server_id, user.id, "manage_messages")))
        if can_delete do
          Gallery.delete_post(p)
          json(conn, %{ok: true})
        else
          conn |> put_status(403) |> json(%{error: "Not authorized"})
        end
    end
  end

  defp format_errors(cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, k ->
        opts |> Keyword.get(String.to_existing_atom(k), k) |> to_string()
      end)
    end)
  end
end