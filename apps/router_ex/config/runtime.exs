import Config

# Runtime configuration loaded when the release starts
# This is where production configuration should be specified

if config_env() == :prod do
  # Helper functions for parsing environment variables
  parse_int = fn env_var, default ->
    case System.get_env(env_var) do
      nil -> default
      value -> String.to_integer(value)
    end
  end

  parse_bool = fn env_var, default ->
    case System.get_env(env_var) do
      nil -> default
      "true" -> true
      "1" -> true
      "false" -> false
      "0" -> false
      _ -> default
    end
  end

  parse_list = fn env_var, default ->
    case System.get_env(env_var) do
      nil ->
        default

      value ->
        value
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(&String.to_integer/1)
    end
  end

  # General configuration
  config :router_ex,
    general: [
      tcp_server_port: parse_int.("TCP_SERVER_PORT", 5760),
      report_stats: parse_bool.("REPORT_STATS", false),
      mavlink_dialect: :auto,
      log_level: String.to_atom(System.get_env("LOG_LEVEL", "info"))
    ]

  # Endpoint configuration from environment
  # Example: ROUTER_ENDPOINTS environment variable can contain endpoint configuration
  # For now, endpoints are configured via Elixir config
  # Future: support loading from YAML/TOML/INI via environment variables

  # Example Elixir-native endpoint configuration
  endpoints =
    case System.get_env("ROUTER_CONFIG_MODE") do
      "example" ->
        # Example configuration for testing
        [
          %{
            name: "FlightController",
            type: :uart,
            device: System.get_env("SERIAL_DEVICE", "/dev/serial0"),
            baud: parse_int.("SERIAL_BAUD", 921_600)
          },
          %{
            name: "video0",
            type: :udp_server,
            address: "0.0.0.0",
            port: 14560,
            allow_msg_ids: parse_list.("VIDEO0_ALLOWED_MSGS", [0, 4, 76, 322, 323])
          }
        ]

      _ ->
        # Load from application environment or empty list
        Application.get_env(:router_ex, :endpoints, [])
    end

  config :router_ex, endpoints: endpoints
end
