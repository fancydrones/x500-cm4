import Config

# Configure XMAVLink for testing
config :xmavlink,
  dialect: Common,
  system_id: 255,
  component_id: 1,
  connections: []

# Test configuration
config :router_ex,
  general: [
    # Different port for testing
    tcp_server_port: 15760,
    report_stats: false,
    mavlink_dialect: :auto,
    # Less verbose during tests
    log_level: :warning
  ],

  # No endpoints by default in test - tests will configure as needed
  endpoints: []

# Disable telemetry polling during tests
config :router_ex, RouterEx.Telemetry, enabled: false
