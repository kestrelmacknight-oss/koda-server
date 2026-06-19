import Config

# Production config is handled entirely by runtime.exs using environment
# variables. This file exists because config.exs imports it via
# import_config "#{config_env()}.exs" and Elixir requires it to be present.
#
# Do not put secrets here. Put them in runtime.exs and set them via:
#   fly secrets set KEY=VALUE --app koda-server

config :koda, KodaWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  server: true

config :logger, level: :info

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :user_id]
