import Config

# Production configuration
# Runtime environment variables are handled in runtime.exs

# Set production logger level to debug temporarily for debugging
config :logger, level: :debug

# Compile-time production settings
config :announcer_ex,
  # Environment-specific runtime config is in runtime.exs
  # Static deployment config from announcer-ex-deployment.yaml:
  # - CAMERA_URL (from configMap)
  # - CAMERA_ID: "100"
  # - CAMERA_NAME: "Front"
  # - SYSTEM_HOST: "router-service.rpiuav.svc.cluster.local"
  # - SYSTEM_PORT: "14560"
  # - SYSTEM_ID (from configMap)
  # - MAVLINK20: "1"
  env: :prod
