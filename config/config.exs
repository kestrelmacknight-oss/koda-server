import Config

config :koda,
  ecto_repos: [Koda.Repo],
  env:        config_env(),
  generators: [timestamp_type: :utc_datetime]

config :koda, KodaWeb.Endpoint,
  url:           [host: "localhost"],
  adapter:       Bandit.PhoenixAdapter,
  render_errors: [formats: [json: KodaWeb.ErrorJSON], layout: false],
  pubsub_server: Koda.PubSub,
  live_view:     [signing_salt: "koda_lv_salt"]

config :koda, Koda.Mailer, adapter: Swoosh.Adapters.Local

config :swoosh, :api_client, false

config :koda, Koda.Auth.Guardian,
  issuer:     "koda",
  secret_key: "dev_secret_replace_in_production",
  ttl:        {30, :days}

config :guardian, Guardian.DB,
  repo:           Koda.Repo,
  schema_name:    "guardian_tokens",
  sweep_interval: 60

config :koda, :email,
  from_name:    "Koda",
  from_address: "noreply@koda.fyi",
  support:      "support@koda.fyi",
  app_url:      "https://koda.fyi",
  terms_url:    "https://koda.fyi/terms.html",
  privacy_url:  "https://koda.fyi/privacy.html"

config :koda, :scylla,
  nodes:     ["localhost:9042"],
  keyspace:  "koda",
  pool_size: 5

config :koda, :livekit,
  url:        "http://localhost:7880",
  public_url: "ws://localhost:7880",
  api_key:    "devkey",
  api_secret: "devsecret"

config :cors_plug,
  origin:      ["https://koda.fyi", "https://www.koda.fyi"],
  max_age:     86_400,
  methods:     ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
  headers:     ["Authorization", "Content-Type", "Accept", "X-App-Version"],
  credentials: true

config :koda, Oban,
  engine: Oban.Engines.Basic,
  repo:   Koda.Repo,
  queues: [default: 10, email: 5, notifications: 20]

config :hammer,
  backend: {Hammer.Backend.ETS,
    [expiry_ms: 60_000 * 60 * 4, cleanup_interval_ms: 60_000 * 10]}

config :logger, :console,
  format:   "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
