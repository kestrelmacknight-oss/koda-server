defmodule Koda.Repo.Migrations.AddRecurrenceAndTicketsToEvents do
  use Ecto.Migration

  def change do
    alter table(:server_events) do
      # Cents; 0 = free. Only meaningful when stage_channel_id is set --
      # see Koda.Events.current_ticketed_event/1.
      add_if_not_exists :price_cents, :integer, default: 0
      # Distinct from channel_id (which calendar this event is filed
      # under/displayed in) -- this is which stage channel, if any, a
      # ticket to this event actually grants access to. Nullable: most
      # calendar events aren't stage shows at all.
      add_if_not_exists :stage_channel_id, references(:channels, type: :binary_id, on_delete: :nilify_all)
    end

    create table(:event_tickets, primary_key: false) do
      add :id,                       :binary_id, primary_key: true
      add :event_id,                 references(:server_events, type: :binary_id, on_delete: :delete_all), null: false
      add :buyer_id,                 references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :amount_cents,             :integer, null: false
      add :fee_cents,                :integer, default: 0
      add :stripe_payment_intent_id, :string
      add :status,                   :string, default: "pending"
      timestamps(type: :utc_datetime_usec)
    end

    # Not a unique index -- deliberately matches product_purchases'
    # pattern (see Koda.DigitalProducts), which allows multiple
    # pending/failed rows for the same buyer+item and only treats
    # status == "complete" as meaningful, avoiding retry-after-failure
    # friction a strict uniqueness constraint would cause.
    create index(:event_tickets, [:event_id, :buyer_id])
    create index(:event_tickets, [:stripe_payment_intent_id])
  end
end
