defmodule Koda.Moderation do
  @moduledoc """
  Tier 1 ("Zero Knowledge Safe") moderation: rate limiting, flood/raid
  detection, mutes, and the audit log all of that (plus kicks/bans) write
  into. Every function here operates on metadata only -- who did what to
  whom, when, how often -- and never touches message content. Content
  moderation with user consent is Koda.Reports (Tier 2, not yet built);
  threshold moderator decryption is a distinct, explicitly opt-in Tier 3
  (not yet built either).
  """
  import Ecto.Query
  alias Koda.Repo

  defmodule Action do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id
    schema "moderation_actions" do
      field :server_id,      :binary_id
      # nil means the system itself took this action (an automated
      # flood-triggered mute or raid lockdown), not a human moderator.
      field :actor_id,       :binary_id
      field :target_user_id, :binary_id
      field :action,         :string
      field :reason,         :string
      field :metadata,       :map, default: %{}
      field :inserted_at,    :utc_datetime_usec
    end

    def changeset(a, attrs) do
      a
      |> cast(attrs, [:server_id, :actor_id, :target_user_id, :action, :reason,
                      :metadata, :inserted_at])
      |> validate_required([:server_id, :action, :inserted_at])
    end
  end

  # ── Audit log ──────────────────────────────────────────────────────────

  def log(server_id, action, opts \\ []) do
    %Action{}
    |> Action.changeset(%{
      server_id:      server_id,
      actor_id:       Keyword.get(opts, :actor_id),
      target_user_id: Keyword.get(opts, :target_user_id),
      action:         action,
      reason:         Keyword.get(opts, :reason),
      metadata:       Keyword.get(opts, :metadata, %{}),
      inserted_at:    DateTime.utc_now()
    })
    |> Repo.insert()
  end

  def list_actions(server_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    Repo.all(
      from a in Action,
      where: a.server_id == ^server_id,
      order_by: [desc: a.inserted_at],
      limit: ^limit
    )
  end

  def action_json(a) do
    %{
      id:             a.id,
      actor_id:       a.actor_id,
      target_user_id: a.target_user_id,
      action:         a.action,
      reason:         a.reason,
      metadata:       a.metadata,
      inserted_at:    DateTime.to_iso8601(a.inserted_at)
    }
  end

  # ── Mute ───────────────────────────────────────────────────────────────

  def mute_member(server_id, user_id, duration_seconds, opts \\ []) do
    case Koda.Servers.get_member(server_id, user_id) do
      nil ->
        {:error, :not_found}

      member ->
        until = DateTime.utc_now() |> DateTime.add(duration_seconds, :second)

        case member |> Ecto.Changeset.change(muted_until: until) |> Repo.update() do
          {:ok, updated} ->
            log(server_id, "mute",
              actor_id: Keyword.get(opts, :actor_id),
              target_user_id: user_id,
              reason: Keyword.get(opts, :reason),
              metadata: %{"until" => DateTime.to_iso8601(until)})
            {:ok, updated}
          error -> error
        end
    end
  end

  def unmute_member(server_id, user_id, opts \\ []) do
    case Koda.Servers.get_member(server_id, user_id) do
      nil ->
        {:error, :not_found}

      member ->
        case member |> Ecto.Changeset.change(muted_until: nil) |> Repo.update() do
          {:ok, updated} ->
            log(server_id, "unmute", actor_id: Keyword.get(opts, :actor_id), target_user_id: user_id)
            {:ok, updated}
          error -> error
        end
    end
  end

  def muted?(server_id, user_id) do
    case Koda.Servers.get_member(server_id, user_id) do
      nil -> false
      %{muted_until: nil} -> false
      %{muted_until: until} -> DateTime.compare(until, DateTime.utc_now()) == :gt
    end
  end
end
