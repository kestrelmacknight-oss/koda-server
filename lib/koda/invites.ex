defmodule Koda.Invites do
  @moduledoc """
  Server invite codes and backer/redemption code system.

  Server invites: short random codes that let anyone join a specific server.
  Backer codes: admin-generated codes that apply account flags on redemption.
  """
  import Ecto.Query
  alias Koda.{Repo, Servers}

  # -- Schemas -----------------------------------------------------------------

  defmodule Invite do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "invites" do
      field :code,       :string
      field :uses,       :integer, default: 0
      field :max_uses,   :integer
      field :expires_at, :utc_datetime
      belongs_to :server,  Koda.Servers.Server
      belongs_to :creator, Koda.Auth.User
      timestamps(type: :utc_datetime)
    end

    def changeset(i, attrs) do
      i
      |> cast(attrs, [:code, :server_id, :creator_id, :max_uses, :expires_at])
      |> validate_required([:code, :server_id, :creator_id])
      |> unique_constraint(:code)
    end
  end

  defmodule BackerCode do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "backer_codes" do
      field :code,       :string
      field :flags,      :map, default: %{}
      field :note,       :string
      field :max_uses,   :integer
      field :uses,       :integer, default: 0
      field :expires_at, :utc_datetime
      belongs_to :creator, Koda.Auth.User, foreign_key: :created_by
      timestamps(type: :utc_datetime)
    end

    def changeset(c, attrs) do
      c
      |> cast(attrs, [:code, :flags, :note, :max_uses, :expires_at, :created_by])
      |> validate_required([:code, :flags])
      |> unique_constraint(:code)
    end
  end

  defmodule Redemption do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "backer_code_redemptions" do
      field :redeemed_at, :utc_datetime
      belongs_to :code, BackerCode
      belongs_to :user, Koda.Auth.User
    end

    def changeset(r, attrs) do
      r
      |> cast(attrs, [:code_id, :user_id, :redeemed_at])
      |> validate_required([:code_id, :user_id, :redeemed_at])
      |> unique_constraint([:code_id, :user_id],
           message: "You have already redeemed this code")
    end
  end

  # -- Server invites ----------------------------------------------------------

  def create_invite(server_id, creator_id, opts \\ []) do
    code = generate_code()
    %Invite{}
    |> Invite.changeset(%{
      code:       code,
      server_id:  server_id,
      creator_id: creator_id,
      max_uses:   Keyword.get(opts, :max_uses),
      expires_at: Keyword.get(opts, :expires_at)
    })
    |> Repo.insert()
  end

  def list_invites(server_id) do
    Repo.all(
      from i in Invite,
      where: i.server_id == ^server_id,
      order_by: [desc: i.inserted_at],
      preload: [:creator]
    )
  end

  def delete_invite(invite), do: Repo.delete(invite)

  def get_invite_by_code(code) do
    Repo.get_by(Invite, code: code)
  end

  @doc """
  Redeem a server invite code. Adds the user to the server if valid.
  Returns {:ok, server} or {:error, reason}.
  """
  def redeem_invite(code, user_id) do
    case get_invite_by_code(code) do
      nil ->
        {:error, :invalid_code}

      invite ->
        now = DateTime.utc_now()

        cond do
          invite.expires_at && DateTime.compare(invite.expires_at, now) == :lt ->
            {:error, :expired}

          invite.max_uses && invite.uses >= invite.max_uses ->
            {:error, :max_uses_reached}

          true ->
            Repo.transaction(fn ->
              # Increment use count
              Repo.update_all(
                from(i in Invite, where: i.id == ^invite.id),
                inc: [uses: 1]
              )

              # Add member to server (idempotent if already a member)
              case Servers.get_member(invite.server_id, user_id) do
                nil -> Servers.add_member(invite.server_id, user_id)
                _   -> :ok
              end

              Servers.get_server(invite.server_id)
            end)
        end
    end
  end

  # -- Backer codes ------------------------------------------------------------

  def create_backer_code(admin_id, attrs) do
    code = Keyword.get(attrs, :code) || generate_code(12)
    %BackerCode{}
    |> BackerCode.changeset(%{
      code:       code,
      flags:      Keyword.get(attrs, :flags, %{}),
      note:       Keyword.get(attrs, :note),
      max_uses:   Keyword.get(attrs, :max_uses),
      expires_at: Keyword.get(attrs, :expires_at),
      created_by: admin_id
    })
    |> Repo.insert()
  end

  def list_backer_codes do
    Repo.all(from c in BackerCode, order_by: [desc: c.inserted_at])
  end

  def get_backer_code(code) do
    Repo.get_by(BackerCode, code: code)
  end

  @doc """
  Redeem a backer code. Merges the code's flags into the user's account flags.
  Returns {:ok, updated_user} or {:error, reason}.
  """
  def redeem_backer_code(code, user_id) do
    case get_backer_code(code) do
      nil ->
        {:error, :invalid_code}

      backer_code ->
        now = DateTime.utc_now()

        already_redeemed = Repo.exists?(
          from r in Redemption,
          where: r.code_id == ^backer_code.id and r.user_id == ^user_id
        )

        cond do
          already_redeemed ->
            {:error, :already_redeemed}

          backer_code.expires_at &&
              DateTime.compare(backer_code.expires_at, now) == :lt ->
            {:error, :expired}

          backer_code.max_uses && backer_code.uses >= backer_code.max_uses ->
            {:error, :max_uses_reached}

          true ->
            Repo.transaction(fn ->
              # Record redemption
              %Redemption{}
              |> Redemption.changeset(%{
                  code_id:     backer_code.id,
                  user_id:     user_id,
                  redeemed_at: now
                })
              |> Repo.insert!()

              # Increment use count
              Repo.update_all(
                from(c in BackerCode, where: c.id == ^backer_code.id),
                inc: [uses: 1]
              )

              # Merge flags into user's account flags
              user = Repo.get!(Koda.Auth.User, user_id)
              merged_flags = Map.merge(user.flags || %{}, backer_code.flags)
              user
              |> Koda.Auth.User.flags_changeset(%{flags: merged_flags})
              |> Repo.update!()
            end)
        end
    end
  end

  # -- Helpers -----------------------------------------------------------------

  defp generate_code(length \\ 6) do
    :crypto.strong_rand_bytes(length)
    |> Base.url_encode64(padding: false)
    |> String.slice(0, length)
    |> String.upcase()
  end
end