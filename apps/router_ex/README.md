# Router-Ex

Elixir-based MAVLink message router for the x500-cm4 UAV platform.

Router-Ex intelligently routes MAVLink messages between serial, UDP, and TCP connections, providing a native Elixir alternative to the C/C++ mavlink-router.

## Features

- ✅ **MAVLink Protocol Support**: MAVLink 1.0 and 2.0
- ✅ **Multiple Connection Types**: Serial (UART), UDP (server/client), TCP (server/client)
- ✅ **Intelligent Routing**: System awareness-based message routing
- ✅ **Message Filtering**: Whitelist/blacklist message IDs per endpoint
- ✅ **Flexible Configuration**: Elixir-native, YAML, TOML, or INI formats
- ✅ **Hot Code Reloading**: Update routing logic without restart
- ✅ **OTP Supervision**: Automatic fault recovery
- ✅ **Rich Telemetry**: Comprehensive metrics and monitoring
- ⏳ **Backward Compatible**: INI format support for migration from mavlink-router

## Status

**Phase 1: COMPLETE** ✅
- Application structure
- Configuration management
- Router core
- Telemetry setup

**Phase 2-6: IN PROGRESS** 🚧
- Connection handlers (Serial, UDP, TCP)
- Message parsing and filtering
- Containerization
- Testing and validation
- Documentation

See [PRD-004](../../PRDs/004-router-ex/README.md) for complete implementation plan.

## Installation

Router-Ex is part of the x500-cm4 monorepo. Dependencies are managed at the application level.

```bash
cd apps/router_ex
mix deps.get
```

## Configuration

Router-Ex supports multiple configuration formats. The recommended approach is Elixir-native configuration.

### Elixir Configuration (Recommended)

**config/runtime.exs:**
```elixir
config :router_ex,
  general: [
    tcp_server_port: 5760,
    report_stats: false,
    mavlink_dialect: :auto
  ],
  endpoints: [
    %{
      name: "FlightController",
      type: :uart,
      device: "/dev/serial0",
      baud: 921_600
    },
    %{
      name: "video0",
      type: :udp_server,
      address: "0.0.0.0",
      port: 14560,
      allow_msg_ids: [0, 4, 76, 322, 323]
    },
    %{
      name: "GCS",
      type: :udp_client,
      address: "10.10.10.70",
      port: 14550
    }
  ]
```

### Also Supported

- **YAML**: For Kubernetes ConfigMaps
- **TOML**: Modern alternative to INI
- **INI**: Backward compatibility with mavlink-router

See [configuration-formats.md](../../PRDs/004-router-ex/configuration-formats.md) for complete documentation.

## Development

```bash
# Start in interactive mode
iex -S mix

# Compile
mix compile

# Run tests
mix test

# Format code
mix format
```

## Architecture

```
┌─────────────────────────────────────────┐
│     Router-Ex Application               │
│                                         │
│  ┌─────────────────────────────────┐  │
│  │    RouterCore (GenServer)        │  │
│  │  - Message routing               │  │
│  │  - System awareness tracking     │  │
│  │  - Message filtering             │  │
│  └─────────────────────────────────┘  │
│                                         │
│  ┌─────────────────────────────────┐  │
│  │   ConfigManager                  │  │
│  │  - Multi-format support          │  │
│  │  - Hot reload capability         │  │
│  └─────────────────────────────────┘  │
│                                         │
│  ┌─────────────────────────────────┐  │
│  │   Telemetry                      │  │
│  │  - Performance metrics           │  │
│  │  - Connection events             │  │
│  └─────────────────────────────────┘  │
│                                         │
│  ┌─────────────────────────────────┐  │
│  │   Endpoint.Supervisor            │  │
│  │  - Serial handlers (Phase 2)     │  │
│  │  - UDP handlers (Phase 2)        │  │
│  │  - TCP handlers (Phase 2)        │  │
│  └─────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

## Documentation

- [Implementation Plan](../../PRDs/004-router-ex/implementation_plan.md) - Complete technical spec
- [Configuration Formats](../../PRDs/004-router-ex/configuration-formats.md) - Configuration guide
- [Testing Guide](../../PRDs/004-router-ex/testing-guide.md) - Testing strategy
- [API Documentation](https://hexdocs.pm/router_ex) - Generated API docs (run `mix docs`)

## License

Part of the x500-cm4 project.
