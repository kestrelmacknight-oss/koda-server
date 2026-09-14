defmodule Koda.Parental do
  @moduledoc """
  Parent/child account supervision: creating a child account, a parent's
  read-only-plus-remove access to a child's friends/servers (never
  message content), and the child's weekly access schedule + temporary
  overrides.

  Every function here that acts on a child's data re-checks
  `parent_of?/2` internally, not only at the controller layer -- these
  are the only functions in the codebase that let one account mutate
  another account's data, so the guard belongs at the point of effect,
  not just at the door.
  """
  import Ecto.Query
  alias Koda.{Repo, Friends, Servers}
  alias Koda.Auth.User
  alias Koda.Parental.{ParentalLink, ChildSchedule, ScheduleOverride}

  @weekday_keys %{1 => "mon", 2 => "tue", 3 => "wed", 4 => "thu", 5 => "fri", 6 => "sat", 7 => "sun"}

  # ── Child account creation & linking ────────────────────────────────────

  @doc """
  Creates a child account and links it to `parent` in one transaction.
  The only path in the codebase that can ever produce
  `account_type: "child"` -- see User.child_registration_changeset/2.
  """
  def create_child_account(%User{} = parent, attrs) do
    Repo.transaction(fn ->
      with {:ok, child} <-
             %User{} |> User.child_registration_changeset(attrs) |> Repo.insert(),
           {:ok, _link} <-
             %ParentalLink{}
             |> ParentalLink.changeset(%{"parent_id" => parent.id, "child_id" => child.id})
             |> Repo.insert() do
        child
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc "The authorization primitive every other function below relies on."
  def parent_of?(parent_id, child_id) do
    Repo.exists?(from l in ParentalLink, where: l.parent_id == ^parent_id and l.child_id == ^child_id)
  end

  def list_children(parent_id) do
    Repo.all(from l in ParentalLink, where: l.parent_id == ^parent_id, preload: [:child])
    |> Enum.map(& &1.child)
  end

  @doc """
  Removes the parent/child link and reverts the child's account_type to
  "standard" in the same transaction -- an unlinked account is never left
  permanently locked with no one able to adjust it.
  """
  def unlink_child(parent_id, child_id) do
    if parent_of?(parent_id, child_id) do
      Repo.transaction(fn ->
        Repo.delete_all(from l in ParentalLink, where: l.parent_id == ^parent_id and l.child_id == ^child_id)
        Repo.update_all(from(u in User, where: u.id == ^child_id), set: [account_type: "standard"])
      end)
      :ok
    else
      {:error, :not_authorized}
    end
  end

  # ── Friends/servers -- structural visibility, never message content ────

  def list_child_friends(parent_id, child_id) do
    if parent_of?(parent_id, child_id) do
      {:ok, Friends.list_friends(child_id)}
    else
      {:error, :not_authorized}
    end
  end

  def remove_child_friend(parent_id, child_id, friend_id) do
    if parent_of?(parent_id, child_id) do
      Friends.unfriend(child_id, friend_id)
    else
      {:error, :not_authorized}
    end
  end

  def list_child_servers(parent_id, child_id) do
    if parent_of?(parent_id, child_id) do
      {:ok, Servers.list_user_servers(child_id)}
    else
      {:error, :not_authorized}
    end
  end

  def remove_child_from_server(parent_id, child_id, server_id) do
    if parent_of?(parent_id, child_id) do
      Servers.remove_member(server_id, child_id)
    else
      {:error, :not_authorized}
    end
  end

  # ── Schedule ─────────────────────────────────────────────────────────────

  def get_schedule(child_id), do: Repo.get_by(ChildSchedule, child_id: child_id)

  def upsert_schedule(parent_id, child_id, attrs) do
    if parent_of?(parent_id, child_id) do
      (get_schedule(child_id) || %ChildSchedule{})
      |> ChildSchedule.changeset(Map.put(attrs, "child_id", child_id))
      |> Repo.insert_or_update()
    else
      {:error, :not_authorized}
    end
  end

  @doc """
  Removes any schedule restriction entirely -- distinct from saving an
  empty `windows` map, which (since the row would still exist) means
  "no allowed minutes on any day," i.e. always blocked. Deleting the row
  is the only way back to "unrestricted" once a schedule has been set.
  """
  def delete_schedule(parent_id, child_id) do
    if parent_of?(parent_id, child_id) do
      Repo.delete_all(from s in ChildSchedule, where: s.child_id == ^child_id)
      :ok
    else
      {:error, :not_authorized}
    end
  end

  # ── Overrides ────────────────────────────────────────────────────────────

  def grant_override(parent_id, child_id, attrs) do
    if parent_of?(parent_id, child_id) do
      %ScheduleOverride{}
      |> ScheduleOverride.changeset(%{
        "child_id"      => child_id,
        "granted_by_id" => parent_id,
        "expires_at"    => override_expires_at(attrs),
        "reason"        => Map.get(attrs, "reason")
      })
      |> Repo.insert()
    else
      {:error, :not_authorized}
    end
  end

  defp override_expires_at(%{"duration_minutes" => minutes}) when is_integer(minutes) and minutes > 0 do
    DateTime.add(DateTime.utc_now(), minutes, :minute)
  end

  defp override_expires_at(%{"expires_at" => iso}) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> dt
      _ -> DateTime.add(DateTime.utc_now(), 30, :minute)
    end
  end

  defp override_expires_at(_), do: DateTime.add(DateTime.utc_now(), 30, :minute)

  def revoke_override(parent_id, child_id) do
    if parent_of?(parent_id, child_id) do
      Repo.delete_all(
        from o in ScheduleOverride,
        where: o.child_id == ^child_id and o.expires_at > ^DateTime.utc_now()
      )
      :ok
    else
      {:error, :not_authorized}
    end
  end

  def active_override?(child_id) do
    Repo.exists?(
      from o in ScheduleOverride,
      where: o.child_id == ^child_id and o.expires_at > ^DateTime.utc_now()
    )
  end

  # ── The gate every enforcement layer calls ──────────────────────────────

  @doc "True for any non-child account. For a child, delegates to within_window?/2."
  def allowed_now?(%User{account_type: "child"} = user), do: within_window?(user.id)
  def allowed_now?(%User{}), do: true

  @doc """
  Whether `child_id` is currently inside an allowed window: an active
  override always wins; no schedule row means unrestricted; otherwise
  `now` is converted into the schedule's timezone and checked against
  that weekday's windows, wrapping past midnight when a window's end is
  earlier than its start.
  """
  def within_window?(child_id, now \\ DateTime.utc_now()) do
    cond do
      active_override?(child_id) ->
        true

      true ->
        case get_schedule(child_id) do
          nil ->
            true

          %ChildSchedule{} = schedule ->
            local = DateTime.shift_zone!(now, schedule.timezone, Tzdata.TimeZoneDatabase)
            weekday = Map.fetch!(@weekday_keys, local |> DateTime.to_date() |> Date.day_of_week())
            minute = local.hour * 60 + local.minute
            windows = Map.get(schedule.windows, weekday, [])
            Enum.any?(windows, &minute_in_window?(minute, &1))
        end
    end
  end

  defp minute_in_window?(minute, [start_min, end_min]) when start_min <= end_min do
    minute >= start_min and minute < end_min
  end

  defp minute_in_window?(minute, [start_min, end_min]) do
    # end_min < start_min: the window wraps past midnight.
    minute >= start_min or minute < end_min
  end

  defp minute_in_window?(_minute, _window), do: false
end
