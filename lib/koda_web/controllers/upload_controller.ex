defmodule KodaWeb.UploadController do
  use KodaWeb, :controller
  alias Koda.Upload

  def presign(conn, %{"type" => upload_type, "content_type" => content_type}) do
    case Upload.presign(Guardian.Plug.current_resource(conn).id, upload_type, content_type) do
      {:ok, payload} ->
        json(conn, %{
          upload_url: payload.upload_url,
          cdn_url:    payload.cdn_url,
          key:        payload.key,
          expires_in: 300,
          max_bytes:  Upload.max_bytes()
        })

      {:error, :unsupported_content_type} ->
        conn
        |> put_status(422)
        |> json(%{
          error: "Unsupported file type",
          allowed: Upload.allowed_content_types()
        })

      {:error, :invalid_upload_type} ->
        conn |> put_status(422) |> json(%{error: "type must be avatar, gallery, or attachment"})

      {:error, reason} ->
        conn |> put_status(500) |> json(%{error: "Could not generate upload URL: #{inspect(reason)}"})
    end
  end

  def presign(conn, _) do
    conn |> put_status(400) |> json(%{error: "type and content_type are required"})
  end
end