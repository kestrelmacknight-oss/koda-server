defmodule Koda.Moderation.RateLimiter do
  @moduledoc """
  In-memory (ETS) sliding-window rate limiting for message sends, flood
  detection (repeated violations auto-mute), and raid detection (a burst
  of joins auto-locks a server's invites). Deliberately metadata-only --
  send timestamps and counts, never content -- keeping it Tier 1 (zero
  knowledge safe).

  Single-node by design, matching how this app is actually deployed
  today: state lives in this process's ETS tables, not a shared store.
  A multi-node deployment would need this behind something like Redis
  instead.
  """
  use GenServer

  @send_table :koda_rl_sends
  @raid_table :koda_rl_raid_joins

  # A member may send this many channel messages per @msg_window_ms
  # before being rate-limited.
  @msg_limit 8
  @msg_window_ms 10_000

  # Hitting the rate limit this many times within @flood_window_ms is
  # treated as flooding, not just a burst -- auto-mutes for
  # @flood_mute_seconds and logs it.
  @flood_violations 3
  @flood_window_ms 30_000
  @flood_mute_seconds 300

  # This many new joins to one server within @raid_window_ms auto-locks
  # that server's invites (Server.invites_locked) until a human clears it.
  @raid_join_threshold 10
  @raid_window_ms 60_000

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    :ets.new(@send_table, [:named_table, :public, :set])
    :ets.new(@raid_table, [:named_table, :public, :bag])
    {:ok, %{}}
  end

  @doc """
  Records a send attempt for `{channel_id, user_id}`. Returns :ok if it's
  allowed, or :rate_limited if it's over @msg_limit for the window (in
  which case a repeated-violation count is bumped, possibly triggering
  an automatic flood mute as a side effect).
  """
  def check_send(server_id, channel_id, user_id) do
    now = System.monotonic_time(:millisecond)
    key = {channel_id, user_id}

    recent =
      case :ets.lookup(@send_table, key) do
        [{^key, timestamps}] -> Enum.filter(timestamps, &(now - &1 < @msg_window_ms))
        [] -> []
      end

    if length(recent) >= @msg_limit do
      record_violation(server_id, user_id)
      :rate_limited
    else
      :ets.insert(@send_table, {key, [now | recent]})
      :ok
    end
  end

  defp record_violation(server_id, user_id) do
    now = System.monotonic_time(:millisecond)
    vkey = {:violations, server_id, user_id}

    recent =
      case :ets.lookup(@send_table, vkey) do
        [{^vkey, timestamps}] -> Enum.filter(timestamps, &(now - &1 < @flood_window_ms))
        [] -> []
      end

    updated = [now | recent]

    if length(updated) >= @flood_violations do
      :ets.delete(@send_table, vkey) # reset after acting, don't re-trigger on the next check
      Koda.Moderation.mute_member(server_id, user_id, @flood_mute_seconds,
        reason: "Automatic: repeated rate-limit violations")
      Koda.Moderation.log(server_id, "flood_detected", target_user_id: user_id,
        metadata: %{"violations" => length(updated)})
    else
      :ets.insert(@send_table, {vkey, updated})
    end
  end

  @doc """
  Records a join to `server_id` and returns true if this join pushed the
  server over the raid-detection threshold. The caller (Koda.Invites)
  decides what to do with that -- currently, locking invites.
  """
  def record_join_and_check_raid(server_id) do
    now = System.monotonic_time(:millisecond)

    recent =
      :ets.lookup(@raid_table, server_id)
      |> Enum.filter(fn {_, ts} -> now - ts < @raid_window_ms end)

    # Rewritten (not just filtered) each time so the table can't grow
    # unboundedly across a long-lived server's lifetime -- bounded to
    # whatever's actually within the current window.
    :ets.delete(@raid_table, server_id)
    Enum.each(recent, &:ets.insert(@raid_table, &1))
    :ets.insert(@raid_table, {server_id, now})

    length(recent) + 1 >= @raid_join_threshold
  end
end
