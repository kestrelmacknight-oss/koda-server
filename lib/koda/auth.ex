defmodule Koda.Auth do
  @moduledoc "Authentication context -- register, login, password management, TOTP, verification."

  import Ecto.Query
  import Bitwise

  alias Koda.Repo
  alias Koda.Auth.{User, Guardian}
  alias Koda.Email

  # -- Registration ---------------------------------------------------------

  def create_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  # -- Login -----------------------------------------------------------------

  def login(email, password) do
    user = Repo.get_by(User, email: String.downcase(email))

    cond do
      is_nil(user) ->
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}

      not User.valid_password?(user, password) ->
        {:error, :invalid_credentials}

      user.must_change_password ->
        {:ok, token, _} = Guardian.encode_and_sign(user,
          %{"typ" => "restricted"}, ttl: {30, :minutes})
        {:ok, %{token: token, user: user, must_change_password: true}}

      true ->
        {:ok, token, _} = Guardian.encode_and_sign(user)
        {:ok, %{token: token, user: user, must_change_password: false}}
    end
  end

  def logout(token) do
    Guardian.DB.Token.revoke(token)
  end

  # -- Force password change -------------------------------------------------

  def force_change_password(user, password, password_confirmation) do
    changeset = User.password_changeset(user, %{
      password:              password,
      password_confirmation: password_confirmation
    })

    case Repo.update(changeset) do
      {:ok, updated_user} ->
        {:ok, token, _} = Guardian.encode_and_sign(updated_user)
        {:ok, %{token: token, user: updated_user, must_change_password: false}}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  # -- Email verification -----------------------------------------------------

  def send_verification_email(user) do
    code       = generate_code()
    expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)

    Repo.insert!(%Koda.Auth.VerificationCode{
      user_id:    user.id,
      code:       code,
      type:       "email_verification",
      expires_at: expires_at
    })

    Email.send_verification(user, code)
    :ok
  end

  def verify_email(user_id, code) do
    now = DateTime.utc_now()

    result = Repo.one(
      from v in Koda.Auth.VerificationCode,
      where: v.user_id    == ^user_id
         and v.code       == ^code
         and v.type       == "email_verification"
         and v.used       == false
         and v.expires_at > ^now
    )

    case result do
      nil ->
        {:error, :invalid_or_expired_code}

      code_record ->
        Repo.update!(Ecto.Changeset.change(code_record, used: true))
        user = Repo.get!(User, user_id)
        user |> User.update_changeset(%{email_verified: true}) |> Repo.update()
    end
  end

  # -- Password reset ---------------------------------------------------------

  def request_password_reset(email) do
    case Repo.get_by(User, email: String.downcase(email)) do
      nil  -> :ok
      user ->
        code       = generate_code()
        expires_at = DateTime.add(DateTime.utc_now(), 900, :second)

        Repo.insert!(%Koda.Auth.VerificationCode{
          user_id:    user.id,
          code:       code,
          type:       "password_reset",
          expires_at: expires_at
        })

        Email.send_password_reset(user, code)
    end
    :ok
  end

  def confirm_password_reset(email, code, new_password) do
    now  = DateTime.utc_now()
    user = Repo.get_by(User, email: String.downcase(email))

    with %User{} <- user,
         %Koda.Auth.VerificationCode{} = record <- Repo.one(
           from v in Koda.Auth.VerificationCode,
           where: v.user_id    == ^user.id
              and v.code       == ^code
              and v.type       == "password_reset"
              and v.used       == false
              and v.expires_at > ^now
         ) do
      Repo.update!(Ecto.Changeset.change(record, used: true))
      user
      |> User.password_changeset(%{
           password:              new_password,
           password_confirmation: new_password
         })
      |> Repo.update()
    else
      _ -> {:error, :invalid_or_expired_code}
    end
  end

  # -- TOTP ------------------------------------------------------------------

  def generate_totp_secret(user) do
    secret = :crypto.strong_rand_bytes(20) |> Base.encode32(padding: false)
    uri    = "otpauth://totp/Koda:#{user.email}?secret=#{secret}&issuer=Koda"

    user
    |> User.totp_changeset(%{totp_secret: secret})
    |> Repo.update()

    {:ok, %{secret: secret, uri: uri}}
  end

  def verify_and_enable_totp(user, code) do
    if verify_totp_code(user.totp_secret, code) do
      user |> User.totp_changeset(%{totp_enabled: true}) |> Repo.update()
    else
      {:error, :invalid_totp_code}
    end
  end

  def verify_totp(%User{totp_secret: secret}, code) when is_binary(secret) do
    verify_totp_code(secret, code)
  end

  def verify_totp(_, _), do: false

  # -- User lookup ------------------------------------------------------------

  def get_user(id),                   do: Repo.get(User, id)
  def get_user_by_email(email),       do: Repo.get_by(User, email: String.downcase(email))
  def get_user_by_username(username), do: Repo.get_by(User, username: username)
  def admin?(%User{is_admin: true}),  do: true
  def admin?(_),                      do: false

  # -- Private ----------------------------------------------------------------

  defp generate_code do
    :crypto.strong_rand_bytes(3)
    |> :binary.decode_unsigned()
    |> rem(1_000_000)
    |> Integer.to_string()
    |> String.pad_leading(6, "0")
  end

  defp verify_totp_code(secret, code) do
    # RFC 6238 TOTP -- 30-second window, allow +/-1 step for clock drift
    now   = System.system_time(:second)
    steps = [div(now, 30) - 1, div(now, 30), div(now, 30) + 1]

    key = Base.decode32!(secret, padding: false)

    Enum.any?(steps, fn step ->
      # HMAC-SHA1 of the 8-byte big-endian step counter
      msg      = <<step::big-unsigned-integer-size(64)>>
      hmac     = :crypto.mac(:hmac, :sha, key, msg)

      # Dynamic truncation per RFC 4226
      offset   = :binary.at(hmac, 19) &&& 0x0F
      <<_::bits-size(32)>> = binary_part(hmac, offset, 4)
      raw      = hmac
                 |> binary_part(offset, 4)
                 |> :binary.decode_unsigned(:big)
      token    = (raw &&& 0x7FFFFFFF)
                 |> rem(1_000_000)
                 |> Integer.to_string()
                 |> String.pad_leading(6, "0")

      Plug.Crypto.secure_compare(token, code)
    end)
  end
end
