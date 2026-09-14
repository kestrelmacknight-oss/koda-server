defmodule Koda.Printful do
  @moduledoc """
  Per-server Printful OAuth connection for merch fulfillment -- mirrors
  Koda.Marketplace's Stripe Connect shape (each server owner connects
  their own account), with one real difference: Printful's OAuth hands
  us a genuine bearer access token for the connected store, which we
  have to store and use ourselves. Stripe Connect never works this way
  (API calls go through our own platform key with a Stripe-Account
  header instead) -- so unlike a Stripe account id, this access token is
  exactly as sensitive as any other credential. Never log it, never
  return it to the client.

  Endpoint/param names below are Printful's actual documented OAuth2
  flow (https://developers.printful.com/docs/): note the authorize
  param is `redirect_url`, not the more common `redirect_uri`.
  """
  import Ecto.Query
  require Logger
  alias Koda.Repo

  @authorize_url "https://www.printful.com/oauth/authorize"
  @token_url "https://www.printful.com/oauth/token"
  @redirect_url "https://api.koda.fyi/api/v1/printful/oauth/callback"

  defmodule Connection do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "printful_connections" do
      field :access_token,     :string
      field :refresh_token,    :string
      field :token_expires_at, :utc_datetime_usec
      belongs_to :server,      Koda.Servers.Server
      belongs_to :connected_by, Koda.Auth.User
      timestamps(type: :utc_datetime_usec)
    end

    def changeset(c, attrs) do
      c
      |> cast(attrs, [:server_id, :connected_by_id, :access_token, :refresh_token, :token_expires_at])
      |> validate_required([:server_id, :access_token])
      |> unique_constraint(:server_id)
    end
  end

  @doc """
  Builds the consent-screen URL to send a server owner to. `state` is a
  signed, time-limited Phoenix.Token (not a DB row) carrying which
  server/user initiated the connection, verified back in
  handle_callback/2 -- this also doubles as OAuth's CSRF protection.
  """
  def authorize_url(server_id, user_id) do
    client_id = Application.get_env(:koda, :printful, [])[:client_id]
    state = Phoenix.Token.sign(KodaWeb.Endpoint, "printful_oauth",
      %{server_id: server_id, user_id: user_id})

    query = URI.encode_query(%{
      "client_id"    => client_id,
      "redirect_url" => @redirect_url,
      "state"        => state
    })
    "#{@authorize_url}?#{query}"
  end

  @doc """
  Completes the OAuth handshake after Printful redirects back: verifies
  `state`, exchanges `code` for tokens, and upserts the connection for
  the server named in the state.
  """
  def handle_callback(code, state) do
    with {:ok, %{server_id: server_id, user_id: user_id}} <-
           Phoenix.Token.verify(KodaWeb.Endpoint, "printful_oauth", state, max_age: 600),
         {:ok, tokens} <- exchange_code(code) do
      upsert_connection(server_id, user_id, tokens)
    else
      {:error, :expired} -> {:error, :state_expired}
      {:error, :invalid} -> {:error, :invalid_state}
      other -> other
    end
  end

  defp exchange_code(code) do
    cfg = Application.get_env(:koda, :printful, [])

    case Req.post(@token_url,
           form: [
             grant_type:    "authorization_code",
             client_id:     cfg[:client_id],
             client_secret: cfg[:client_secret],
             code:          code
           ],
           receive_timeout: 10_000) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("[Printful] token exchange failed: #{status} #{inspect(body)}")
        {:error, :upstream_error}

      {:error, reason} ->
        Logger.error("[Printful] token exchange error: #{inspect(reason)}")
        {:error, :upstream_error}
    end
  end

  defp upsert_connection(server_id, user_id, tokens) do
    attrs = %{
      "server_id"        => server_id,
      "connected_by_id"  => user_id,
      "access_token"     => tokens["access_token"],
      "refresh_token"    => tokens["refresh_token"],
      "token_expires_at" => parse_expiry(tokens["expires_at"])
    }

    (get_connection(server_id) || %Connection{})
    |> Connection.changeset(attrs)
    |> Repo.insert_or_update()
  end

  # Printful documents expires_at as "a timestamp" without pinning down
  # the exact wire format -- handle both a raw unix integer and an
  # ISO8601 string rather than assuming.
  defp parse_expiry(nil), do: nil
  defp parse_expiry(unix) when is_integer(unix), do: DateTime.from_unix!(unix)
  defp parse_expiry(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ ->
        case Integer.parse(str) do
          {unix, _} -> DateTime.from_unix!(unix)
          :error    -> nil
        end
    end
  end

  def get_connection(server_id), do: Repo.get_by(Connection, server_id: server_id)
  def connected?(server_id), do: get_connection(server_id) != nil

  def disconnect(server_id) do
    Repo.delete_all(from c in Connection, where: c.server_id == ^server_id)
    :ok
  end
end
