defmodule KodaWeb.GiphyController do
  use KodaWeb, :controller
  alias Koda.Giphy

  def search(conn, %{"q" => query}) when byte_size(query) > 0 do
    respond(conn, Giphy.search(query))
  end
  def search(conn, _params), do: respond(conn, Giphy.trending())

  def trending(conn, _params), do: respond(conn, Giphy.trending())

  defp respond(conn, {:ok, gifs}), do: json(conn, %{gifs: gifs})
  defp respond(conn, {:error, :not_configured}),
    do: conn |> put_status(503) |> json(%{error: "GIF search is not configured"})
  defp respond(conn, {:error, _}),
    do: conn |> put_status(502) |> json(%{error: "GIF search failed"})
end
