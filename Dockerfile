FROM hexpm/elixir:1.16.3-erlang-26.2.5-debian-bookworm-20240612-slim AS build

RUN apt-get update -y && \
    apt-get install -y build-essential git curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

# Copy mix.exs only -- mix.lock is generated during build
# (no local mix.lock exists because mix deps.get has not been run locally)
COPY mix.exs ./
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy the rest of the source
COPY config/ ./config/
COPY priv/ ./priv/
COPY rel/ ./rel/
COPY lib/ ./lib/

RUN mix compile
RUN mix release

# ── Runtime image ─────────────────────────────────────────────────────────────
FROM debian:bookworm-slim AS runtime

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app
RUN chown nobody /app

COPY --from=build --chown=nobody:root /app/_build/prod/rel/koda ./
COPY --chown=nobody:root rel/inetrc /app/inetrc

USER nobody

CMD ["/app/bin/koda", "start"]