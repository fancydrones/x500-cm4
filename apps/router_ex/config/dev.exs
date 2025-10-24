import Config

# Development configuration

# Configure XMAVLink for development
config :xmavlink,
  dialect: Common,
  system_id: 255,
  component_id: 1,
  heartbeat_interval_ms: 1000

config :router_ex,
  general: [
    tcp_server_port: 5760,
    # Enable stats in development
    report_stats: true,
    mavlink_dialect: :auto,
    # More verbose logging
    log_level: :debug
  ],

  # Development endpoints (example configuration)
  endpoints: [
    # Example: Connect to SITL (Software In The Loop) for testing
    # Uncomment when testing with SITL
    # %{
    #   name: "SITL",
    #   type: :tcp_client,
    #   address: "127.0.0.1",
    #   port: 5762
    # },
    # %{
    #   name: "QGC_UDP",
    #   type: :udp_server,
    #   address: "0.0.0.0",
    #   port: 14550
    # }
  ]
