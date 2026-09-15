defmodule Koda.ServerSubscriptions.SubscriptionSweeper do
  @moduledoc """
  Runs hourly (see config :koda, Oban's Cron plugin). A server
  subscription is a one-time 30-day grant, not an auto-renewing Stripe
  Subscription -- nothing queries expires_at on its own to stop granting
  access, so this is what actually flips a due subscription to
  "expired" and removes the role its tier granted. See
  Koda.ServerSubscriptions.expire_due_subscriptions/0 for the real work;
  this worker is just the schedule.
  """
  use Oban.Worker, queue: :default

  @impl Oban.Worker
  def perform(_job) do
    Koda.ServerSubscriptions.expire_due_subscriptions()
    :ok
  end
end
