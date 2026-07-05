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
      # Auth
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
      {:xandra,              ">= 0.18.0"},
      # UUID generation (TimeUUID for ScyllaDB)
      {:uuid,                "~> 1.1"},
      # Rate limiting
      {:hammer,              "~> 6.2"},
      # R2 / S3-compatible presigned URL generation.
      # ex_aws_s3 handles the AWS Signature V4 signing that R2 requires.
      # hackney is the HTTP adapter ex_aws uses internally.
      {:ex_aws,              "~> 2.5"},
      {:ex_aws_s3,           "~> 2.5"},
      {:hackney,             "~> 1.20"},
      {:sweet_xml,           "~> 0.7"},
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