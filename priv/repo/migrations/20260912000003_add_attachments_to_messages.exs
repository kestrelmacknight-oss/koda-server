defmodule Koda.Repo.Migrations.AddAttachmentsToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add_if_not_exists :attachment_url, :string
      add_if_not_exists :attachment_content_type, :string
    end

    alter table(:dm_messages) do
      add_if_not_exists :attachment_url, :string
      add_if_not_exists :attachment_content_type, :string
    end
  end
end
