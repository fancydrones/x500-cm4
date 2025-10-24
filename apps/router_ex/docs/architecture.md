# RouterEx Architecture

This document describes the architecture of RouterEx, a high-performance MAVLink message router built with Elixir/OTP.

## Table of Contents

1. [Overview](#overview)
2. [System Architecture](#system-architecture)
3. [Supervision Tree](#supervision-tree)
4. [Message Flow](#message-flow)
5. [Routing Logic](#routing-logic)
6. [Configuration Management](#configuration-management)
7. [Endpoint Types](#endpoint-types)
8. [Telemetry and Monitoring](#telemetry-and-monitoring)
9. [Error Handling and Fault Tolerance](#error-handling-and-fault-tolerance)

## Overview

RouterEx is designed as a drop-in replacement for mavlink-router, providing intelligent routing of MAVLink messages between multiple endpoints. It leverages Elixir's OTP framework for fault tolerance, concurrency, and scalability.

### Design Principles

1. **Fault Tolerance**: OTP supervision trees ensure automatic recovery from crashes
2. **Concurrency**: Each endpoint runs in its own process for parallel message handling
3. **Flexibility**: Support for multiple configuration formats and endpoint types
4. **Observability**: Built-in telemetry and health monitoring
5. **Performance**: Efficient message routing with minimal overhead (<1ms per message)

### Key Features

- MAVLink v1 and v2 protocol support
- Multiple endpoint types (UART, UDP, TCP)
- Intelligent system-aware routing
- Per-endpoint message filtering
- Hot configuration reload
- Comprehensive telemetry

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         RouterEx Application                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    Supervision Tree                       │  │
│  │                                                            │  │
│  │  ┌─────────────┐  ┌──────────────┐  ┌────────────────┐  │  │
│  │  │ RouterCore  │  │ConfigManager │  │HealthMonitor   │  │  │
│  │  │  (routing)  │  │ (config mgmt)│  │ (health checks)│  │  │
│  │  └─────────────┘  └──────────────┘  └────────────────┘  │  │
│  │                                                            │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │         Endpoint Supervisor                         │  │  │
│  │  │  ┌───────┐  ┌───────┐  ┌───────┐  ┌───────────┐  │  │  │
│  │  │  │ UART  │  │  UDP  │  │  TCP  │  │ Telemetry │  │  │  │
│  │  │  └───────┘  └───────┘  └───────┘  └───────────┘  │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Supervision Tree

RouterEx uses a hierarchical supervision tree following OTP best practices:

```
RouterEx.Application (Supervisor)
│
├── RouterEx.RouterCore (GenServer)
│   └── Manages routing table and connection registry
│
├── RouterEx.ConfigManager (GenServer)
│   └── Loads and manages configuration
│
├── RouterEx.HealthMonitor (GenServer)
│   └── Provides health check endpoints
│
├── RouterEx.Endpoint.Supervisor (DynamicSupervisor)
│   │
│   ├── RouterEx.Endpoint.Serial (GenServer)
│   │   └── Handles UART communication
│   │
│   ├── RouterEx.Endpoint.UdpServer (GenServer)
│   │   └── Accepts UDP clients and tracks addresses
│   │
│   ├── RouterEx.Endpoint.UdpClient (GenServer)
│   │   └── Sends messages to specific UDP address
│   │
│   ├── RouterEx.Endpoint.TcpServer (GenServer)
│   │   └── Accepts TCP connections
│   │
│   └── RouterEx.Endpoint.TcpClient (GenServer)
│       └── Maintains TCP connection to remote server
│
└── RouterEx.Telemetry (Module)
    └── Telemetry event handlers and metrics
```

### Supervision Strategies

- **Application Supervisor**: `one_for_one` - If a child crashes, only that child is restarted
- **Endpoint Supervisor**: `one_for_one` - Endpoints are independent and don't affect each other
- **Restart Strategy**: `:permanent` for critical processes (RouterCore, ConfigManager)
- **Restart Strategy**: `:transient` for endpoints (restart only on abnormal exit)

## Message Flow

### Inbound Message Flow

```
External Source (Flight Controller, GCS, etc.)
        │
        │ MAVLink Frame
        ▼
┌─────────────────┐
│    Endpoint     │  1. Receive raw bytes
│  (UDP/TCP/UART) │  2. Buffer incomplete frames
└────────┬────────┘
         │ Binary data
         ▼
┌─────────────────┐
│  MAVLink.Parser │  3. Parse MAVLink frames
│                 │  4. Validate CRC
└────────┬────────┘
         │ Parsed frame map
         ▼
┌─────────────────┐
│   RouterCore    │  5. Update routing table
│                 │  6. Determine target endpoints
│                 │  7. Apply message filters
│                 │  8. Update statistics
└────────┬────────┘
         │ Frame + target list
         ▼
┌─────────────────┐
│    Endpoint     │  9. Serialize frame
│  (destination)  │ 10. Send to network/serial
└─────────────────┘
         │
         │ MAVLink Frame
         ▼
External Destination
```

### Routing Decision Flow

```
           Receive Frame
                 │
                 ▼
        Update Routing Table
        (source_system → conn_id)
                 │
                 ▼
           Extract Target
           (from payload)
                 │
                 ▼
         ┌───────┴────────┐
         │                │
     Target = 0       Target ≠ 0
    (Broadcast)      (Targeted)
         │                │
         ▼                ▼
    All conns     Routing table lookup
    except            for target
    source                │
         │         ┌──────┴──────┐
         │         │             │
         │      Found        Not found
         │      conns         (new system)
         │         │             │
         └─────────┴─────────────┘
                   │
                   ▼
           Apply Filters
           (allow/block lists)
                   │
                   ▼
            Send to Targets
```

## Routing Logic

### Routing Table

The RouterCore maintains a routing table that maps system IDs to connection IDs:

```elixir
routing_table = %{
  1 => MapSet.new([{:uart, "FlightController"}]),
  255 => MapSet.new([{:udp_server, "GCS1"}, {:udp_server, "GCS2"}])
}
```

### System Awareness

- Each time a message is received from a connection, the source system ID is recorded
- Messages are routed to connections that have previously seen the target system
- Unknown target systems result in broadcast to all connections (except source)

### Loop Prevention

Messages are never routed back to their source connection:

```elixir
# Always exclude source connection from targets
candidates
|> Enum.reject(fn {conn_id, _} -> conn_id == source_conn_id end)
```

### Message Filtering

Each endpoint can specify:

1. **Allow List (Whitelist)**: Only specified message IDs pass
2. **Block List (Blacklist)**: All messages except specified IDs pass
3. **Combined**: Allow list checked first, then block list

```elixir
allowed = if allow_list, do: msg_id in allow_list, else: true
blocked = if block_list, do: msg_id in block_list, else: false

forward? = allowed and not blocked
```

## Configuration Management

### Configuration Sources

Configuration is loaded in priority order:

1. **Environment Variable** (`ROUTER_CONFIG`): Highest priority
2. **Application Config**: From config files
3. **Default Config**: Fallback if no config found

### Supported Formats

```
ConfigManager
    │
    ├── INI Parser (mavlink-router compatible)
    │   └── Parses [General] and [*Endpoint NAME] sections
    │
    ├── YAML Parser (Kubernetes-friendly)
    │   └── Parses YAML with general: and endpoints:
    │
    └── TOML Parser (modern alternative)
        └── Parses TOML with [general] and [[endpoints]]
```

### Configuration Reload

```
User/System
    │
    │ reload_config()
    ▼
ConfigManager
    │
    │ 1. Parse new configuration
    │ 2. Validate endpoints
    │ 3. Update state
    ▼
Endpoint.Supervisor
    │
    │ 4. Stop old endpoints
    │ 5. Start new endpoints
    ▼
Active Endpoints
```

## Endpoint Types

### UART Endpoint

```
┌──────────────────────┐
│   UART Endpoint      │
│                      │
│  ┌────────────────┐  │
│  │ Circuits.UART  │  │  Serial device communication
│  └────────────────┘  │
│         │            │
│         │ Bytes      │
│         ▼            │
│  ┌────────────────┐  │
│  │ Frame Buffer   │  │  Accumulate partial frames
│  └────────────────┘  │
│         │            │
│         │ Frames     │
│         ▼            │
│  ┌────────────────┐  │
│  │  RouterCore    │  │  Route to other endpoints
│  └────────────────┘  │
└──────────────────────┘
```

### UDP Server Endpoint

```
┌──────────────────────┐
│  UDP Server          │
│                      │
│  ┌────────────────┐  │
│  │  :gen_udp      │  │  Bind to port
│  │  (server mode) │  │
│  └────────────────┘  │
│         │            │
│         │ Packets    │
│         ▼            │
│  ┌────────────────┐  │
│  │ Client Tracker │  │  Track {IP, Port} of senders
│  └────────────────┘  │
│         │            │
│         │ Frames     │
│         ▼            │
│  ┌────────────────┐  │
│  │  RouterCore    │  │
│  └────────────────┘  │
└──────────────────────┘

Client tracking allows bidirectional communication:
- Inbound: Frame from {IP1, Port1} → tracked
- Outbound: Frame to all tracked clients
```

### UDP Client Endpoint

```
┌──────────────────────┐
│  UDP Client          │
│                      │
│  ┌────────────────┐  │
│  │  :gen_udp      │  │  Send to specific address
│  │  (client mode) │  │
│  └────────────────┘  │
│         │            │
│         │ Frames     │
│         ▼            │
│  Target: 192.168.1.100:14550
│                      │
└──────────────────────┘
```

### TCP Server Endpoint

```
┌──────────────────────┐
│  TCP Server          │
│                      │
│  ┌────────────────┐  │
│  │  :gen_tcp      │  │  Listen on port
│  │  (acceptor)    │  │
│  └────────────────┘  │
│         │            │
│         │ Accept     │
│         ▼            │
│  ┌────────────────┐  │
│  │ Client Handler │  │  One per connected client
│  └────────────────┘  │
│         │            │
│         │ Frames     │
│         ▼            │
│  ┌────────────────┐  │
│  │  RouterCore    │  │
│  └────────────────┘  │
└──────────────────────┘
```

## Telemetry and Monitoring

### Telemetry Events

RouterEx emits telemetry events for all major operations:

```
[:router_ex, :connection, :registered]
    %{count: 1}
    %{connection_id: {:udp_server, "GCS"}, type: :udp_server}

[:router_ex, :connection, :unregistered]
    %{count: 1}
    %{connection_id: {:udp_server, "GCS"}}

[:router_ex, :message, :routed]
    %{count: 1, targets: 2, filtered: 0}
    %{source: {:uart, "FC"}, source_system: 1}

[:router_ex, :endpoint, :started]
    %{count: 1}
    %{endpoint: {:udp_server, "GCS"}, type: :udp_server}

[:router_ex, :endpoint, :stopped]
    %{count: 1}
    %{endpoint: {:udp_server, "GCS"}}

[:router_ex, :endpoint, :error]
    %{count: 1}
    %{endpoint: {:uart, "FC"}, error: :disconnected}
```

### Statistics Tracking

RouterCore maintains running statistics:

```elixir
%{
  packets_received: 15234,    # Total messages received
  packets_sent: 45678,        # Total messages forwarded
  bytes_received: 1234567,    # Total bytes received
  bytes_sent: 3456789,        # Total bytes sent
  packets_filtered: 123       # Messages blocked by filters
}
```

### Health Checks

The HealthMonitor provides endpoints for Kubernetes health probes:

```
Liveness Probe:
  Check if RouterCore process is alive
  → Process.whereis(RouterCore) != nil

Readiness Probe:
  Check if at least one endpoint is registered
  → length(get_connections()) > 0
```

## Error Handling and Fault Tolerance

### Supervision Strategy

```
Application crashes → Entire app restarts (rare)
    │
    ├─ RouterCore crashes → Restarted, state rebuilt from messages
    │
    ├─ ConfigManager crashes → Restarted, config reloaded
    │
    ├─ Endpoint crashes → Restarted individually
    │   │
    │   ├─ UART error → Retry connection
    │   ├─ UDP error → Recreate socket
    │   └─ TCP error → Reconnect to server
    │
    └─ HealthMonitor crashes → Restarted, no state loss
```

### Error Recovery

**UART Endpoint**:
- Serial device unplugged → Retry connection every 5 seconds
- Read error → Log warning, continue operation
- Write error → Buffer message, retry on next write

**UDP Endpoint**:
- Socket error → Recreate socket, resume operation
- Send failure → Log warning, drop packet (UDP is lossy)

**TCP Endpoint**:
- Connection lost → Attempt reconnection with exponential backoff
- Send failure → Close connection, trigger reconnection
- Accept error → Log error, continue accepting new connections

**RouterCore**:
- Unexpected message → Log warning, ignore
- Unknown connection → Silently drop message
- Routing table corruption → Rebuild from next received messages

### Graceful Degradation

1. **No Configuration**: Uses default (empty) configuration, endpoints can be added at runtime
2. **Endpoint Failure**: Other endpoints continue operating normally
3. **Parse Error**: Logs error, drops malformed frame, continues parsing next frame
4. **Filter Error**: Logs error, allows message through (fail-open for safety)

## Performance Characteristics

### Routing Latency

- **Target**: <1ms per message
- **Typical**: 0.1-0.5ms for small messages
- **Overhead**: Minimal - routing is O(1) lookup, O(N) filtering where N = number of endpoints

### Throughput

- **Target**: >10,000 messages/second
- **Bottleneck**: Network I/O, not routing logic
- **Scalability**: Linear with number of endpoints (each runs in parallel)

### Memory Usage

- **Base**: ~50-100 MB for application
- **Per Endpoint**: ~1-5 MB depending on type
- **Routing Table**: O(S×E) where S = number of systems, E = endpoints per system
- **Frame Buffers**: ~4KB per endpoint for partial frame buffering

### CPU Usage

- **Idle**: <1% CPU
- **Light Load** (100 msg/s): 1-3% CPU
- **Heavy Load** (10k msg/s): 10-30% CPU
- **Bottleneck**: MAVLink parsing and serialization

## Deployment Architecture

### Container Deployment

```
┌────────────────────────────────────────┐
│         Kubernetes Pod                  │
│                                         │
│  ┌──────────────────────────────────┐  │
│  │     RouterEx Container            │  │
│  │                                   │  │
│  │  Environment:                     │  │
│  │    ROUTER_CONFIG=<configmap>     │  │
│  │                                   │  │
│  │  Volumes:                         │  │
│  │    /dev/serial0 (hostPath)       │  │
│  │                                   │  │
│  │  Ports:                           │  │
│  │    5760/tcp  (MAVLink TCP)       │  │
│  │    14550/udp (GCS UDP)           │  │
│  │    14560-14563/udp (Video)       │  │
│  └──────────────────────────────────┘  │
└────────────────────────────────────────┘
```

### Network Modes

**Host Network** (Recommended for RPI):
```yaml
spec:
  hostNetwork: true  # Direct access to host network stack
  dnsPolicy: ClusterFirstWithHostNet
```

**Bridge Network** (Standard):
```yaml
spec:
  hostNetwork: false
  ports:
    - containerPort: 5760
      protocol: TCP
```

## Security Considerations

### Attack Surface

1. **Network Endpoints**: Exposed to network traffic
   - Mitigation: Use firewall rules, restrict to trusted networks
   - No authentication in MAVLink protocol

2. **Configuration Injection**: Environment variable injection
   - Mitigation: Validate all configuration, sanitize inputs
   - Use Kubernetes Secrets for sensitive data

3. **Serial Device Access**: Requires privileged mode
   - Mitigation: Minimal privilege escalation, only required capabilities
   - Consider device plugins for production

### Defense in Depth

1. **Input Validation**: All configuration and messages validated
2. **Error Handling**: Fail-safe defaults, never crash on bad input
3. **Resource Limits**: Kubernetes resource constraints prevent DoS
4. **Audit Logging**: All configuration changes logged
5. **Telemetry**: Monitor for anomalous behavior

## Future Enhancements

### Planned Features

1. **Message Priority Queuing**: Prioritize critical messages (HEARTBEAT, COMMAND_ACK)
2. **Connection Grouping**: Logical groups of endpoints with shared routing
3. **Rate Limiting**: Per-endpoint message rate limits
4. **Message Replay**: Record and replay MAVLink sessions
5. **Web UI**: Real-time monitoring and configuration interface
6. **TLS Support**: Encrypted TCP connections for sensitive deployments

### Performance Optimizations

1. **Binary NIF**: Native implemented functions for parsing hot paths
2. **Zero-Copy Routing**: Avoid frame serialization/deserialization
3. **Connection Pooling**: Reuse TCP connections
4. **Message Batching**: Batch small messages for network efficiency

---

## References

- [MAVLink Protocol](https://mavlink.io/)
- [Elixir OTP Guide](https://elixir-lang.org/getting-started/mix-otp/introduction-to-mix.html)
- [Telemetry Documentation](https://hexdocs.pm/telemetry/)
- [Operations Guide](operations.md)
