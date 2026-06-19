defmodule Mix.Tasks.Koda.CreateAdmin do
  @moduledoc """
  Creates the initial platform admin account.

  Run on Fly.io after deployment:
    fly ssh console --app koda-server \\
      --command "/app/bin/koda eval 'Mix.Tasks.Koda.CreateAdmin.run([])'"
  """
  use Mix.Task

  @username "Kestrel_MacKnight"
  @email    "admin@koda.fyi"

  def run(_args) do
    Application.ensure_all_started(:koda)

    IO.puts("\n[Koda] Creating admin account for #{@username}...")

    case Koda.Repo.get_by(Koda.Auth.User, username: @username) do
      %Koda.Auth.User{} ->
        IO.puts("[Koda] Account '#{@username}' already exists.")

      nil ->
        temp_password = generate_password()

        case Koda.Auth.create_user(%{
          username:             @username,
          email:                @email,
          password:             temp_password,
          password_confirmation: temp_password,
          is_admin:             true,
          must_change_password: true,
          email_verified:       true
        }) do
          {:ok, _user} ->
            IO.puts("""

            +===================================================+
            |      KODA ADMIN ACCOUNT CREATED SUCCESSFULLY      |
            +===================================================+
            |                                                   |
            |  Username : #{String.pad_trailing(@username, 37)}|
            |  Email    : #{String.pad_trailing(@email, 37)}|
            |  Password : #{String.pad_trailing(temp_password, 37)}|
            |                                                   |
            |  Must change password on first login.             |
            |  Copy this now -- it will NOT be shown again.      |
            |                                                   |
            +===================================================+
            """)

          {:error, changeset} ->
            IO.puts("\n[Koda] Failed:")
            changeset.errors |> Enum.each(fn {f, {msg, _}} ->
              IO.puts("  #{f}: #{msg}")
            end)
        end
    end
  end

  defp generate_password do
    upper  = random_chars("ABCDEFGHJKLMNPQRSTUVWXYZ", 4)
    lower  = random_chars("abcdefghjkmnpqrstuvwxyz", 4)
    digits = random_chars("23456789", 4)
    extra  = random_chars("23456789", 4)
    "#{upper}-#{lower}-#{digits}-#{extra}"
  end

  defp random_chars(chars, n) do
    list = String.graphemes(chars)
    Enum.map_join(1..n, "", fn _ -> Enum.random(list) end)
  end
end
