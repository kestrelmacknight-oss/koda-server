defmodule Koda.Servers do
  import Ecto.Query
  alias Koda.Repo
  alias Koda.Servers.{Server, Channel, Member, Category, Role, MemberRole}

  # Default permission set for the auto-created "@everyone"-equivalent
  # role every server gets on creation. Owners bypass all permission
  # checks entirely (see member_can?/3) -- this only governs what
  # everyone else can do by default.
  @default_role_permissions %{
    "view_channels"    => true,
    "send_messages"    => true,
    "connect_voice"    => true,
    "manage_server"    => false,
    "manage_channels"  => false,
    "manage_roles"     => false,
    "manage_messages"  => false,
    "kick_members"     => false,
    "ban_members"      => false,
    "mention_everyone" => false
  }

  # Full permission set for the auto-created "Admin" role, granted to
  # every server's creator automatically. Distinct from the implicit
  # owner?/2 bypass that already exists -- this makes admin status
  # visible and explicit in the member list (rather than invisible
  # ownership), and gives a ready-made role to hand to trusted
  # co-admins later without building a separate mechanism for it.
  @admin_role_permissions %{
    "view_channels"    => true,
    "send_messages"    => true,
    "connect_voice"    => true,
    "manage_server"    => true,
    "manage_channels"  => true,
    "manage_roles"     => true,
    "manage_messages"  => true,
    "kick_members"     => true,
    "ban_members"      => true,
    "mention_everyone" => true
  }

  # ── Servers ────────────────────────────────────────────────────────────────

  def list_user_servers(user_id) do
    Repo.all(
      from s in Server,
      join: m in Member, on: m.server_id == s.id and m.user_id == ^user_id,
      where: m.is_banned == false,
      order_by: [asc: s.name],
      preload: [:channels]
    )
  end

  def get_server(id), do: Repo.get(Server, id)

  def get_server_with_channels(id) do
    Repo.one(
      from s in Server,
      where: s.id == ^id,
      preload: [channels: ^from(c in Channel, order_by: c.position)]
    )
  end

  def create_server(owner_id, attrs) do
    Repo.transaction(fn ->
      server = %Server{}
      |> Server.changeset(Map.put(attrs, "owner_id", owner_id))
      |> Repo.insert!()

      # Auto-join the owner
      member = %Member{}
      |> Member.changeset(%{
        server_id: server.id,
        user_id:   owner_id,
        joined_at: DateTime.utc_now()
      })
      |> Repo.insert!()

      # Default role every server gets -- the "@everyone" equivalent.
      # Every member, including the owner, is assigned this role so
      # member listings always show at least one role per person.
      default_role = %Role{}
      |> Role.changeset(%{
        server_id:  server.id,
        name:       "Member",
        color:      "#9BA5C8",
        position:   0,
        is_default: true,
        permissions: @default_role_permissions
      })
      |> Repo.insert!()

      %MemberRole{}
      |> MemberRole.changeset(%{member_id: member.id, role_id: default_role.id})
      |> Repo.insert!()

      # Admin role, automatically granted to the creator so they can
      # manage roles/channels/members right away, with no manual
      # assignment needed after the fact.
      admin_role = %Role{}
      |> Role.changeset(%{
        server_id:  server.id,
        name:       "Admin",
        color:      "#FF6584",
        position:   1,
        is_default: false,
        permissions: @admin_role_permissions
      })
      |> Repo.insert!()

      %MemberRole{}
      |> MemberRole.changeset(%{member_id: member.id, role_id: admin_role.id})
      |> Repo.insert!()

      # Default channels
      %Channel{}
      |> Channel.changeset(%{
        server_id: server.id,
        name:      "general",
        type:      "text",
        position:  0
      })
      |> Repo.insert!()

      %Channel{}
      |> Channel.changeset(%{
        server_id: server.id,
        name:      "general-voice",
        type:      "voice",
        position:  1
      })
      |> Repo.insert!()

      server
    end)
  end

  def update_server(server, attrs) do
    server |> Server.changeset(attrs) |> Repo.update()
  end

  def delete_server(server) do
    Repo.delete(server)
  end

  # ── Members ────────────────────────────────────────────────────────────────

  def get_member(server_id, user_id) do
    Repo.get_by(Member, server_id: server_id, user_id: user_id)
  end

  def add_member(server_id, user_id) do
    Repo.transaction(fn ->
      member = %Member{}
      |> Member.changeset(%{
        server_id: server_id,
        user_id:   user_id,
        joined_at: DateTime.utc_now()
      })
      |> Repo.insert!()

      # New members get the server's default role automatically
      case get_default_role(server_id) do
        nil -> :ok
        role ->
          %MemberRole{}
          |> MemberRole.changeset(%{member_id: member.id, role_id: role.id})
          |> Repo.insert!()
      end

      Repo.update_all(
        from(s in Server, where: s.id == ^server_id),
        inc: [member_count: 1]
      )

      member
    end)
  end

  def remove_member(server_id, user_id) do
    case get_member(server_id, user_id) do
      nil    -> {:error, :not_found}
      member ->
        Repo.delete(member)
        Repo.update_all(
          from(s in Server, where: s.id == ^server_id),
          inc: [member_count: -1]
        )
        :ok
    end
  end

  def list_members(server_id) do
    Repo.all(
      from m in Member,
      where: m.server_id == ^server_id and m.is_banned == false,
      preload: [:user, :roles]
    )
  end

  def get_member_by_id(member_id), do: Repo.get(Member, member_id) |> Repo.preload(:roles)

  # ── Channels ───────────────────────────────────────────────────────────────

  def get_channel(id), do: Repo.get(Channel, id)

  def list_channels(server_id) do
    Repo.all(
      from c in Channel,
      where: c.server_id == ^server_id,
      order_by: [asc: c.position]
    )
  end

  def create_channel(server_id, attrs) do
    %Channel{}
    |> Channel.changeset(Map.put(attrs, "server_id", server_id))
    |> Repo.insert()
  end

  def update_channel(channel, attrs) do
    channel |> Channel.changeset(attrs) |> Repo.update()
  end

  def delete_channel(channel) do
    Repo.delete(channel)
  end

  # ── Categories ─────────────────────────────────────────────────────────────

  def list_categories(server_id) do
    Repo.all(
      from c in Category,
      where: c.server_id == ^server_id,
      order_by: [asc: c.position],
      preload: [channels: ^from(ch in Channel, order_by: ch.position)]
    )
  end

  def get_category(id), do: Repo.get(Category, id)

  def create_category(server_id, attrs) do
    %Category{}
    |> Category.changeset(Map.put(attrs, "server_id", server_id))
    |> Repo.insert()
  end

  def update_category(category, attrs) do
    category |> Category.changeset(attrs) |> Repo.update()
  end

  def delete_category(category) do
    Repo.delete(category)
  end

  # ── Roles ──────────────────────────────────────────────────────────────────

  def list_roles(server_id) do
    Repo.all(
      from r in Role,
      where: r.server_id == ^server_id,
      order_by: [desc: r.position]
    )
  end

  def get_role(id), do: Repo.get(Role, id)

  def get_default_role(server_id) do
    Repo.get_by(Role, server_id: server_id, is_default: true)
  end

  def create_role(server_id, attrs) do
    # is_default is set exclusively by create_server's internal logic --
    # never accepted from the public API, same protection update_role has.
    attrs = Map.drop(attrs, ["is_default", :is_default])
    %Role{}
    |> Role.changeset(Map.put(attrs, "server_id", server_id))
    |> Repo.insert()
  end

  def update_role(role, attrs) do
    # The default role's permissions can be edited, but it can never be
    # un-defaulted or deleted -- every server needs exactly one.
    attrs = Map.drop(attrs, ["is_default", :is_default])
    role |> Role.changeset(attrs) |> Repo.update()
  end

  def delete_role(%Role{is_default: true}), do: {:error, :cannot_delete_default_role}
  def delete_role(role), do: Repo.delete(role)

  def assign_role(member_id, role_id) do
    %MemberRole{}
    |> MemberRole.changeset(%{member_id: member_id, role_id: role_id})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:member_id, :role_id])
  end

  def remove_role(member_id, role_id) do
    Repo.delete_all(
      from mr in MemberRole,
      where: mr.member_id == ^member_id and mr.role_id == ^role_id
    )
    :ok
  end

  # ── Permission checks ─────────────────────────────────────────────────────

  @doc """
  The single source of truth for "can this user do X in this server."
  Server owners always return true, regardless of role -- this mirrors
  how Discord treats server ownership, and avoids the awkward edge case
  of an owner locking themselves out of their own server.

  For everyone else: true if ANY of the member's assigned roles grants
  the permission (additive across roles, same as Discord's server-wide
  permission model). Channel-level overrides are not part of this --
  that's a deliberately separate, not-yet-built layer.
  """
  def member_can?(server_id, user_id, permission) when is_binary(permission) do
    case get_server(server_id) do
      %Server{owner_id: ^user_id} -> true
      nil -> false
      _server ->
        member =
          Repo.one(
            from m in Member,
            where: m.server_id == ^server_id and m.user_id == ^user_id,
            preload: [:roles]
          )

        case member do
          nil -> false
          %Member{roles: roles} ->
            Enum.any?(roles, fn role -> Map.get(role.permissions, permission, false) end)
        end
    end
  end

  def owner?(server_id, user_id) do
    case get_server(server_id) do
      %Server{owner_id: ^user_id} -> true
      _ -> false
    end
  end

  # ── Discovery ──────────────────────────────────────────────────────────────

  def discover_servers(opts \\ []) do
    query = from s in Server, where: s.is_public == true

    query = case Keyword.get(opts, :category) do
      nil -> query
      cat -> where(query, [s], s.category == ^cat)
    end

    query = case Keyword.get(opts, :query) do
      nil -> query
      q   -> where(query, [s], ilike(s.name, ^"%#{q}%"))
    end

    limit = Keyword.get(opts, :limit, 24)

    Repo.all(
      from q in query,
      select: %{
        id:           q.id,
        name:         q.name,
        description:  q.description,
        icon_url:     q.icon_url,
        category:     q.category,
        member_count: q.member_count
      },
      order_by: [desc: q.member_count],
      limit:    ^limit
    )
  end
end
