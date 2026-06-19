defmodule Koda.Release do
  @moduledoc """
  Release tasks that run against a deployed build via `/app/bin/koda eval`.

  These intentionally start ONLY the Ecto repo, never the full :koda
  application -- starting the full app would also try to bind the HTTP
  listener a second time, colliding with the already-running production
  instance and silently tearing the whole temporary boot back down.
  """

  @app :koda

  def migrate do
    load_app()
    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @admin_username "Kestrel_MacKnight"
  @admin_email    "Kestrel_MacKnight@koda.fyi"

  @doc """
  Deletes any existing admin account with @admin_username and recreates
  it fresh with @admin_email. Use this when you need a clean, known-good
  reset rather than troubleshooting an existing account.
  """
  def reset_admin do
    load_app()

    Ecto.Migrator.with_repo(Koda.Repo, fn _repo ->
      case Koda.Repo.get_by(Koda.Auth.User, username: @admin_username) do
        %Koda.Auth.User{} = existing ->
          Koda.Repo.delete!(existing)
          IO.puts("[Koda] Deleted existing account for #{@admin_username}.")
        nil ->
          IO.puts("[Koda] No existing account found for #{@admin_username}.")
      end

      create_admin_record()
    end)
  end

  @doc "Creates the admin account only if it does not already exist."
  def create_admin do
    load_app()

    Ecto.Migrator.with_repo(Koda.Repo, fn _repo ->
      case Koda.Repo.get_by(Koda.Auth.User, username: @admin_username) do
        %Koda.Auth.User{} ->
          IO.puts("[Koda] Account '#{@admin_username}' already exists. No changes made.")
          IO.puts("[Koda] Run Koda.Release.reset_admin() instead to force a clean reset.")
        nil ->
          create_admin_record()
      end
    end)
  end

  defp create_admin_record do
    IO.puts("\n[Koda] Creating admin account for #{@admin_username}...")
    temp_password = generate_password()

    attrs = %{
      username:              @admin_username,
      email:                 @admin_email,
      password:              temp_password,
      password_confirmation: temp_password,
      is_admin:              true,
      must_change_password:  true,
      email_verified:        true
    }

    case Koda.Auth.create_user(attrs) do
      {:ok, _user} ->
        IO.puts("""

        +-----------------------------------------------------+
        |      KODA ADMIN ACCOUNT CREATED SUCCESSFULLY        |
        +-----------------------------------------------------+
        |                                                     |
        |  Username : #{String.pad_trailing(@admin_username, 39)}|
        |  Email    : #{String.pad_trailing(@admin_email, 39)}|
        |  Password : #{String.pad_trailing(temp_password, 39)}|
        |                                                     |
        |  Must change password on first login.               |
        |  Copy ONLY the password text -- no trailing spaces.  |
        |                                                     |
        +-----------------------------------------------------+
        """)

      {:error, changeset} ->
        IO.puts("\n[Koda] Failed to create admin account:")
        changeset.errors |> Enum.each(fn {field, {msg, _}} ->
          IO.puts("  #{field}: #{msg}")
        end)
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

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
