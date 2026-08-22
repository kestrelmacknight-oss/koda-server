defmodule KodaWeb.ImportController do
  use KodaWeb, :controller
  alias Koda.{Servers, Repo}
  import Ecto.Query

  # Discord channel type constants
  @discord_text     0
  @discord_dm       1
  @discord_voice    2
  @discord_category 4
  @discord_announce 5
  @discord_stage    13
  @discord_forum    15

  # Discord permission bit flags we care about
  @perm_view_channel      0x0000000000000400
  @perm_send_messages     0x0000000000000800
  @perm_manage_messages   0x0000000000002000
  @perm_connect           0x0000000000100000
  @perm_kick_members      0x0000000000000002
  @perm_ban_members       0x0000000000000004
  @perm_manage_server     0x0000000000000020
  @perm_manage_channels   0x0000000000000010
  @perm_manage_roles      0x0000000000010000000

  # ── Fetch and parse Discord template ─────────────────────────────────────

  def preview(conn, %{"code" => code}) do
    user = Guardian.Plug.current_resource(conn)
    case fetch_discord_template(code) do
      {:ok, template} ->
        parsed = parse_template(template)
        json(conn, %{ok: true, template: parsed})
      {:error, reason} ->
        conn |> put_status(422) |> json(%{error: reason})
    end
  end

  # ── Apply template to a server ────────────────────────────────────────────

  def apply(conn, %{"server_id" => server_id} = params) do
    user   = Guardian.Plug.current_resource(conn)
    server = Servers.get_server(server_id)

    unless server && (server.owner_id == user.id || user.is_admin) do
      conn |> put_status(403) |> json(%{error: "Not authorized"})
    else
      replace = Map.get(params, "replace", false)
      code    = Map.get(params, "code", "")
      parsed  = Map.get(params, "parsed")  # pre-parsed from preview

      template_data = if parsed do
        {:ok, parsed}
      else
        case fetch_discord_template(code) do
          {:ok, t} -> {:ok, parse_template(t)}
          err      -> err
        end
      end

      case template_data do
        {:error, reason} ->
          conn |> put_status(422) |> json(%{error: reason})

        {:ok, %{"roles" => roles, "categories" => categories, "channels" => channels}} ->
          Repo.transaction(fn ->
            # If replace mode -- delete existing channels, categories, roles
            if replace do
              Repo.delete_all(from c in Koda.Servers.Channel, where: c.server_id == ^server_id)
              Repo.delete_all(from c in Koda.Servers.Category, where: c.server_id == ^server_id)
              Repo.delete_all(from r in Koda.Servers.Role,
                where: r.server_id == ^server_id and r.name != "@everyone")
            end

            # Create roles (skip @everyone -- Koda handles it natively)
            role_map = roles
              |> Enum.reject(& &1["name"] == "@everyone")
              |> Enum.reduce(%{}, fn role, acc ->
                case Servers.create_role(server_id, %{
                  "name"        => role["name"],
                  "color"       => role["color"],
                  "permissions" => role["permissions"]
                }) do
                  {:ok, r} -> Map.put(acc, role["discord_id"], r.id)
                  _        -> acc
                end
              end)

            # Create categories
            cat_map = categories
              |> Enum.reduce(%{}, fn cat, acc ->
                case Servers.create_category(server_id, %{"name" => cat["name"]}) do
                  {:ok, c} -> Map.put(acc, cat["discord_id"], c.id)
                  _        -> acc
                end
              end)

            # Create channels
            Enum.each(channels, fn ch ->
              category_id = if ch["category_discord_id"],
                do: Map.get(cat_map, ch["category_discord_id"]),
                else: nil

              Servers.create_channel(server_id, %{
                "name"        => ch["name"],
                "type"        => ch["type"],
                "category_id" => category_id,
                "position"    => ch["position"]
              })
            end)
          end)

          json(conn, %{ok: true, message: "Template applied successfully"})
      end
    end
  end

  # ── Private: fetch from Discord public API ────────────────────────────────

  defp fetch_discord_template(code) do
    url = "https://discord.com/api/v10/guilds/templates/#{String.trim(code)}"
    headers = [{"User-Agent", "Koda/1.0"}, {"Content-Type", "application/json"}]

    case :httpc.request(:get, {String.to_charlist(url), headers}, [], []) do
      {:ok, {{_, 200, _}, _, body}} ->
        case Jason.decode(List.to_string(body)) do
          {:ok, data} -> {:ok, data}
          _           -> {:error, "Failed to parse Discord response"}
        end
      {:ok, {{_, 404, _}, _, _}} ->
        {:error, "Template not found. Check the code and try again."}
      {:ok, {{_, status, _}, _, _}} ->
        {:error, "Discord API returned status #{status}"}
      {:error, reason} ->
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  # ── Private: parse Discord template into Koda-friendly format ────────────

  defp parse_template(%{"serialized_source_guild" => guild, "name" => name}) do
    channels    = Map.get(guild, "channels", [])
    roles       = Map.get(guild, "roles", [])

    categories = channels
      |> Enum.filter(& &1["type"] == @discord_category)
      |> Enum.map(fn c ->
        %{
          "discord_id" => c["id"],
          "name"       => c["name"],
          "position"   => c["position"]
        }
      end)
      |> Enum.sort_by(& &1["position"])

    mapped_channels = channels
      |> Enum.reject(& &1["type"] == @discord_category)
      |> Enum.map(fn c ->
        %{
          "discord_id"          => c["id"],
          "name"                => c["name"],
          "type"                => map_channel_type(c["type"]),
          "position"            => c["position"],
          "category_discord_id" => c["parent_id"]
        }
      end)
      |> Enum.sort_by(& &1["position"])

    mapped_roles = roles
      |> Enum.map(fn r ->
        %{
          "discord_id"  => r["id"],
          "name"        => r["name"],
          "color"       => Map.get(r, "color", 0),
          "permissions" => map_permissions(Map.get(r, "permissions", "0"))
        }
      end)

    %{
      "name"       => name,
      "roles"      => mapped_roles,
      "categories" => categories,
      "channels"   => mapped_channels
    }
  end

  defp parse_template(_), do: %{"roles" => [], "categories" => [], "channels" => []}

  defp map_channel_type(@discord_text),     do: "text"
  defp map_channel_type(@discord_voice),    do: "voice"
  defp map_channel_type(@discord_announce), do: "text"   # closest equivalent
  defp map_channel_type(@discord_stage),    do: "stage"
  defp map_channel_type(@discord_forum),    do: "gallery" # closest equivalent
  defp map_channel_type(_),                 do: "text"

  defp map_permissions(bits_str) do
    bits = String.to_integer(bits_str)
    %{
      "view_channels"    => bit_set?(bits, @perm_view_channel),
      "send_messages"    => bit_set?(bits, @perm_send_messages),
      "manage_messages"  => bit_set?(bits, @perm_manage_messages),
      "connect_voice"    => bit_set?(bits, @perm_connect),
      "kick_members"     => bit_set?(bits, @perm_kick_members),
      "ban_members"      => bit_set?(bits, @perm_ban_members),
      "manage_server"    => bit_set?(bits, @perm_manage_server),
      "manage_channels"  => bit_set?(bits, @perm_manage_channels),
      "manage_roles"     => bit_set?(bits, @perm_manage_roles)
    }
  end

  defp bit_set?(bits, flag), do: Bitwise.band(bits, flag) != 0
end
