defmodule KodaWeb.VersionController do
  use KodaWeb, :controller

  # Update these values when releasing a new client build.
  @current_version "0.34.0"
  @download_url    "https://koda.fyi/download"
  @release_notes   "Initial Alpha release"

  def index(conn, _params) do
    json(conn, %{
      version:       @current_version,
      download_url:  @download_url,
      release_notes: @release_notes,
      required:      false   # set true to force update
    })
  end
end
