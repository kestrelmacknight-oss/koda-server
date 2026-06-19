defmodule KodaWeb.AuthController do
  use KodaWeb, :controller
  alias Koda.Auth

  def register(conn, params) do
    case Auth.create_user(params) do
      {:ok, user} ->
        Auth.send_verification_email(user)
        json(conn, %{
          message: "Account created. Check your email for a verification code.",
          user_id: user.id
        })

      {:error, changeset} ->
        conn |> put_status(422) |> json(%{errors: format_errors(changeset)})
    end
  end

  def login(conn, %{"email" => email, "password" => password}) do
    case Auth.login(email, password) do
      {:ok, %{token: token, user: user, must_change_password: mcp}} ->
        json(conn, %{
          token:                token,
          must_change_password: mcp,
          user:                 user_json(user)
        })

      {:error, :invalid_credentials} ->
        conn |> put_status(401) |> json(%{error: "Invalid email or password"})
    end
  end

  def logout(conn, _) do
    token = conn |> get_req_header("authorization") |> List.first("")
            |> String.replace_prefix("Bearer ", "")
    Auth.logout(token)
    json(conn, %{ok: true})
  end

  def me(conn, _) do
    user = Guardian.Plug.current_resource(conn)
    json(conn, %{user: user_json(user)})
  end

  def force_change_password(conn, %{"password" => pw, "password_confirmation" => pc}) do
    user = Guardian.Plug.current_resource(conn)

    unless user.must_change_password do
      conn |> put_status(422) |> json(%{error: "Password change not required"})
    else
      case Auth.force_change_password(user, pw, pc) do
        {:ok, %{token: token, user: updated}} ->
          json(conn, %{
            token:                token,
            must_change_password: false,
            user:                 user_json(updated)
          })

        {:error, changeset} ->
          conn |> put_status(422) |> json(%{errors: format_errors(changeset)})
      end
    end
  end

  def verify_email(conn, %{"code" => code}) do
    user = Guardian.Plug.current_resource(conn)
    case Auth.verify_email(user.id, code) do
      {:ok, _} ->
        Koda.Email.send_welcome(user)
        json(conn, %{message: "Email verified"})
      {:error, :invalid_or_expired_code} ->
        conn |> put_status(422) |> json(%{error: "Invalid or expired code"})
    end
  end

  def resend_verification(conn, _) do
    user = Guardian.Plug.current_resource(conn)
    Auth.send_verification_email(user)
    json(conn, %{message: "Verification email sent"})
  end

  def request_password_reset(conn, %{"email" => email}) do
    Auth.request_password_reset(email)
    json(conn, %{message: "If that account exists, a reset code has been sent"})
  end

  def confirm_password_reset(conn, %{"email" => e, "code" => c, "new_password" => p}) do
    case Auth.confirm_password_reset(e, c, p) do
      {:ok, _}  -> json(conn, %{message: "Password updated"})
      {:error, _} -> conn |> put_status(422) |> json(%{error: "Invalid or expired code"})
    end
  end

  def totp_setup(conn, _) do
    user = Guardian.Plug.current_resource(conn)
    case Auth.generate_totp_secret(user) do
      {:ok, %{secret: s, uri: u}} -> json(conn, %{secret: s, uri: u})
      {:error, _} -> conn |> put_status(500) |> json(%{error: "Could not generate TOTP"})
    end
  end

  def totp_verify(conn, %{"code" => code}) do
    user = Guardian.Plug.current_resource(conn)
    case Auth.verify_and_enable_totp(user, code) do
      {:ok, _}  -> json(conn, %{enabled: true})
      {:error, _} -> conn |> put_status(422) |> json(%{error: "Invalid code"})
    end
  end

  def get_keys(conn, _), do: json(conn, %{keys: []})
  def upload_keys(conn, _), do: json(conn, %{ok: true})
  def get_user_keys(conn, _), do: json(conn, %{keys: []})

  defp user_json(u) do
    %{id: u.id, username: u.username, email: u.email,
      display_name: u.display_name, avatar_url: u.avatar_url,
      is_admin: u.is_admin, email_verified: u.email_verified}
  end

  defp format_errors(cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, k ->
        opts |> Keyword.get(String.to_existing_atom(k), k) |> to_string()
      end)
    end)
  end
end
