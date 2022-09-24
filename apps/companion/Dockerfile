#FROM bitwalker/alpine-elixir:1.14 as build
FROM elixir:1.13-alpine as build

# install build dependencies
RUN apk update && apk add --no-cache build-base git linux-headers

# prepare build dir
WORKDIR /app

# set build ENV
ENV MIX_ENV="prod"

# install hex + rebar
RUN mix do local.hex --force, local.rebar --force

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
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
FROM alpine:latest AS app
RUN apk update && apk add --no-cache openssl ncurses-libs bind-tools
WORKDIR /app
RUN chown nobody:nobody /app
USER nobody:nobody
COPY --from=build --chown=nobody:nobody /app/_build/prod/rel/companion ./
ENV HOME=/app
EXPOSE 4000
CMD ["bin/companion", "start"]
