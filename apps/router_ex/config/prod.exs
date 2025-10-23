import Config

# Production configuration
# Note: Most production configuration should be in runtime.exs
# This file is evaluated at build time

config :router_ex,
  general: [
    tcp_server_port: 5760,
    report_stats: false,  # Stats disabled by default in prod
    mavlink_dialect: :auto,
    log_level: :info
  ]

# Endpoints should be configured via runtime.exs using environment variables
# or via ROUTER_CONFIG in Kubernetes ConfigMap
config :router_ex, endpoints: []
