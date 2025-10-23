# Multi-stage build for video_streamer with rpicam-apps
#
# Stage 1: Build Elixir release
# Stage 2: Runtime image with rpicam-apps from edge/testing
#
# Note: Using Alpine edge for runtime to avoid dependency conflicts with rpicam-apps

ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=28.1
ARG ALPINE_VERSION=3.22.1

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-alpine-${ALPINE_VERSION}"
ARG RUNNER_IMAGE="alpine:edge"

# Stage 1: Build Elixir app
FROM ${BUILDER_IMAGE} AS elixir-builder

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

# Stage 2: Runtime
FROM ${RUNNER_IMAGE} AS app

# Enable testing repository for rpicam-apps and update package index
RUN echo "@testing https://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories && \
    apk update

# Install runtime dependencies including rpicam-apps from testing
RUN apk add --no-cache \
    libstdc++ \
    openssl \
    ncurses-libs \
    libcamera \
    libcamera-ipa \
    rpicam-apps@testing

WORKDIR /app

# Copy Elixir release
COPY --from=elixir-builder /app/_build/prod/rel/video_streamer ./

# RTSP port
EXPOSE 8554

CMD ["/app/bin/video_streamer", "start"]
