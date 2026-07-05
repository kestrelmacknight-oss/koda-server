import Config

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise "DATABASE_URL is not set. fly secrets set DATABASE_URL=postgresql://..."

  config :koda, Koda.Repo,
    url:       database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    ssl:       true,
    ssl_opts:  [verify: :verify_none]

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "SECRET_KEY_BASE is not set. Generate: openssl rand -hex 64"

  config :koda, KodaWeb.Endpoint,
    url:    [host: "api.koda.fyi", port: 443, scheme: "https"],
    http:   [ip: {0, 0, 0, 0, 0, 0, 0, 0},
             port: String.to_integer(System.get_env("PORT") || "8080")],
    secret_key_base: secret_key_base,
    server: true,
    check_origin: ["https://koda.fyi", "https://www.koda.fyi"]

  config :koda, Koda.Auth.Guardian,
    issuer:     "koda",
    secret_key: System.get_env("GUARDIAN_SECRET_KEY") ||
      raise("GUARDIAN_SECRET_KEY not set. Generate: openssl rand -hex 32"),
    ttl: {30, :days}

  config :koda, Koda.Mailer,
    adapter: Swoosh.Adapters.Resend,
    api_key: System.get_env("RESEND_API_KEY") ||
      raise("RESEND_API_KEY not set")

  config :swoosh, :api_client, Swoosh.ApiClient.Finch

  config :koda, :email,
    from_name:    "Koda",
    from_address: "noreply@koda.fyi",
    support:      "support@koda.fyi",
    app_url:      "https://koda.fyi",
    terms_url:    "https://koda.fyi/terms.html",
    privacy_url:  "https://koda.fyi/privacy.html"

  scylla_nodes =
    System.get_env("SCYLLA_NODES", "koda-scylla.internal:9042")
    |> String.split(",")
    |> Enum.map(&String.trim/1)

  config :koda, :scylla,
    nodes:     scylla_nodes,
    keyspace:  "koda",
    pool_size: String.to_integer(System.get_env("SCYLLA_POOL_SIZE") || "20"),
    username:  System.get_env("SCYLLA_USERNAME"),
    password:  System.get_env("SCYLLA_PASSWORD")

  config :koda, :livekit,
    url:        System.get_env("LIVEKIT_URL",        "http://koda-livekit.internal:7880"),
    public_url: System.get_env("LIVEKIT_PUBLIC_URL", "wss://voice.koda.fyi"),
    api_key:    System.get_env("LIVEKIT_API_KEY")    || raise("LIVEKIT_API_KEY not set"),
    api_secret: System.get_env("LIVEKIT_API_SECRET") || raise("LIVEKIT_API_SECRET not set")

  config :koda, :r2,
    access_key_id:     System.get_env("R2_ACCESS_KEY_ID"),
    secret_access_key: System.get_env("R2_SECRET_ACCESS_KEY"),
    account_id:        System.get_env("R2_ACCOUNT_ID"),
    bucket:            System.get_env("R2_BUCKET")     || "koda-images",
    cdn_url:           System.get_env("R2_CDN_URL")    || "https://cdn.koda.fyi"

  config :cors_plug,
    origin:      ["https://koda.fyi", "https://www.koda.fyi"],
    max_age:     86_400,
    methods:     ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    headers:     ["Authorization", "Content-Type", "Accept", "X-App-Version"],
    credentials: true

  config :koda, Oban,
    engine:  Oban.Engines.Basic,
    repo:    Koda.Repo,
    queues:  [default: 10, email: 5, notifications: 20]

  config :logger, :console,
    format:   "$time $metadata[$level] $message\n",
    metadata: [:request_id, :user_id]
end