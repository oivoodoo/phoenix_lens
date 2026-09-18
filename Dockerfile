# Find eligible builder and runner images on Docker Hub.
# We use Debian instead of Alpine to avoid DNS and NIF issues in production.
# Source: https://hexdocs.pm/phoenix/releases.html
#
#   - https://hub.docker.com/r/hexpm/elixir/tags
#   - https://hub.docker.com/_/debian?tab=tags
#
ARG ELIXIR_VERSION=1.17.3
ARG OTP_VERSION=27.2.4
ARG DEBIAN_VERSION=bookworm-20260824-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force \
  && mix local.rebar --force

ENV MIX_ENV="prod"

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib

RUN mix compile

COPY config/runtime.exs config/
COPY rel rel
RUN chmod +x rel/overlays/bin/server
RUN mix release

FROM ${RUNNER_IMAGE} AS final

RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates \
  && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

ENV MIX_ENV="prod"
ENV PORT=8080
ENV PHX_SERVER=true
ENV PHOENIX_LENS_SERVER=true

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/phoenix_lens ./

USER nobody

EXPOSE 8080

CMD ["/app/bin/server"]
