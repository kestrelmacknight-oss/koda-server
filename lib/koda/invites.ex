defmodule Koda.Invites do
  import Ecto.Query
  alias Koda.Repo
  alias Koda.Servers

  defmodule Invite do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "invites" do
      field :code,         :string
      field :is_permanent, :boolean, default: false
      field :uses,         :integer, default: 0
      field :max_uses,     :integer
      field :expires_at,   :utc_datetime
      belongs_to :server,  Koda.Servers.Server
      belongs_to :creator, Koda.Auth.User
      timestamps(type: :utc_datetime, updated_at: false)
    end

    def changeset(invite, attrs) do
      invite
      |> cast(attrs, [:server_id, :creator_id, :code, :is_permanent,
                      :max_uses, :expires_at])
      |> validate_required([:server_id, :creator_id, :code])
      |> unique_constraint(:code)
    end
  end

  def get_by_code(code) do
    Repo.one(
      from i in Invite,
      where: i.code == ^code,
      preload: [:server]
    )
  end

  def create_permanent_invite(server_id, creator_id) do
    code = generate_code()
    %Invite{}
    |> Invite.changeset(%{
      server_id:   server_id,
      creator_id:  creator_id,
      code:        code,
      is_permanent: true
    })
    |> Repo.insert()
  end

  def create_invite(server_id, creator_id, opts \\ []) do
    expires_at = case Keyword.get(opts, :expires_in_hours) do
      nil   -> nil
      hours -> DateTime.add(DateTime.utc_now(), hours * 3600, :second)
    end

    %Invite{}
    |> Invite.changeset(%{
      server_id:   server_id,
      creator_id:  creator_id,
      code:        generate_code(),
      is_permanent: false,
      max_uses:    Keyword.get(opts, :max_uses),
      expires_at:  expires_at
    })
    |> Repo.insert()
  end

  def use_invite(code, user_id) do
    now = DateTime.utc_now()

    case get_by_code(code) do
      nil ->
        {:error, :not_found}

      invite ->
        cond do
          invite.expires_at && DateTime.compare(invite.expires_at, now) == :lt ->
            {:error, :expired}

          invite.max_uses && invite.uses >= invite.max_uses ->
            {:error, :max_uses_reached}

          Servers.get_member(invite.server_id, user_id) ->
            {:error, :already_member}

          true ->
            Repo.transaction(fn ->
              Repo.update_all(
                from(i in Invite, where: i.id == ^invite.id),
                inc: [uses: 1]
              )
              Servers.add_member(invite.server_id, user_id)
              invite
            end)
        end
    end
  end

  def list_server_invites(server_id) do
    Repo.all(from i in Invite, where: i.server_id == ^server_id, preload: [:creator])
  end

  def delete_invite(id), do: Repo.delete(%Invite{id: id})

  defp generate_code do
    :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false) |> String.slice(0, 8)
  end
end
