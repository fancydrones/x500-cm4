import Config

# Development configuration
config :router_ex,
  general: [
    tcp_server_port: 5760,
    report_stats: true,  # Enable stats in development
    mavlink_dialect: :auto,
    log_level: :debug     # More verbose logging
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
