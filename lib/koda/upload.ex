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
  # 8 MB -- matching Discord's free tier file size limit.
  @max_bytes 8 * 1024 * 1024
  # Presigned URLs expire after 5 minutes -- enough for any reasonable
  # upload on a consumer connection, short enough to limit abuse.
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
  @doc """
  Generates a presigned PUT URL for a direct upload to R2.
  Returns {:ok, %{upload_url, cdn_url, key}} or {:error, reason}.
  """
  def presign(user_id, upload_type, content_type) do
    with :ok <- validate_content_type(content_type),
         :ok <- validate_upload_type(upload_type) do
      key     = build_key(user_id, upload_type, content_type)
      cdn_url = "#{cdn_base()}/#{bucket()}/#{key}"

      case sign_r2_put(key, content_type) do
        {:ok, upload_url} ->
          {:ok, %{upload_url: upload_url, cdn_url: cdn_url, key: key}}
        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # Builds an AWS Signature V4 presigned PUT URL directly, giving us
  # full control over the host/path split that ex_aws_s3's virtual_host
  # option doesn't support cleanly for R2 custom domains.
  #
  # R2 custom domain signing rules:
  #   host   = cdn.koda.fyi  (custom domain, no bucket prefix)
  #   path   = /koda-images/<key>  (bucket name IS in path for cdn.koda.fyi)
  #   region = auto
  defp sign_r2_put(key, content_type) do
    cfg    = Application.get_env(:koda, :r2, [])
    ak     = cfg[:access_key_id]     || System.get_env("R2_ACCESS_KEY_ID")
    sk     = cfg[:secret_access_key] || System.get_env("R2_SECRET_ACCESS_KEY")
    host   = "cdn.koda.fyi"
    bkt    = bucket()
    path   = "/#{bkt}/#{key}"
    region = "auto"
    service = "s3"

    now      = DateTime.utc_now()
    date_str = Calendar.strftime(now, "%Y%m%d")
    dt_str   = Calendar.strftime(now, "%Y%m%dT%H%M%SZ")
    expires  = Integer.to_string(@expires_in)

    scope      = "#{date_str}/#{region}/#{service}/aws4_request"
    credential = "#{ak}/#{scope}"

    signed_headers = "content-type;host"

    query = URI.encode_query([
      {"X-Amz-Algorithm",     "AWS4-HMAC-SHA256"},
      {"X-Amz-Credential",    credential},
      {"X-Amz-Date",          dt_str},
      {"X-Amz-Expires",       expires},
      {"X-Amz-SignedHeaders", signed_headers},
    ])

    # Canonical request
    canonical = Enum.join([
      "PUT",
      path,
      query,
      "content-type:#{content_type}\nhost:#{host}\n",
      signed_headers,
      "UNSIGNED-PAYLOAD"
    ], "\n")

    string_to_sign = Enum.join([
      "AWS4-HMAC-SHA256",
      dt_str,
      scope,
      Base.encode16(:crypto.hash(:sha256, canonical), case: :lower)
    ], "\n")

    signing_key =
      hmac("AWS4#{sk}", date_str)
      |> hmac(region)
      |> hmac(service)
      |> hmac("aws4_request")

    signature = hmac(signing_key, string_to_sign) |> Base.encode16(case: :lower)

    upload_url = "https://#{host}#{path}?#{query}&X-Amz-Signature=#{signature}"
    {:ok, upload_url}
  end

  defp hmac(key, data) when is_binary(key) and is_binary(data) do
    :crypto.mac(:hmac, :sha256, key, data)
  end
  # -- Private -----------------------------------------------------------------
  defp validate_content_type(ct) do
    if ct in @allowed_content_types, do: :ok, else: {:error, :unsupported_content_type}
  end
  defp validate_upload_type(t) do
    if t in ["avatar", "gallery", "attachment"], do: :ok, else: {:error, :invalid_upload_type}
  end
  defp build_key(user_id, upload_type, content_type) do
    ext = ext_for(content_type)
    ts  = System.system_time(:millisecond)
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