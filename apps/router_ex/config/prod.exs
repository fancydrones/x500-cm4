import Config

# Production configuration
# Note: Most production configuration should be in runtime.exs
# This file is evaluated at build time

# Configure XMAVLink for production
config :xmavlink,
  dialect: Common,
  system_id: 255,
  component_id: 1,
  heartbeat_interval_ms: 1000

config :router_ex,
  general: [
    tcp_server_port: 5760,
    # Stats disabled by default in prod
    report_stats: false,
    mavlink_dialect: :auto,
    log_level: :info
  ]

# Endpoints should be configured via runtime.exs using environment variables
# or via ROUTER_CONFIG in Kubernetes ConfigMap
config :router_ex, endpoints: []
