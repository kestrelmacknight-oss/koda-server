defmodule Koda.Upload do
  @moduledoc """
  Generates presigned PUT URLs for direct client-to-R2 uploads.
  Flow:
    1. Client POSTs to /api/v1/uploads/presign with {type, content_type}
    2. Phoenix returns {upload_url, cdn_url, key}
    3. Client PUTs the file directly to upload_url (no server bandwidth)
    4. Client uses cdn_url as the final media URL in subsequent requests
  type is one of: "avatar" | "gallery" | "attachment"
  """
  @max_bytes 8 * 1024 * 1024
  @expires_in 300
  @allowed_content_types ~w(
    image/jpeg image/png image/gif image/webp
    image/svg+xml image/avif
    video/mp4 video/webm video/quicktime
    audio/mpeg audio/ogg audio/wav audio/webm
    application/pdf
  )

  def allowed_content_types, do: @allowed_content_types
  def max_bytes, do: @max_bytes

  def presign(user_id, upload_type, content_type) do
    with :ok <- validate_content_type(content_type),
         :ok <- validate_upload_type(upload_type) do
      key     = build_key(user_id, upload_type, content_type)
      cdn_url = "#{cdn_base()}/#{bucket()}/#{key}"
      config  = ex_aws_config()

      url =
        ExAws.S3.presigned_url(
          config,
          :put,
          bucket(),
          key,
          expires_in: @expires_in,
          headers: [{"content-type", content_type}]
        )

      case url do
        {:ok, upload_url} ->
          {:ok, %{upload_url: upload_url, cdn_url: cdn_url, key: key}}
        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp validate_content_type(ct) do
    if ct in @allowed_content_types, do: :ok, else: {:error, :unsupported_content_type}
  end

  defp validate_upload_type(t) do
    if t in ["avatar", "gallery", "attachment"], do: :ok, else: {:error, :invalid_upload_type}
  end

  defp build_key(user_id, upload_type, content_type) do
    ext  = ext_for(content_type)
    ts   = System.system_time(:millisecond)
    rand = :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
    "#{upload_type}/#{user_id}/#{ts}-#{rand}#{ext}"
  end

  defp ext_for(ct) do
    case ct do
      "image/jpeg"       -> ".jpg"
      "image/png"        -> ".png"
      "image/gif"        -> ".gif"
      "image/webp"       -> ".webp"
      "image/avif"       -> ".avif"
      "image/svg+xml"    -> ".svg"
      "video/mp4"        -> ".mp4"
      "video/webm"       -> ".webm"
      "video/quicktime"  -> ".mov"
      "audio/mpeg"       -> ".mp3"
      "audio/ogg"        -> ".ogg"
      "audio/wav"        -> ".wav"
      "audio/webm"       -> ".weba"
      "application/pdf"  -> ".pdf"
      _                  -> ""
    end
  end

  defp ex_aws_config do
    cfg = Application.get_env(:koda, :r2, [])
    ExAws.Config.new(:s3,
      access_key_id:     cfg[:access_key_id]     || System.get_env("R2_ACCESS_KEY_ID"),
      secret_access_key: cfg[:secret_access_key] || System.get_env("R2_SECRET_ACCESS_KEY"),
      region:            "auto",
      host:              "#{cfg[:account_id] || System.get_env("R2_ACCOUNT_ID")}.r2.cloudflarestorage.com",
      scheme:            "https://"
    )
  end

  defp bucket do
    cfg = Application.get_env(:koda, :r2, [])
    cfg[:bucket] || System.get_env("R2_BUCKET") || "koda-images"
  end

  defp cdn_base do
    cfg = Application.get_env(:koda, :r2, [])
    cdn = cfg[:cdn_url] || System.get_env("R2_CDN_URL") || "https://cdn.koda.fyi"
    String.trim_trailing(cdn, "/")
  end
end