defmodule Koda.MixProject do
  use Mix.Project

  def project do
    [
      app:             :koda,
      version:         "0.34.0",
      elixir:          "~> 1.16",
      elixirc_paths:   elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases:         aliases(),
      deps:            deps(),
      releases:        releases()
    ]
  end

  def application do
    [
      mod:                {Koda.Application, []},
      extra_applications: [:logger, :runtime_tools, :crypto]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_),     do: ["lib"]

  defp deps do
    [
      # Phoenix
      {:phoenix,             "~> 1.7.14"},
      {:phoenix_ecto,        "~> 4.6"},
      {:ecto_sql,            "~> 3.12"},
      {:postgrex,            ">= 0.0.0"},
      {:bandit,              "~> 1.5"},
      {:gettext,             "~> 0.26"},
      {:jason,               "~> 1.4"},
      {:dns_cluster,         "~> 0.1.3"},
      {:telemetry_metrics,   "~> 1.0"},
      {:telemetry_poller,    "~> 1.1"},
      # Auth -- Guardian 2.x includes Guardian.Phoenix.Socket built in.
      # No separate guardian_phoenix package needed or available.
      {:guardian,            "~> 2.3"},
      {:guardian_db,         "~> 3.0"},
      {:bcrypt_elixir,       "~> 3.2"},
      # HTTP client
      {:req,                 "~> 0.5"},
      {:finch,               "~> 0.18"},
      # Email
      {:swoosh,              "~> 1.17"},
      # CORS
      {:cors_plug,           "~> 3.0"},
      # Background jobs
      {:oban,                "~> 2.18"},
      # ScyllaDB / Cassandra
      {:xandra,              "~> 0.18"},
      # UUID generation (TimeUUID for ScyllaDB)
      {:uuid,                "~> 1.1"},
      # Rate limiting
      {:hammer,              "~> 6.2"},
      # Dev only
      {:phoenix_live_dashboard, "~> 0.8", only: :dev},
    ]
  end

  defp releases do
    [
      koda: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent],
        steps: [:assemble]
      ]
    ]
  end

  defp aliases do
    [
      setup:        ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test:         ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
