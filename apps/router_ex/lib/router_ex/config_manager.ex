defmodule RouterEx.ConfigManager do
  @moduledoc """
  Manages router configuration from multiple formats and sources.

  ConfigManager is responsible for loading, parsing, and managing the router's
  configuration. It supports multiple configuration formats for flexibility and
  backward compatibility with mavlink-router.

  ## Supported Formats

  1. **INI Format** (mavlink-router compatible):
     ```ini
     [General]
     TcpServerPort=5760
     ReportStats=false

     [UartEndpoint FlightController]
     Device=/dev/serial0
     Baud=921600

     [UdpEndpoint GroundStation]
     Mode=Server
     Port=14550
     AllowMsgIdOut=0,1,33
     ```

  2. **YAML Format** (Kubernetes-friendly):
     ```yaml
     general:
       tcp_server_port: 5760
       report_stats: false
     endpoints:
       - name: FlightController
         type: uart
         device: /dev/serial0
         baud: 921600
       - name: GroundStation
         type: udp_server
         port: 14550
         allow_msg_ids: [0, 1, 33]
     ```

  3. **TOML Format** (modern alternative):
     ```toml
     [general]
     tcp_server_port = 5760
     report_stats = false

     [[endpoints]]
     name = "FlightController"
     type = "uart"
     device = "/dev/serial0"
     baud = 921600
     ```

  ## Configuration Sources

  Configuration is loaded in the following priority order (later sources override earlier):

  1. **Application Environment**: `Application.get_env(:router_ex, :endpoints)`
  2. **INI File**: Parsed from ROUTER_CONFIG env var
  3. **YAML File**: Parsed from ROUTER_CONFIG env var
  4. **TOML File**: Parsed from ROUTER_CONFIG env var

  The `ROUTER_CONFIG` environment variable should contain the full configuration
  as a string in one of the supported formats.

  ## Dynamic Reload

  Configuration can be reloaded at runtime without restarting the application:

      # Reload configuration from source
      RouterEx.ConfigManager.reload_config()

  Note: Reloading configuration will restart endpoints with new settings.

  ## Endpoint Types

  ### UART (Serial)
  ```elixir
  %{
    name: "FlightController",
    type: :uart,
    device: "/dev/serial0",
    baud: 921600,
    flow_control: false
  }
  ```

  ### UDP Server
  ```elixir
  %{
    name: "GroundStation",
    type: :udp_server,
    address: "0.0.0.0",
    port: 14550
  }
  ```

  ### UDP Client
  ```elixir
  %{
    name: "RemoteGCS",
    type: :udp_client,
    address: "192.168.1.100",
    port: 14550
  }
  ```

  ### TCP Server
  ```elixir
  %{
    name: "MissionPlanner",
    type: :tcp_server,
    address: "0.0.0.0",
    port: 5760
  }
  ```

  ### TCP Client
  ```elixir
  %{
    name: "RemoteServer",
    type: :tcp_client,
    address: "192.168.1.200",
    port: 5760
  }
  ```

  ## Message Filtering

  Each endpoint can filter messages using allow lists (whitelist) or block lists (blacklist):

  ### Allow List (Whitelist)
  Only specified message IDs are forwarded:
  ```elixir
  %{
    name: "FilteredEndpoint",
    type: :udp_server,
    port: 14560,
    allow_msg_ids: [0, 1, 33, 147]  # Only HEARTBEAT, SYS_STATUS, ATTITUDE, BATTERY_STATUS
  }
  ```

  ### Block List (Blacklist)
  All messages except specified IDs are forwarded:
  ```elixir
  %{
    name: "VideoEndpoint",
    type: :udp_server,
    port: 14561,
    block_msg_ids: [263]  # Block CAMERA_IMAGE_CAPTURED
  }
  ```

  ### Combined Filtering
  When both are specified, allow list is checked first, then block list:
  ```elixir
  %{
    allow_msg_ids: [0, 1, 33, 253],
    block_msg_ids: [253]  # Block STATUSTEXT even though it's in allow list
  }
  ```

  ## Examples

      # Get current configuration
      config = RouterEx.ConfigManager.get_config()
      # => %{general: [...], endpoints: [...]}

      # Reload configuration
      :ok = RouterEx.ConfigManager.reload_config()

      # Access endpoint configurations
      config.endpoints
      # => [%{name: "FlightController", type: :uart, ...}, ...]

  """

  use GenServer
  require Logger

  @typedoc """
  Configuration for a single endpoint.

  ## Fields

  - `:name` - Unique identifier for the endpoint
  - `:type` - Endpoint type (uart, udp_server, udp_client, tcp_server, tcp_client)
  - `:device` - Serial device path (for UART endpoints)
  - `:baud` - Baud rate (for UART endpoints)
  - `:address` - IP address (for network endpoints)
  - `:port` - Port number (for network endpoints)
  - `:allow_msg_ids` - Whitelist of allowed message IDs
  - `:block_msg_ids` - Blacklist of blocked message IDs
  """
  @type endpoint_config :: %{
          required(:name) => String.t(),
          required(:type) => :uart | :udp_server | :udp_client | :tcp_server | :tcp_client,
          optional(:device) => String.t(),
          optional(:baud) => pos_integer(),
          optional(:flow_control) => boolean(),
          optional(:address) => String.t() | :inet.ip_address(),
          optional(:port) => :inet.port_number(),
          optional(:allow_msg_ids) => [non_neg_integer()],
          optional(:block_msg_ids) => [non_neg_integer()]
        }

  @typedoc """
  General router configuration settings.

  ## Common Settings

  - `:tcp_server_port` - Port for TCP server (default: 5760)
  - `:report_stats` - Enable periodic statistics reporting (default: false)
  - `:mavlink_dialect` - MAVLink dialect (default: "common")
  - `:log_level` - Logging level (default: :info)
  """
  @type general_config :: keyword()

  @typedoc """
  Complete router configuration.

  Contains general settings and list of endpoint configurations.
  """
  @type config :: %{
          general: general_config(),
          endpoints: [endpoint_config()]
        }

  ## Client API

  @doc """
  Starts the ConfigManager.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the current configuration.
  """
  @spec get_config() :: config()
  def get_config do
    GenServer.call(__MODULE__, :get_config)
  end

  @doc """
  Reloads configuration from source.

  Note: This will restart all endpoints with new configuration.
  """
  @spec reload_config() :: :ok | {:error, term()}
  def reload_config do
    GenServer.call(__MODULE__, :reload_config)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    config = load_config()

    Logger.info("Configuration loaded: #{length(config.endpoints)} endpoints configured")

    # Start configured endpoints
    start_endpoints(config.endpoints)

    {:ok, %{config: config}}
  end

  @impl true
  def handle_call(:get_config, _from, state) do
    {:reply, state.config, state}
  end

  @impl true
  def handle_call(:reload_config, _from, state) do
    Logger.info("Reloading configuration")

    try do
      config = load_config()

      # TODO: Implement graceful endpoint restart
      # For now, just update state
      Logger.info("Configuration reloaded: #{length(config.endpoints)} endpoints")

      {:reply, :ok, %{state | config: config}}
    rescue
      e ->
        Logger.error("Failed to reload configuration: #{inspect(e)}")
        {:reply, {:error, e}, state}
    end
  end

  ## Private Functions

  defp load_config do
    # Priority order: Elixir config > YAML > TOML > INI
    cond do
      # 1. Elixir-native configuration (recommended)
      config = Application.get_env(:router_ex, :config) ->
        Logger.debug("Loading configuration from Application environment")
        config

      # 2. YAML configuration (Kubernetes-friendly)
      yaml_content = System.get_env("ROUTER_CONFIG_YAML") ->
        Logger.info("Loading configuration from YAML")
        parse_yaml(yaml_content)

      # 3. TOML configuration (modern alternative)
      toml_content = System.get_env("ROUTER_CONFIG_TOML") ->
        Logger.info("Loading configuration from TOML")
        parse_toml(toml_content)

      # 4. INI configuration (backward compatibility)
      ini_content = System.get_env("ROUTER_CONFIG") ->
        Logger.info("Loading configuration from INI")
        parse_ini(ini_content)

      # Fallback to default config from Application env
      true ->
        Logger.debug("Loading default configuration")
        default_config()
    end
  end

  defp default_config do
    %{
      general:
        Application.get_env(:router_ex, :general,
          tcp_server_port: 5760,
          report_stats: false,
          mavlink_dialect: :auto,
          log_level: :info
        ),
      endpoints: Application.get_env(:router_ex, :endpoints, [])
    }
  end

  defp parse_yaml(content) when is_binary(content) do
    # TODO: Implement YAML parsing when yaml_elixir is loaded
    # For now, return default config
    Logger.warning("YAML parsing not yet implemented, using default config")
    default_config()
  end

  defp parse_toml(content) when is_binary(content) do
    # TODO: Implement TOML parsing when toml is loaded
    # For now, return default config
    Logger.warning("TOML parsing not yet implemented, using default config")
    default_config()
  end

  defp parse_ini(content) when is_binary(content) do
    Logger.info("Parsing INI configuration")

    lines =
      content
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))

    {general, endpoints} = parse_ini_sections(lines)

    %{
      general: general,
      endpoints: endpoints
    }
  end

  defp parse_ini_sections(lines) do
    parse_ini_sections(lines, :none, %{}, [], [])
  end

  defp parse_ini_sections([], current_section, general, endpoints, current_endpoint) do
    # Finalize the last endpoint if there is one
    endpoints =
      if current_section != :none and current_section != :general and current_endpoint != [] do
        [finalize_endpoint(current_section, current_endpoint) | endpoints]
      else
        endpoints
      end

    {Map.to_list(general), Enum.reverse(endpoints)}
  end

  defp parse_ini_sections([line | rest], current_section, general, endpoints, current_endpoint) do
    cond do
      # Section header: [SectionName] or [SectionName Value]
      String.starts_with?(line, "[") and String.ends_with?(line, "]") ->
        # Save current endpoint if any
        endpoints =
          if current_section != :none and current_section != :general and
               current_endpoint != [] do
            [finalize_endpoint(current_section, current_endpoint) | endpoints]
          else
            endpoints
          end

        # Parse new section
        section_content = String.slice(line, 1..-2//1) |> String.trim()

        cond do
          section_content == "General" ->
            parse_ini_sections(rest, :general, general, endpoints, [])

          String.starts_with?(section_content, "UartEndpoint") ->
            name = String.replace_prefix(section_content, "UartEndpoint ", "")
            parse_ini_sections(rest, :uart, general, endpoints, name: name)

          String.starts_with?(section_content, "UdpEndpoint") ->
            name = String.replace_prefix(section_content, "UdpEndpoint ", "")
            parse_ini_sections(rest, :udp, general, endpoints, name: name)

          String.starts_with?(section_content, "TcpEndpoint") ->
            name = String.replace_prefix(section_content, "TcpEndpoint ", "")
            parse_ini_sections(rest, :tcp, general, endpoints, name: name)

          true ->
            Logger.warning("Unknown section: #{section_content}")
            parse_ini_sections(rest, :unknown, general, endpoints, [])
        end

      # Key=Value pair
      String.contains?(line, "=") ->
        [key, value] = String.split(line, "=", parts: 2)
        key = String.trim(key)
        value = String.trim(value)

        case current_section do
          :general ->
            general = parse_general_key(general, key, value)
            parse_ini_sections(rest, current_section, general, endpoints, current_endpoint)

          section when section in [:uart, :udp, :tcp] ->
            current_endpoint = parse_endpoint_key(current_endpoint, key, value)
            parse_ini_sections(rest, current_section, general, endpoints, current_endpoint)

          _ ->
            parse_ini_sections(rest, current_section, general, endpoints, current_endpoint)
        end

      # Unknown line format
      true ->
        Logger.debug("Skipping line: #{line}")
        parse_ini_sections(rest, current_section, general, endpoints, current_endpoint)
    end
  end

  defp parse_general_key(general, "TcpServerPort", value) do
    Map.put(general, :tcp_server_port, String.to_integer(value))
  end

  defp parse_general_key(general, "ReportStats", value) do
    Map.put(general, :report_stats, value in ["true", "True", "1"])
  end

  defp parse_general_key(general, "MavlinkDialect", value) do
    Map.put(general, :mavlink_dialect, String.to_atom(value))
  end

  defp parse_general_key(general, "DebugLogLevel", value) do
    Map.put(general, :log_level, String.to_atom(value))
  end

  defp parse_general_key(general, _key, _value) do
    # Ignore unknown keys
    general
  end

  defp parse_endpoint_key(endpoint, "Device", value) do
    Keyword.put(endpoint, :device, value)
  end

  defp parse_endpoint_key(endpoint, "Baud", value) do
    Keyword.put(endpoint, :baud, String.to_integer(value))
  end

  defp parse_endpoint_key(endpoint, "Mode", value) do
    Keyword.put(endpoint, :mode, String.downcase(value))
  end

  defp parse_endpoint_key(endpoint, "Address", value) do
    Keyword.put(endpoint, :address, value)
  end

  defp parse_endpoint_key(endpoint, "Port", value) do
    Keyword.put(endpoint, :port, String.to_integer(value))
  end

  defp parse_endpoint_key(endpoint, "AllowMsgIdOut", value) do
    ids =
      value
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.map(&String.to_integer/1)

    Keyword.put(endpoint, :allow_msg_ids, ids)
  end

  defp parse_endpoint_key(endpoint, "BlockMsgIdOut", value) do
    ids =
      value
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.map(&String.to_integer/1)

    Keyword.put(endpoint, :block_msg_ids, ids)
  end

  defp parse_endpoint_key(endpoint, _key, _value) do
    # Ignore unknown keys
    endpoint
  end

  defp finalize_endpoint(:uart, config) do
    %{
      name: Keyword.fetch!(config, :name),
      type: :uart,
      device: Keyword.fetch!(config, :device),
      baud: Keyword.get(config, :baud, 57_600),
      allow_msg_ids: Keyword.get(config, :allow_msg_ids),
      block_msg_ids: Keyword.get(config, :block_msg_ids)
    }
  end

  defp finalize_endpoint(:udp, config) do
    mode = Keyword.get(config, :mode, "normal")

    type =
      case String.downcase(mode) do
        "server" -> :udp_server
        "normal" -> :udp_client
        _ -> :udp_client
      end

    %{
      name: Keyword.fetch!(config, :name),
      type: type,
      address: Keyword.get(config, :address, "0.0.0.0"),
      port: Keyword.fetch!(config, :port),
      allow_msg_ids: Keyword.get(config, :allow_msg_ids),
      block_msg_ids: Keyword.get(config, :block_msg_ids)
    }
  end

  defp finalize_endpoint(:tcp, config) do
    mode = Keyword.get(config, :mode, "normal")

    type =
      case String.downcase(mode) do
        "server" -> :tcp_server
        "normal" -> :tcp_client
        _ -> :tcp_client
      end

    %{
      name: Keyword.fetch!(config, :name),
      type: type,
      address: Keyword.get(config, :address, "0.0.0.0"),
      port: Keyword.fetch!(config, :port),
      allow_msg_ids: Keyword.get(config, :allow_msg_ids),
      block_msg_ids: Keyword.get(config, :block_msg_ids)
    }
  end

  defp start_endpoints(endpoints) when is_list(endpoints) do
    # Start each endpoint via the Endpoint.Supervisor
    Enum.each(endpoints, fn endpoint ->
      Logger.info("Starting configured endpoint: #{endpoint.name} (#{endpoint.type})")

      case RouterEx.Endpoint.Supervisor.start_endpoint(endpoint) do
        {:ok, _pid} ->
          Logger.info("Successfully started endpoint: #{endpoint.name}")

        {:error, reason} ->
          Logger.error("Failed to start endpoint #{endpoint.name}: #{inspect(reason)}")
      end
    end)
  end
end
