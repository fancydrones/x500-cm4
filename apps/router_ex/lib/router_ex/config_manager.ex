defmodule RouterEx.ConfigManager do
  @moduledoc """
  Manages router configuration from multiple formats:
  - Elixir (recommended): config/runtime.exs
  - YAML: for Kubernetes ConfigMaps
  - TOML: modern alternative to INI
  - INI: backward compatibility with mavlink-router

  Priority: Elixir > YAML > TOML > INI

  The ConfigManager loads configuration on startup and can reload
  configuration dynamically when requested.
  """

  use GenServer
  require Logger

  @type endpoint_config :: %{
          required(:name) => String.t(),
          required(:type) => :uart | :udp_server | :udp_client | :tcp_server | :tcp_client,
          optional(:device) => String.t(),
          optional(:baud) => pos_integer(),
          optional(:address) => String.t(),
          optional(:port) => :inet.port_number(),
          optional(:allow_msg_ids) => [non_neg_integer()],
          optional(:block_msg_ids) => [non_neg_integer()]
        }

  @type general_config :: keyword()

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

    Logger.info(
      "Configuration loaded: #{length(config.endpoints)} endpoints configured"
    )

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
      general: Application.get_env(:router_ex, :general, [
        tcp_server_port: 5760,
        report_stats: false,
        mavlink_dialect: :auto,
        log_level: :info
      ]),
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
    # TODO: Implement INI parsing for mavlink-router compatibility
    # For now, return default config
    Logger.warning("INI parsing not yet implemented, using default config")
    default_config()
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
