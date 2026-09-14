defmodule Koda.Giphy do
  @moduledoc """
  Thin server-side proxy to Giphy's search/trending APIs.

  This exists purely to keep the Giphy API key off the client -- a
  Flutter binary is trivially decompiled, so any key baked into it is
  effectively public. The server holds the key and the client only ever
  talks to our own /gifs endpoints.
  """
  require Logger

  @base_url "https://api.giphy.com/v1/gifs"

  def search(query, limit \\ 24) do
    request("/search", q: query, limit: limit)
  end

  def trending(limit \\ 24) do
    request("/trending", limit: limit)
  end

  defp request(path, params) do
    api_key = Application.get_env(:koda, :giphy, [])[:api_key]

    if is_nil(api_key) or api_key == "" do
      {:error, :not_configured}
    else
      case Req.get("#{@base_url}#{path}",
             params: Keyword.merge(params, api_key: api_key, rating: "pg-13"),
             receive_timeout: 5_000) do
        {:ok, %{status: 200, body: %{"data" => data}}} -> {:ok, Enum.map(data, &gif_json/1)}
        {:ok, %{status: status, body: body}} ->
          Logger.warning("[Giphy] request failed: #{status} #{inspect(body)}")
          {:error, :upstream_error}
        {:error, reason} ->
          Logger.error("[Giphy] request error: #{inspect(reason)}")
          {:error, :upstream_error}
      end
    end
  end

  defp gif_json(g) do
    images = g["images"] || %{}
    fixed  = images["fixed_width"] || %{}
    orig   = images["original"] || %{}
    %{
      id:         g["id"],
      title:      g["title"],
      url:        orig["url"] || fixed["url"],
      preview_url: fixed["url"] || orig["url"],
      width:      to_int(fixed["width"]),
      height:     to_int(fixed["height"])
    }
  end

  defp to_int(nil), do: nil
  defp to_int(s) when is_binary(s), do: String.to_integer(s)
  defp to_int(n) when is_integer(n), do: n
end
