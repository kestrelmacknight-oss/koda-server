defmodule Koda.Repo.Migrations.BackfillDefaultRoles do
  use Ecto.Migration

  # Default permission set for the auto-created @everyone-equivalent role.
  # Owners always bypass permission checks entirely regardless of role,
  # so this only governs what non-owner members can do by default.
  @default_permissions %{
    "view_channels"   => true,
    "send_messages"   => true,
    "connect_voice"   => true,
    "manage_server"   => false,
    "manage_channels" => false,
    "manage_roles"    => false,
    "manage_messages" => false,
    "kick_members"    => false,
    "ban_members"     => false,
    "mention_everyone"=> false
  }

  def up do
    # One default role per existing server that doesn't already have one
    execute """
    INSERT INTO roles (id, server_id, name, color, position, is_default, permissions, inserted_at, updated_at)
    SELECT gen_random_uuid(), s.id, 'Member', '#9BA5C8', 0, true,
           '#{Jason.encode!(@default_permissions)}'::jsonb, now(), now()
    FROM servers s
    WHERE NOT EXISTS (
      SELECT 1 FROM roles r WHERE r.server_id = s.id AND r.is_default = true
    )
    """

    # Assign every existing member their server's default role
    execute """
    INSERT INTO member_roles (id, member_id, role_id, inserted_at)
    SELECT gen_random_uuid(), m.id, r.id, now()
    FROM server_members m
    JOIN roles r ON r.server_id = m.server_id AND r.is_default = true
    WHERE NOT EXISTS (
      SELECT 1 FROM member_roles mr WHERE mr.member_id = m.id AND mr.role_id = r.id
    )
    """
  end

  def down do
    execute "DELETE FROM member_roles"
    execute "DELETE FROM roles WHERE is_default = true"
  end
end
