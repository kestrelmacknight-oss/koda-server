defmodule Koda.Repo.Migrations.AddContentLabelsToChannels do
  use Ecto.Migration

  def change do
    alter table(:channels) do
      # BlueSky-style content labels a server owner/mod can flag a channel
      # with: "adult" | "suggestive" | "graphic" | "nudity". Empty list
      # means unlabeled. See Koda.Servers.member_can_view_channel?/2 for
      # how this hard-blocks child accounts, and channel_json/1 for how
      # standard accounts get it to drive their own hide/warn/show prefs.
      add_if_not_exists :content_labels, {:array, :string}, default: []
    end
  end
end
