import Config

# General router configuration
config :router_ex,
  # Default settings (can be overridden in runtime.exs)
  general: [
    tcp_server_port: 5760,
    report_stats: false,
    mavlink_dialect: :auto,
    log_level: :info
  ]

# Import environment-specific config
import_config "#{config_env()}.exs"
