# Multi-stage Dockerfile for router-ex
#
# This file is based on these images:
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the build image
#   - https://hub.docker.com/_/alpine - for the release image
#
# Build arguments for version control
ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=28.1.1
ARG ALPINE_VERSION=3.22.2

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-alpine-${ALPINE_VERSION}"
ARG RUNNER_IMAGE="alpine:${ALPINE_VERSION}"

# ============================================================================
# Build stage
# ============================================================================
FROM ${BUILDER_IMAGE} AS builder

WORKDIR /app

# Install build dependencies
# - build-base: gcc, g++, make (required for NIFs like circuits_uart)
# - git: required for fetching git dependencies
# - linux-headers: required for compiling native extensions
RUN apk update && apk add --no-cache \
    build-base \
    git \
    linux-headers

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy dependency files first (for better layer caching)
COPY mix.exs mix.lock ./

# Fetch and compile dependencies (production only)
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy application source code
COPY lib ./lib
COPY config ./config

# Compile application and build release
ENV MIX_ENV=prod
RUN mix compile
RUN mix release

# ============================================================================
# Runtime stage
# ============================================================================
FROM ${RUNNER_IMAGE} AS app

# Install runtime dependencies
# - libstdc++: C++ standard library (required by some NIFs)
# - openssl: SSL/TLS support
# - ncurses-libs: Terminal handling (required by BEAM)
RUN apk add --no-cache \
    libstdc++ \
    openssl \
    ncurses-libs

WORKDIR /app

# Copy the release from builder stage
COPY --from=builder /app/_build/prod/rel/router_ex ./

# Expose MAVLink ports
# - 5760: Serial/UART proxy (standard MAVLink port)
# - 14550: UDP port for GCS (QGroundControl default)
# - 14560-14563: Additional UDP ports for multiple endpoints
EXPOSE 5760 14550 14560 14561 14562 14563

# Health check - verify the application is running
# Checks if the BEAM VM is responsive
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD /app/bin/router_ex rpc 'Process.whereis(RouterEx.RouterCore) != nil' || exit 1

# Set runtime environment
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Start the application
CMD ["/app/bin/router_ex", "start"]
