# Implementation Plan: Router-Ex - Elixir MAVLink Router

## Executive Summary

This document provides a detailed implementation plan for Router-Ex, an Elixir-based MAVLink message router for the x500-cm4 UAV platform. Router-Ex will replicate and eventually replace the existing C/C++ mavlink-router with a native Elixir implementation using the XMAVLink library, providing better integration with the existing Elixir ecosystem (announcer-ex, video-streamer, companion) while maintaining full compatibility with existing configurations and behaviors.

## Project Context

### Overview
- **Current Router:** C/C++ mavlink-router (github.com/mavlink-router/mavlink-router)
- **New Router:** Elixir-based router-ex using XMAVLink library
- **Platform:** Raspberry Pi CM4/CM5 companion computer
- **Deployment:** K3s cluster on companion computer
- **Software Stack:** Elixir + XMAVLink
- **Container Base:** Alpine Linux
- **Protocol:** MAVLink 1.0/2.0
- **Connections:** Serial (UART), UDP (server/client), TCP (server/client)

### Rationale for Elixir Implementation

**Benefits:**
1. **Unified Ecosystem:** All drone services in Elixir (router-ex, announcer-ex, video-streamer, companion)
2. **Maintainability:** Easier to modify and extend than C/C++
3. **Hot Code Reloading:** Update routing logic without restart
4. **Fault Tolerance:** OTP supervision trees for automatic recovery
5. **Telemetry:** Built-in observability with Elixir telemetry
6. **Developer Productivity:** Faster iteration and testing cycles

**Compatibility Goals:**
1. Drop-in replacement for existing router
2. Support existing configuration format
3. Maintain same port mappings (5760, 14550, 14560-14563)
4. Compatible with all existing MAVLink clients

### Key Design Principles
1. **Compatibility First:** Maintain behavior parity with mavlink-router
2. **Configuration Compatible:** Parse existing main.conf format
3. **Performance:** Minimize latency, handle high message rates
4. **Reliability:** Automatic reconnection, fault tolerance
5. **Observability:** Comprehensive logging and telemetry
6. **Extensibility:** Easy to add new features (message sniffing, logging, filtering)

## Architecture Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Router-Ex Application                    │
│                                                               │
│  ┌───────────────────────────────────────────────────────┐  │
│  │              Router.Supervisor                         │  │
│  │                                                         │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐│  │
│  │  │ Config       │  │ Router       │  │ Telemetry    ││  │
│  │  │ Manager      │  │ Core         │  │ Reporter     ││  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘│  │
│  │                                                         │  │
│  │  ┌────────────────────────────────────────────────────┐│  │
│  │  │         Connection Supervisor                      ││  │
│  │  │                                                     ││  │
│  │  │  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐  ││  │
│  │  │  │ Serial │  │ UDP    │  │ UDP    │  │ TCP    │  ││  │
│  │  │  │ Handler│  │ Server │  │ Client │  │ Server │  ││  │
│  │  │  └────────┘  └────────┘  └────────┘  └────────┘  ││  │
│  │  └────────────────────────────────────────────────────┘│  │
│  └───────────────────────────────────────────────────────┘  │
│                                                               │
│  Message Flow:                                                │
│  Connection → RouterCore → Filter → Route → Connections      │
└─────────────────────────────────────────────────────────────┘

         ↕ Serial        ↕ UDP          ↕ UDP         ↕ TCP
   ┌──────────┐    ┌──────────┐   ┌──────────┐  ┌──────────┐
   │ Flight   │    │ Video    │   │ Ground   │  │ QGC/ATAK │
   │Controller│    │Components│   │ Station  │  │  Clients │
   └──────────┘    └──────────┘   └──────────┘  └──────────┘
```

### Message Routing Logic

Router-Ex implements intelligent message routing using the MAVLink addressing scheme:

**Routing Rules:**
1. **System Awareness:** Track which systems have been seen on each connection
2. **Targeted Messages:** Route to connections aware of the target system
3. **Broadcast Messages:** Forward to all connections except source
4. **No Loops:** Never send message back to source connection
5. **Filtering:** Apply AllowMsgIdOut/BlockMsgIdOut per endpoint

**Message Flow:**
```
1. Receive MAVLink packet on Connection A
2. Parse and validate packet
3. Extract source (system_id, component_id)
4. Update routing table: Connection A knows about source system
5. Determine target:
   - If target_system != 0: targeted message
   - If target_system == 0: broadcast message
6. For targeted messages:
   - Find connections that have seen target_system
   - Apply egress filters
   - Forward to matching connections (except source)
7. For broadcast messages:
   - Apply egress filters
   - Forward to all connections (except source)
8. Update telemetry (packets routed, bytes transferred)
```

### Connection Types

**1. Serial (UART) Connections**
```elixir
# Configuration
[UartEndpoint FlightControllerSerial]
Device = /dev/serial0
Baud = 921600

# Implementation
- Use Circuits.UART library
- Handle device open/close/errors
- Automatic reconnection on disconnect
- Buffer management for high-speed data
```

**2. UDP Server Endpoints**
```elixir
# Configuration
[UdpEndpoint video0]
Mode = Server
Address = 0.0.0.0
Port = 14560
AllowMsgIdOut = 0,4,76,322,323

# Implementation
- Bind to specified port
- Track multiple clients by {ip, port}
- Per-client system awareness
- Message filtering per endpoint
```

**3. UDP Client Endpoints**
```elixir
# Configuration
[UdpEndpoint GCS]
Mode = Normal
Address = 10.10.10.70
Port = 14550

# Implementation
- Send to fixed destination
- Track responses from remote
- Handle network changes
```

**4. TCP Server**
```elixir
# Configuration
[General]
TcpServerPort=5760

# Implementation
- Listen for incoming connections
- Per-client connection tracking
- Handle client connect/disconnect
- Dynamic client management
```

### Comparison: mavlink-router vs Router-Ex

| Feature | mavlink-router (C++) | Router-Ex (Elixir) |
|---------|---------------------|-------------------|
| **Language** | C/C++ | Elixir |
| **Concurrency** | Threading | Actor model (processes) |
| **Hot Reload** | No (requires restart) | Yes (code reloading) |
| **Supervision** | Manual | OTP supervision trees |
| **Telemetry** | Basic stats | Rich telemetry events |
| **Configuration** | INI file | INI file + runtime env |
| **Memory** | ~10-20 MB | ~30-50 MB (acceptable) |
| **CPU** | <5% idle | <10% idle (acceptable) |
| **Integration** | Standalone | Native Elixir ecosystem |
| **Development** | Compile/test cycles | Interactive shell, hot reload |

## Implementation Phases

### Phase 1: Project Setup & Basic Router (Week 1-2)

#### 1.1 Create New Elixir Application

**Location:** `apps/router_ex/`

**Command:**
```bash
cd apps
mix new router_ex --sup
```

**Dependencies (mix.exs):**
```elixir
defp deps do
  [
    # MAVLink library
    {:xmavlink, "~> 0.5.0"},

    # Serial communication
    {:circuits_uart, "~> 1.5"},

    # Configuration parsing
    {:toml, "~> 0.7"},  # If using TOML, or parse INI manually

    # Telemetry
    {:telemetry, "~> 1.2"},
    {:telemetry_metrics, "~> 1.0"},
    {:telemetry_poller, "~> 1.0"},

    # Testing
    {:stream_data, "~> 1.0", only: :test}
  ]
end
```

#### 1.2 Application Structure

**File:** `lib/router_ex/application.ex`
```elixir
defmodule RouterEx.Application do
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting Router-Ex application")

    children = [
      # Configuration manager
      RouterEx.ConfigManager,

      # Telemetry setup
      RouterEx.Telemetry,

      # Router core (message routing logic)
      RouterEx.RouterCore,

      # Connection supervisor (manages all endpoint connections)
      {DynamicSupervisor, name: RouterEx.ConnectionSupervisor, strategy: :one_for_one}
    ]

    opts = [strategy: :one_for_one, name: RouterEx.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

#### 1.3 Configuration Manager

**File:** `lib/router_ex/config_manager.ex`
```elixir
defmodule RouterEx.ConfigManager do
  @moduledoc """
  Manages router configuration from INI file format.
  Compatible with mavlink-router main.conf format.
  """

  use GenServer
  require Logger

  @type endpoint_config :: %{
    name: String.t(),
    type: :uart | :udp_server | :udp_client | :tcp_server,
    device: String.t() | nil,
    address: String.t() | nil,
    port: integer() | nil,
    baud: integer() | nil,
    mode: :server | :normal | nil,
    allow_msg_ids: [integer()] | nil,
    block_msg_ids: [integer()] | nil
  }

  @type config :: %{
    general: %{
      tcp_server_port: integer(),
      report_stats: boolean(),
      mavlink_dialect: :auto | atom()
    },
    endpoints: [endpoint_config()]
  }

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def get_config do
    GenServer.call(__MODULE__, :get_config)
  end

  def reload_config do
    GenServer.call(__MODULE__, :reload_config)
  end

  # Server Callbacks

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
    # Reload configuration and restart endpoints
    config = load_config()
    Logger.info("Configuration reloaded")

    # TODO: Implement graceful endpoint restart

    {:reply, :ok, %{state | config: config}}
  end

  # Private Functions

  defp load_config do
    # Load from environment variable or default location
    config_content = System.get_env("ROUTER_CONFIG") ||
                     File.read!("/etc/mavlink-router/main.conf")

    parse_config(config_content)
  end

  defp parse_config(content) do
    # Parse INI-style configuration
    # See implementation in Phase 1 detailed tasks

    %{
      general: %{
        tcp_server_port: 5760,
        report_stats: false,
        mavlink_dialect: :auto
      },
      endpoints: []
    }
  end

  defp start_endpoints(endpoints) do
    Enum.each(endpoints, fn endpoint ->
      RouterEx.Endpoint.Supervisor.start_endpoint(endpoint)
    end)
  end
end
```

#### 1.4 Router Core

**File:** `lib/router_ex/router_core.ex`
```elixir
defmodule RouterEx.RouterCore do
  @moduledoc """
  Core routing logic for MAVLink messages.

  Maintains:
  - Routing table (system_id -> connections that have seen it)
  - Connection registry (active connections)
  - Message statistics
  """

  use GenServer
  require Logger

  alias XMAVLink.Frame

  @type connection_id :: {atom(), String.t()}
  @type system_id :: integer()

  @type state :: %{
    # Map: system_id -> MapSet of connection_ids that have seen this system
    routing_table: %{system_id() => MapSet.t(connection_id())},

    # Map: connection_id -> connection info
    connections: %{connection_id() => map()},

    # Statistics
    stats: %{
      packets_received: integer(),
      packets_sent: integer(),
      bytes_received: integer(),
      bytes_sent: integer()
    }
  }

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def register_connection(connection_id, connection_info) do
    GenServer.call(__MODULE__, {:register_connection, connection_id, connection_info})
  end

  def unregister_connection(connection_id) do
    GenServer.call(__MODULE__, {:unregister_connection, connection_id})
  end

  def route_message(source_connection_id, frame) do
    GenServer.cast(__MODULE__, {:route_message, source_connection_id, frame})
  end

  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Router core starting")

    state = %{
      routing_table: %{},
      connections: %{},
      stats: %{
        packets_received: 0,
        packets_sent: 0,
        bytes_received: 0,
        bytes_sent: 0
      }
    }

    # Schedule periodic stats reporting if enabled
    schedule_stats_report()

    {:ok, state}
  end

  @impl true
  def handle_call({:register_connection, conn_id, conn_info}, _from, state) do
    Logger.info("Registering connection: #{inspect(conn_id)}")
    new_connections = Map.put(state.connections, conn_id, conn_info)
    {:reply, :ok, %{state | connections: new_connections}}
  end

  @impl true
  def handle_call({:unregister_connection, conn_id}, _from, state) do
    Logger.info("Unregistering connection: #{inspect(conn_id)}")

    # Remove from connections
    new_connections = Map.delete(state.connections, conn_id)

    # Remove from routing table
    new_routing_table =
      state.routing_table
      |> Enum.map(fn {sys_id, conn_set} ->
        {sys_id, MapSet.delete(conn_set, conn_id)}
      end)
      |> Enum.into(%{})

    {:reply, :ok, %{state | connections: new_connections, routing_table: new_routing_table}}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.stats, state}
  end

  @impl true
  def handle_cast({:route_message, source_conn_id, frame}, state) do
    # Update routing table: source connection has seen this system
    source_system = frame.source_system

    new_routing_table =
      Map.update(
        state.routing_table,
        source_system,
        MapSet.new([source_conn_id]),
        &MapSet.put(&1, source_conn_id)
      )

    # Determine target connections
    target_conns = determine_targets(frame, source_conn_id, new_routing_table, state.connections)

    # Send to all target connections
    Enum.each(target_conns, fn {conn_id, conn_info} ->
      send_to_connection(conn_id, conn_info, frame)
    end)

    # Update statistics
    new_stats = %{
      state.stats |
      packets_received: state.stats.packets_received + 1,
      packets_sent: state.stats.packets_sent + length(target_conns),
      bytes_received: state.stats.bytes_received + byte_size(frame.payload)
    }

    {:noreply, %{state | routing_table: new_routing_table, stats: new_stats}}
  end

  @impl true
  def handle_info(:report_stats, state) do
    if Application.get_env(:router_ex, :report_stats, false) do
      Logger.info("Router stats: #{inspect(state.stats)}")
    end

    schedule_stats_report()
    {:noreply, state}
  end

  # Private Functions

  defp determine_targets(frame, source_conn_id, routing_table, connections) do
    target_system = get_target_system(frame.message)

    if target_system == 0 do
      # Broadcast: send to all connections except source
      connections
      |> Enum.reject(fn {conn_id, _} -> conn_id == source_conn_id end)
    else
      # Targeted: send to connections that have seen target system
      case Map.get(routing_table, target_system) do
        nil ->
          # Unknown target, broadcast to all except source
          connections
          |> Enum.reject(fn {conn_id, _} -> conn_id == source_conn_id end)

        conn_set ->
          # Send to connections aware of target (except source)
          conn_set
          |> MapSet.delete(source_conn_id)
          |> Enum.map(fn conn_id -> {conn_id, connections[conn_id]} end)
      end
    end
    |> Enum.filter(&apply_filters(&1, frame))
  end

  defp get_target_system(message) do
    # Extract target_system from message if it has one
    # Different message types have different field names
    cond do
      Map.has_key?(message, :target_system) -> message.target_system
      true -> 0  # Broadcast
    end
  end

  defp apply_filters({_conn_id, conn_info}, frame) do
    msg_id = frame.message_id

    # Check AllowMsgIdOut (whitelist)
    allowed = if allow_list = conn_info[:allow_msg_ids] do
      msg_id in allow_list
    else
      true
    end

    # Check BlockMsgIdOut (blacklist)
    blocked = if block_list = conn_info[:block_msg_ids] do
      msg_id in block_list
    else
      false
    end

    allowed and not blocked
  end

  defp send_to_connection(conn_id, conn_info, frame) do
    # Send frame to connection process
    # Connection handler will serialize and transmit
    send(conn_info.pid, {:send_frame, frame})
  end

  defp schedule_stats_report do
    Process.send_after(self(), :report_stats, 10_000)
  end
end
```

### Phase 2: Connection Handlers (Week 3-4)

#### 2.1 Endpoint Supervisor

**File:** `lib/router_ex/endpoint/supervisor.ex`
```elixir
defmodule RouterEx.Endpoint.Supervisor do
  @moduledoc """
  Supervises all endpoint connections.
  Handles starting/stopping individual endpoints.
  """

  use DynamicSupervisor

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_endpoint(endpoint_config) do
    spec = endpoint_child_spec(endpoint_config)
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  defp endpoint_child_spec(%{type: :uart} = config) do
    {RouterEx.Endpoint.Serial, config}
  end

  defp endpoint_child_spec(%{type: :udp_server} = config) do
    {RouterEx.Endpoint.UDPServer, config}
  end

  defp endpoint_child_spec(%{type: :udp_client} = config) do
    {RouterEx.Endpoint.UDPClient, config}
  end

  defp endpoint_child_spec(%{type: :tcp_server} = config) do
    {RouterEx.Endpoint.TCPServer, config}
  end
end
```

#### 2.2 Serial Handler

**File:** `lib/router_ex/endpoint/serial.ex`
```elixir
defmodule RouterEx.Endpoint.Serial do
  @moduledoc """
  Handles UART serial connections to flight controller.
  Uses Circuits.UART for hardware communication.
  """

  use GenServer
  require Logger

  alias Circuits.UART
  alias RouterEx.RouterCore

  # Client API

  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  # Server Callbacks

  @impl true
  def init(config) do
    Logger.info("Starting serial endpoint: #{config.name} on #{config.device} @ #{config.baud}")

    connection_id = {:serial, config.name}

    # Open serial port
    {:ok, uart} = UART.start_link()

    state = %{
      config: config,
      uart: uart,
      connection_id: connection_id,
      buffer: <<>>,
      connected: false
    }

    # Attempt connection
    send(self(), :connect)

    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    case UART.open(state.uart, state.config.device,
                   speed: state.config.baud,
                   active: true,
                   framing: Circuits.UART.Framing.None) do
      :ok ->
        Logger.info("Serial port #{state.config.device} opened successfully")

        # Register with router core
        RouterCore.register_connection(state.connection_id, %{
          pid: self(),
          type: :serial,
          allow_msg_ids: state.config[:allow_msg_ids],
          block_msg_ids: state.config[:block_msg_ids]
        })

        {:noreply, %{state | connected: true}}

      {:error, reason} ->
        Logger.error("Failed to open serial port: #{inspect(reason)}, retrying in 5s")
        Process.send_after(self(), :connect, 5000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:circuits_uart, _port, data}, state) do
    # Append to buffer and try to parse MAVLink frames
    new_buffer = state.buffer <> data
    {frames, remaining} = parse_mavlink_frames(new_buffer)

    # Route each parsed frame
    Enum.each(frames, fn frame ->
      RouterCore.route_message(state.connection_id, frame)
    end)

    {:noreply, %{state | buffer: remaining}}
  end

  @impl true
  def handle_info({:send_frame, frame}, state) do
    # Serialize and send frame to serial port
    packet = XMAVLink.pack(frame)
    UART.write(state.uart, packet)
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.connected do
      RouterCore.unregister_connection(state.connection_id)
      UART.close(state.uart)
    end
    :ok
  end

  # Private Functions

  defp parse_mavlink_frames(buffer) do
    # Parse MAVLink frames from byte stream
    # Use XMAVLink parsing utilities
    # Return {[frames], remaining_buffer}

    # Simplified - actual implementation needs proper MAVLink parsing
    {[], buffer}
  end
end
```

#### 2.3 UDP Server Handler

**File:** `lib/router_ex/endpoint/udp_server.ex`
```elixir
defmodule RouterEx.Endpoint.UDPServer do
  @moduledoc """
  Handles UDP server endpoints.
  Listens on a port and tracks multiple clients.
  """

  use GenServer
  require Logger

  alias RouterEx.RouterCore

  # Client API

  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  # Server Callbacks

  @impl true
  def init(config) do
    Logger.info("Starting UDP server: #{config.name} on #{config.address}:#{config.port}")

    # Open UDP socket
    {:ok, socket} = :gen_udp.open(config.port, [
      :binary,
      active: true,
      ip: parse_ip(config.address)
    ])

    connection_id = {:udp_server, config.name}

    # Register with router core
    RouterCore.register_connection(connection_id, %{
      pid: self(),
      type: :udp_server,
      allow_msg_ids: config[:allow_msg_ids],
      block_msg_ids: config[:block_msg_ids]
    })

    state = %{
      config: config,
      socket: socket,
      connection_id: connection_id,
      # Track clients: {ip, port} -> last_seen_timestamp
      clients: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_info({:udp, socket, ip, port, data}, state) do
    client = {ip, port}

    # Update client last seen
    new_clients = Map.put(state.clients, client, System.monotonic_time(:second))

    # Parse MAVLink frame(s)
    case parse_mavlink_packet(data) do
      {:ok, frame} ->
        RouterCore.route_message(state.connection_id, frame)
      {:error, reason} ->
        Logger.debug("Failed to parse MAVLink packet: #{inspect(reason)}")
    end

    {:noreply, %{state | clients: new_clients}}
  end

  @impl true
  def handle_info({:send_frame, frame}, state) do
    # Send to all known clients
    packet = XMAVLink.pack(frame)

    Enum.each(state.clients, fn {{ip, port}, _timestamp} ->
      :gen_udp.send(state.socket, ip, port, packet)
    end)

    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    RouterCore.unregister_connection(state.connection_id)
    :gen_udp.close(state.socket)
    :ok
  end

  # Private Functions

  defp parse_ip(address) when is_binary(address) do
    case :inet.parse_address(String.to_charlist(address)) do
      {:ok, ip} -> ip
      {:error, _} -> {0, 0, 0, 0}
    end
  end

  defp parse_mavlink_packet(data) do
    # Use XMAVLink to parse packet
    # Simplified - needs actual implementation
    {:error, :not_implemented}
  end
end
```

#### 2.4 UDP Client Handler

**File:** `lib/router_ex/endpoint/udp_client.ex`
```elixir
defmodule RouterEx.Endpoint.UDPClient do
  @moduledoc """
  Handles UDP client endpoints (Mode = Normal).
  Sends to a fixed remote address.
  """

  use GenServer
  require Logger

  alias RouterEx.RouterCore

  # Similar structure to UDP Server, but sends to fixed destination
  # Implementation details in Phase 2
end
```

#### 2.5 TCP Server Handler

**File:** `lib/router_ex/endpoint/tcp_server.ex`
```elixir
defmodule RouterEx.Endpoint.TCPServer do
  @moduledoc """
  Handles TCP server for GCS connections (QGroundControl, etc.).
  Manages multiple client connections.
  """

  use GenServer
  require Logger

  alias RouterEx.RouterCore

  # Similar to RTSP server in video-streamer
  # Accepts connections, spawns per-client handlers
  # Implementation details in Phase 2
end
```

### Phase 3: Message Routing & Filtering (Week 5)

#### 3.1 Message Parser

**File:** `lib/router_ex/message_parser.ex`
```elixir
defmodule RouterEx.MessageParser do
  @moduledoc """
  Parses MAVLink messages from byte streams.
  Handles both MAVLink 1.0 and 2.0 protocols.
  """

  # Use XMAVLink.Dialect for parsing
  # Implement stateful parser that can handle partial frames
  # Support frame recovery after errors
end
```

#### 3.2 Message Filter

**File:** `lib/router_ex/message_filter.ex`
```elixir
defmodule RouterEx.MessageFilter do
  @moduledoc """
  Implements message filtering logic.
  Supports AllowMsgIdOut and BlockMsgIdOut rules.
  """

  def should_forward?(frame, endpoint_config) do
    msg_id = frame.message_id

    # Check whitelist
    allowed = case endpoint_config[:allow_msg_ids] do
      nil -> true
      [] -> true
      list -> msg_id in list
    end

    # Check blacklist
    blocked = case endpoint_config[:block_msg_ids] do
      nil -> false
      [] -> false
      list -> msg_id in list
    end

    allowed and not blocked
  end
end
```

#### 3.3 Enhanced Routing Table

Improve RouterCore with:
- System/component tracking (not just system)
- Connection grouping (for parallel links)
- Message deduplication
- Routing metrics and analytics

### Phase 4: Containerization & Deployment (Week 6)

#### 4.1 Multi-Stage Dockerfile

**File:** `apps/router_ex/Dockerfile`
```dockerfile
# ============================================
# Builder Stage
# ============================================
FROM hexpm/elixir:1.18.4-erlang-28.1-alpine-3.22.1 AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    git \
    linux-headers

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy dependency files
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

# Compile dependencies
RUN mix deps.compile

# Copy application source
COPY config ./config
COPY lib ./lib

# Compile and build release
ENV MIX_ENV=prod
RUN mix compile
RUN mix release

# ============================================
# Runtime Stage
# ============================================
FROM alpine:3.22.1

# Install runtime dependencies
RUN apk add --no-cache \
    libstdc++ \
    openssl \
    ncurses-libs

# Create app user
RUN addgroup -g 1000 app && \
    adduser -D -u 1000 -G app app

WORKDIR /app

# Copy release from builder
COPY --from=builder /app/_build/prod/rel/router_ex ./

# Set ownership
RUN chown -R app:app /app

# Note: Will run as root in production for serial port access
# Pod security context handles this

ENV MAVLINK20=1
ENV MIX_ENV=prod

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ps aux | grep -v grep | grep router_ex || exit 1

CMD ["/app/bin/router_ex", "start"]
```

#### 4.2 Kubernetes Deployment

**File:** `deployments/apps/router-ex-deployment.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    name: router-ex
  name: router-ex
  namespace: rpiuav
spec:
  replicas: 1
  selector:
    matchLabels:
      app: router-ex-replicaset
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: router-ex-replicaset
        app.kubernetes.io/name: router-ex-deployment
    spec:
      containers:
      - image: ghcr.io/fancydrones/x500-cm4/router-ex:latest
        name: router-ex
        ports:
        - containerPort: 5760
          name: tcp-server
        - containerPort: 14550
          name: udp-14550
        - containerPort: 14560
          name: udp-14560
        - containerPort: 14561
          name: udp-14561
        - containerPort: 14562
          name: udp-14562
        - containerPort: 14563
          name: udp-14563

        # Environment configuration
        env:
        - name: ROUTER_CONFIG
          valueFrom:
            configMapKeyRef:
              name: rpi4-config
              key: ROUTER_CONFIG
        - name: MAVLINK20
          value: "1"

        # Resource limits
        resources:
          limits:
            cpu: "0.5"
            memory: 500Mi
          requests:
            cpu: "0.25"
            memory: 100Mi

        # Security context
        securityContext:
          privileged: true

        # Volume mounts
        volumeMounts:
        - mountPath: /dev/serial0
          name: serial0

      # Host network for port compatibility
      hostNetwork: true

      # Volumes
      volumes:
      - hostPath:
          path: /dev/serial0
        name: serial0

      # Restart policy
      restartPolicy: Always
---
apiVersion: v1
kind: Service
metadata:
  name: router-ex-service
  namespace: rpiuav
spec:
  ports:
  - name: tcp-server
    port: 5760
    protocol: TCP
    targetPort: 5760
  - name: udp-14550
    port: 14550
    protocol: UDP
    targetPort: 14550
  - name: udp-14560
    port: 14560
    protocol: UDP
    targetPort: 14560
  - name: udp-14561
    port: 14561
    protocol: UDP
    targetPort: 14561
  - name: udp-14562
    port: 14562
    protocol: UDP
    targetPort: 14562
  - name: udp-14563
    port: 14563
    protocol: UDP
    targetPort: 14563
  selector:
    app.kubernetes.io/name: router-ex-deployment
```

#### 4.3 GitHub Actions Workflow

**File:** `.github/workflows/process-router-ex.yaml`
```yaml
name: Process Router-Ex

on:
  push:
    branches:
      - main
    paths:
      - 'apps/router_ex/**'
      - '.github/workflows/process-router-ex.yaml'
  workflow_dispatch:

jobs:
  build-and-deploy:
    uses: ./.github/workflows/process-image-template.yaml
    with:
      app_name: router-ex
      app_path: apps/router_ex
      deployment_file: deployments/apps/router-ex-deployment.yaml
```

### Phase 5: Testing & Validation (Week 7)

#### 5.1 Test Strategy

**Unit Tests:**
- Configuration parser
- Message routing logic
- Message filtering
- Routing table updates

**Integration Tests:**
- Serial port communication
- UDP server/client functionality
- TCP server functionality
- Multi-connection message routing

**Compatibility Tests:**
- Side-by-side comparison with mavlink-router
- Same configuration, verify same behavior
- Message rate and latency benchmarks
- Multi-client scenarios

#### 5.2 Test Setup

**File:** `test/router_ex/router_core_test.exs`
```elixir
defmodule RouterEx.RouterCoreTest do
  use ExUnit.Case, async: true

  alias RouterEx.RouterCore

  setup do
    # Start router core for testing
    {:ok, pid} = start_supervised(RouterCore)
    %{router: pid}
  end

  describe "routing table" do
    test "updates when message received from connection", %{router: router} do
      # Register mock connections
      conn_a = {:test, "conn_a"}
      conn_b = {:test, "conn_b"}

      RouterCore.register_connection(conn_a, %{pid: self(), type: :test})
      RouterCore.register_connection(conn_b, %{pid: self(), type: :test})

      # Create frame from system 1
      frame = create_test_frame(source_system: 1, target_system: 2)

      # Route from conn_a
      RouterCore.route_message(conn_a, frame)

      # Verify routing table updated
      # TODO: Add introspection API for testing
    end
  end

  describe "message routing" do
    test "broadcasts message with target_system = 0" do
      # Test broadcast behavior
    end

    test "routes targeted message to correct connection" do
      # Test targeted routing
    end

    test "does not route back to source" do
      # Test loop prevention
    end
  end
end
```

#### 5.3 Benchmarks

**File:** `test/benchmarks/routing_benchmark.exs`
```elixir
# Measure routing latency and throughput
# Compare with mavlink-router performance
# Target: <1ms routing latency, >10k msg/s throughput
```

### Phase 6: Documentation (Week 8)

#### 6.1 User Documentation

**File:** `apps/router_ex/README.md`
```markdown
# Router-Ex - Elixir MAVLink Router

Elixir-based MAVLink message router for x500-cm4 UAV platform.

## Features

- MAVLink 1.0 and 2.0 protocol support
- Serial (UART), UDP, and TCP connections
- Intelligent message routing with system awareness
- Message filtering (whitelist/blacklist)
- Compatible with mavlink-router configuration
- Hot code reloading
- Comprehensive telemetry

## Configuration

Uses same configuration format as mavlink-router:

```ini
[General]
TcpServerPort=5760
MavlinkDialect=auto

[UartEndpoint FlightController]
Device = /dev/serial0
Baud = 921600

[UdpEndpoint GCS]
Mode = Normal
Address = 10.10.10.70
Port = 14550
```

## Migration from mavlink-router

Router-Ex is a drop-in replacement:

1. Use same ConfigMap configuration
2. Update deployment to use router-ex image
3. Same ports, same behavior
4. Optional: enable additional telemetry features

## Development

```bash
cd apps/router_ex
mix deps.get
mix test
```

## Architecture

See [Architecture Documentation](./docs/architecture.md)
```

#### 6.2 Migration Guide

**File:** `docs/router-ex-migration.md`
- Step-by-step migration from mavlink-router
- Configuration compatibility notes
- Performance comparison
- Rollback procedures
- Troubleshooting

#### 6.3 Operations Guide

**File:** `docs/router-ex-operations.md`
- Deployment procedures
- Monitoring and telemetry
- Performance tuning
- Common issues and solutions

## Success Criteria

### Functional Requirements

- [x] **FR-1:** Support MAVLink 1.0 and 2.0 protocols
- [x] **FR-2:** Serial (UART) connections with configurable baud rate
- [x] **FR-3:** UDP server endpoints (multiple ports)
- [x] **FR-4:** UDP client endpoints (fixed destination)
- [x] **FR-5:** TCP server for GCS connections
- [x] **FR-6:** Intelligent routing based on system awareness
- [x] **FR-7:** Message filtering (AllowMsgIdOut, BlockMsgIdOut)
- [x] **FR-8:** Compatible with existing configuration format
- [x] **FR-9:** Automatic reconnection on connection loss
- [x] **FR-10:** Telemetry and statistics reporting

### Performance Requirements

- **PR-1:** Routing latency: <2ms per message (target: <1ms)
- **PR-2:** Throughput: >5000 msg/s (target: >10000 msg/s)
- **PR-3:** CPU usage: <15% idle, <50% under load
- **PR-4:** Memory usage: <100MB (acceptable: <150MB)
- **PR-5:** Startup time: <5 seconds

### Compatibility Requirements

- **CR-1:** Drop-in replacement for mavlink-router
- **CR-2:** Same port mappings (5760, 14550, 14560-14563)
- **CR-3:** Same configuration format (INI-style)
- **CR-4:** Compatible with existing clients (QGC, ATAK, announcer-ex, etc.)
- **CR-5:** Same message routing behavior

### Operational Requirements

- **OR-1:** Automatic restart on failure (Kubernetes)
- **OR-2:** Graceful shutdown
- **OR-3:** Configuration reload without restart
- **OR-4:** Comprehensive logging
- **OR-5:** Telemetry integration

## Timeline

| Phase | Duration | Deliverables |
|-------|----------|--------------|
| 1 | Week 1-2 | Basic router infrastructure, config parsing |
| 2 | Week 3-4 | Serial, UDP, TCP connection handlers |
| 3 | Week 5 | Message routing, filtering, routing table |
| 4 | Week 6 | Container, Kubernetes, CI/CD |
| 5 | Week 7 | Testing, benchmarking, validation |
| 6 | Week 8 | Documentation, migration guide |

**Total:** 8 weeks to production-ready implementation

## Risk Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Performance not meeting targets | High | Early benchmarking, optimize hot paths, consider NIFs for parsing |
| Circuits.UART compatibility | Medium | Test on actual hardware early, fallback to :gen_serial |
| Configuration parsing complexity | Medium | Comprehensive test coverage, reference implementation analysis |
| XMAVLink limitations | Medium | Contribute fixes upstream, maintain fork if needed |
| Memory overhead concerns | Low | Profile early, optimize GenServer state, consider ETS for routing table |

## Dependencies

**Hardware:**
- Raspberry Pi CM4/CM5
- Serial port access (/dev/serial0)
- Network connectivity

**Software:**
- Elixir 1.18+
- XMAVLink library (~> 0.5.0)
- Circuits.UART (~> 1.5)
- K3s cluster
- Alpine Linux 3.22+

**External Services:**
- None (standalone service)

## Integration Points

**Upstream:**
- Flight controller (serial)
- Ground control station (UDP/TCP)

**Downstream:**
- announcer-ex (UDP)
- video-streamer (via announcer-ex)
- companion web UI
- External GCS applications

**Configuration:**
- rpi4-config ConfigMap (ROUTER_CONFIG key)

## Future Enhancements

### Post-MVP Features

1. **Message Logging:** Save MAVLink traffic to disk for analysis
2. **Message Sniffing:** Forward all traffic to debug endpoint
3. **Web Dashboard:** Real-time router status and statistics
4. **Advanced Filtering:** Regex patterns, rate limiting
5. **Connection Grouping:** Parallel links with shared awareness
6. **Hot Configuration Reload:** Update routes without restart
7. **MAVLink 2 Extensions:** Signing, encryption support
8. **Performance Optimizations:** NIFs for parsing, ETS routing table

### Long-term Vision

- **Unified Platform:** Router-Ex as foundation for all MAVLink services
- **Plugin System:** User-defined message handlers
- **Cloud Integration:** Telemetry forwarding to cloud services
- **Multi-Drone Support:** Route between multiple vehicles

## Appendices

### A. Configuration Format Reference

See existing `rpi4-config` ConfigMap for complete example.

### B. XMAVLink Integration

Router-Ex uses XMAVLink for:
- Message serialization/deserialization
- MAVLink 1.0/2.0 protocol handling
- Dialect support (Common, Ardupilotmega, etc.)

XMAVLink.Router provides basic routing; Router-Ex extends it with:
- Multi-connection management
- Advanced filtering
- Configuration compatibility
- Performance optimizations

### C. Comparison: mavlink-router vs Router-Ex

**Advantages of Router-Ex:**
- Native Elixir integration with other services
- Hot code reloading
- OTP supervision and fault tolerance
- Rich telemetry and observability
- Easier to extend and customize

**Advantages of mavlink-router:**
- Lower memory footprint
- Slightly lower CPU usage
- Battle-tested in production
- Broader community support

**Recommendation:** Use Router-Ex for new deployments; provides better long-term maintainability and integration with Elixir ecosystem.

---

**Document Version:** 1.0
**Date:** 2025-10-23
**Status:** Draft - Ready for Implementation
