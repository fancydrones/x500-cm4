# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags?page=1&name=alpine - for the build image
#   - https://hub.docker.com/_/alpine?tab=tags&page=1&name=3.18.0 - for the release image
#   - https://pkgs.org/ - resource for finding needed packages
#   - Ex: hexpm/elixir:1.14.2-erlang-25.2-alpine-3.17.0
ARG ELIXIR_VERSION=1.15.4
ARG OTP_VERSION=25.3.2.5
ARG ALPINE_VERSION=3.18.2

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-alpine-${ALPINE_VERSION}"
ARG RUNNER_IMAGE="alpine:${ALPINE_VERSION}"

FROM ${BUILDER_IMAGE} as build

# install build dependencies
RUN apk update && apk add --no-cache build-base git linux-headers

# prepare build dir
WORKDIR /app

# set build ENV
ENV MIX_ENV="prod"

# https://github.com/erlang/otp/pull/6340
ENV ERL_AFLAGS="+JPperf true"

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# install mix dependencies
COPY mix.exs mix.lock ./
#RUN mix deps.get --force
RUN mix deps.get --only $MIX_ENV

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
RUN mkdir config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv

# note: if your project uses a tool like https://purgecss.com/,
# which customizes asset compilation based on what it finds in
# your Elixir templates, you will need to move the asset compilation
# step down so that `lib` is available.
COPY assets assets
# COPY protos protos

# compile assets
RUN mix assets.deploy

# Compile the release
COPY lib lib

RUN mix compile

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release


# prepare release image
FROM ${RUNNER_IMAGE} AS app
# set runner ENV
ENV MIX_ENV="prod"
RUN apk update && apk upgrade && apk add --no-cache openssl ncurses-libs bind-tools libstdc++ libgcc libssl1.1
WORKDIR /app
RUN chown nobody:nobody /app
USER nobody:nobody
COPY --from=build --chown=nobody:nobody /app/_build/prod/rel/companion ./
ENV HOME=/app
EXPOSE 4000
CMD ["bin/companion", "start"]
