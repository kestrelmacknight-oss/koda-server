import Config

config :koda, Koda.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "koda_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :koda, KodaWeb.Endpoint,
  http:        [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_secret_key_base_at_least_64_bytes_long_replace_in_production_!!",
  watchers: []

config :koda, :scylla,
  nodes:     ["localhost:9042"],
  keyspace:  "koda",
  pool_size: 5

config :logger, level: :debug
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
