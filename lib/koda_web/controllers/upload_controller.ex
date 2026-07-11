defmodule KodaWeb.UploadController do
  use KodaWeb, :controller
  alias Koda.Upload

  # Receives raw file bytes in the request body.
  # Content-Type header identifies the file type.
  # X-Upload-Type header identifies the purpose: avatar | gallery | attachment
  def upload(conn, _params) do
    user         = Guardian.Plug.current_resource(conn)
    upload_type  = get_req_header(conn, "x-upload-type") |> List.first() || "attachment"
    content_type = get_req_header(conn, "content-type")  |> List.first() || "application/octet-stream"

    {:ok, body, _conn} = Plug.Conn.read_body(conn, length: Upload.max_bytes() + 1)

    case Upload.upload(user.id, upload_type, content_type, body) do
      {:ok, cdn_url} ->
        json(conn, %{cdn_url: cdn_url, max_bytes: Upload.max_bytes()})

      {:error, :unsupported_content_type} ->
        conn
        |> put_status(422)
        |> json(%{error: "Unsupported file type", allowed: Upload.allowed_content_types()})

      {:error, :invalid_upload_type} ->
        conn |> put_status(422) |> json(%{error: "X-Upload-Type must be avatar, gallery, or attachment"})

      {:error, :too_large} ->
        mb = Float.round(Upload.max_bytes() / (1024 * 1024), 0) |> trunc()
        conn |> put_status(413) |> json(%{error: "File too large. Maximum is #{mb}MB."})

      {:error, reason} ->
        conn |> put_status(500) |> json(%{error: "Upload failed: #{inspect(reason)}"})
    end
  end
end