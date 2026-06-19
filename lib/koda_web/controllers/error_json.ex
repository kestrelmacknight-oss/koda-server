defmodule KodaWeb.ErrorJSON do
  def render("404.json", _), do: %{error: "Not found"}
  def render("401.json", _), do: %{error: "Unauthorized"}
  def render("422.json", %{changeset: cs}), do: %{errors: format_errors(cs)}
  def render(template, _), do: %{error: Phoenix.Controller.status_message_from_template(template)}

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
