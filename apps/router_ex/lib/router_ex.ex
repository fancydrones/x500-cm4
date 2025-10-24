defmodule RouterEx do
  @moduledoc """
  RouterEx is a high-performance MAVLink message router written in Elixir.

  RouterEx provides intelligent routing of MAVLink messages between multiple endpoints
  including serial ports (UART), UDP sockets, and TCP connections. It is designed as a
  drop-in replacement for mavlink-router with enhanced features and better observability.

  ## Features

  - **Multiple Protocol Support**: UART, UDP, TCP endpoints
  - **Intelligent Routing**: System-aware message routing with loop prevention
  - **Message Filtering**: Per-endpoint allow/block lists for message IDs
  - **MAVLink v1/v2**: Full support for both MAVLink protocol versions
  - **Configuration Formats**: INI (mavlink-router compatible), YAML, TOML
  - **Hot Reload**: Configuration changes without restart
  - **Telemetry**: Built-in metrics and observability
  - **Supervision**: OTP supervision trees for fault tolerance

  ## Architecture

  RouterEx is built on OTP principles with a supervision tree:

      RouterEx.Application
      ├── RouterEx.RouterCore (message routing logic)
      ├── RouterEx.ConfigManager (configuration management)
      ├── RouterEx.HealthMonitor (health checks)
      ├── RouterEx.Endpoint.Supervisor (endpoint management)
      │   ├── Serial endpoints
      │   ├── UDP server endpoints
      │   ├── UDP client endpoints
      │   ├── TCP server endpoints
      │   └── TCP client endpoints
      └── RouterEx.Telemetry (metrics and events)

  ## Quick Start

  ### Configuration

  Configure endpoints via environment variable (INI format):

      export ROUTER_CONFIG='
      [General]
      TcpServerPort=5760

      [UartEndpoint FlightController]
      Device=/dev/serial0
      Baud=921600

      [UdpEndpoint GroundStation]
      Mode=Server
      Port=14550
      '

  Or use YAML format:

      export ROUTER_CONFIG='
      general:
        tcp_server_port: 5760
      endpoints:
        - name: FlightController
          type: uart
          device: /dev/serial0
          baud: 921600
      '

  ### Running

      # Start the application
      iex -S mix

      # Or as a release
      _build/prod/rel/router_ex/bin/router_ex start

  ### Container Deployment

      # Build container
      docker build -t router-ex -f apps/router_ex/Dockerfile .

      # Run container
      docker run -d \\
        -e ROUTER_CONFIG="..." \\
        --device /dev/serial0:/dev/serial0 \\
        -p 5760:5760 -p 14550:14550/udp \\
        router-ex

  ## Message Routing

  RouterEx implements intelligent message routing:

  1. **System Awareness**: Tracks which systems are visible on each endpoint
  2. **Targeted Routing**: Routes messages to endpoints that have seen the target system
  3. **Broadcast Routing**: Distributes broadcast messages (target=0) to all endpoints
  4. **Loop Prevention**: Never routes a message back to its source
  5. **Filtering**: Applies per-endpoint message ID filters

  ## Monitoring

  RouterEx provides comprehensive monitoring:

      # Get routing statistics
      RouterEx.RouterCore.get_stats()
      %{
        packets_received: 15234,
        packets_sent: 45678,
        bytes_received: 1234567,
        bytes_sent: 3456789,
        packets_filtered: 123
      }

      # List active connections
      RouterEx.RouterCore.get_connections()

      # View routing table
      RouterEx.RouterCore.get_routing_table()

  ## Telemetry Events

  RouterEx emits telemetry events for monitoring:

  - `[:router_ex, :connection, :registered]` - New connection
  - `[:router_ex, :connection, :unregistered]` - Connection removed
  - `[:router_ex, :message, :routed]` - Message routed
  - `[:router_ex, :endpoint, :started]` - Endpoint started
  - `[:router_ex, :endpoint, :stopped]` - Endpoint stopped

  ## Documentation

  See the following modules for detailed information:

  - `RouterEx.RouterCore` - Core routing logic
  - `RouterEx.ConfigManager` - Configuration management
  - `RouterEx.MAVLink.Parser` - MAVLink protocol parsing
  - `RouterEx.Endpoint.Supervisor` - Endpoint lifecycle management

  ## Links

  - [GitHub Repository](https://github.com/fancydrones/x500-cm4)
  - [Operations Guide](apps/router_ex/docs/operations.md)
  - [MAVLink Protocol](https://mavlink.io/)
  """

  @doc """
  Returns the application version.

  ## Examples

      iex> RouterEx.version()
      "0.1.0"

  """
  def version do
    Application.spec(:router_ex, :vsn) |> to_string()
  end

  @doc """
  Returns basic health status of the router.

  Checks if critical processes are running.

  ## Examples

      iex> RouterEx.health_check()
      {:ok, %{router_core: true, config_manager: true}}

  """
  def health_check do
    router_ok = Process.whereis(RouterEx.RouterCore) != nil
    config_ok = Process.whereis(RouterEx.ConfigManager) != nil

    status = %{
      router_core: router_ok,
      config_manager: config_ok
    }

    if router_ok and config_ok do
      {:ok, status}
    else
      {:error, status}
    end
  end
end
