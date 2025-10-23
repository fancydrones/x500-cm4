# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags?page=1&name=alpine - for the build image
#   - https://hub.docker.com/_/alpine?tab=tags&page=1&name=3.18.0 - for the release image
#   - https://pkgs.org/ - resource for finding needed packages
#   - Ex: hexpm/elixir:1.14.2-erlang-25.2-alpine-3.17.0
ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=28.1
ARG ALPINE_VERSION=3.22.1

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-alpine-${ALPINE_VERSION}"
ARG RUNNER_IMAGE="alpine:${ALPINE_VERSION}"

# Build stage
FROM ${BUILDER_IMAGE} AS builder

WORKDIR /app

# Install build dependencies
RUN apk update && apk add --no-cache build-base git linux-headers

# Install hex and rebar
RUN mix local.hex --force && mix local.rebar --force

# Copy dependency files
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy application files
COPY lib ./lib
COPY config ./config

# Compile and build release
ENV MIX_ENV=prod
RUN mix compile
RUN mix release

# Runtime stage
FROM ${RUNNER_IMAGE} AS app

# Install runtime dependencies including rpicam-vid and libcamera
# rpicam-apps provides rpicam-vid binary for camera access
# libcamera provides camera interface libraries
RUN apk add --no-cache \
    libstdc++ \
    openssl \
    ncurses-libs \
    libcamera \
    libcamera-ipa \
    rpicam-apps

WORKDIR /app

COPY --from=builder /app/_build/prod/rel/video_streamer ./

# RTSP port
EXPOSE 8554

CMD ["/app/bin/video_streamer", "start"]
