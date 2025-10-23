# Router-Ex Configuration Formats

Router-Ex supports multiple configuration formats to provide the best developer experience while maintaining backward compatibility with mavlink-router.

---

## Table of Contents

1. [Configuration Format Options](#configuration-format-options)
2. [Recommended: Elixir Configuration](#recommended-elixir-configuration)
3. [YAML Configuration](#yaml-configuration)
4. [TOML Configuration](#toml-configuration)
5. [Backward Compatible: INI Format](#backward-compatible-ini-format)
6. [Configuration Precedence](#configuration-precedence)
7. [Migration Strategies](#migration-strategies)

---

## Configuration Format Options

Router-Ex supports **four configuration formats**, prioritizing Elixir-native approaches:

| Format | Priority | Best For | Pros | Cons |
|--------|----------|----------|------|------|
| **Elixir** | 1st | New deployments, Elixir ecosystem | Native, type-safe, flexible, hot reload | Elixir knowledge required |
| **YAML** | 2nd | Kubernetes-native, readable | Human-friendly, K8s standard | Extra parsing dependency |
| **TOML** | 3rd | Modern alternative to INI | Better typing than INI, readable | Less common in Elixir |
| **INI** | 4th | Legacy migration | Backward compatibility | Limited structure, no types |

**Recommendation:** Use **Elixir configuration** for new deployments. Use **INI** only for migration from mavlink-router.

---

## Recommended: Elixir Configuration

### Why Elixir Config?

**Advantages:**
- ✅ Native Elixir data structures (maps, lists, atoms)
- ✅ Type safety and compile-time validation
- ✅ Hot code reloading support
- ✅ Follows Elixir conventions (config.exs, runtime.exs)
- ✅ Access to Elixir functions and macros
- ✅ No additional parsing dependencies
- ✅ Better error messages
- ✅ Integration with other Elixir apps (announcer-ex, video-streamer)

### Configuration Structure

**File:** `config/runtime.exs`

```elixir
import Config

# Runtime configuration loaded when release starts
config :router_ex,
  # General settings
  general: [
    tcp_server_port: 5760,
    report_stats: false,
    mavlink_dialect: :auto,
    log_level: :info
  ],

  # Endpoint definitions
  endpoints: [
    # Serial/UART endpoint
    %{
      name: "FlightController",
      type: :uart,
      device: "/dev/serial0",
      baud: 921_600
    },

    # UDP Server endpoint
    %{
      name: "video0",
      type: :udp_server,
      address: "0.0.0.0",
      port: 14560,
      # Message filtering
      allow_msg_ids: [0, 4, 76, 322, 323]
    },

    # UDP Client endpoint
    %{
      name: "GCS",
      type: :udp_client,
      address: "10.10.10.70",
      port: 14550
    },

    # TCP Server (optional, if not using general.tcp_server_port)
    %{
      name: "CustomTCP",
      type: :tcp_server,
      port: 5761
    }
  ]
```

### With Environment Variables

```elixir
import Config

# Helper for parsing environment variables
defmodule ConfigHelpers do
  def parse_int(env_var, default) do
    case System.get_env(env_var) do
      nil -> default
      value -> String.to_integer(value)
    end
  end

  def parse_list(env_var, default) do
    case System.get_env(env_var) do
      nil -> default
      value ->
        value
        |> String.split(",")
        |> Enum.map(&String.to_integer/1)
    end
  end
end

config :router_ex,
  general: [
    tcp_server_port: ConfigHelpers.parse_int("TCP_PORT", 5760),
    report_stats: System.get_env("REPORT_STATS") == "true",
    mavlink_dialect: :auto
  ],

  endpoints: [
    %{
      name: "FlightController",
      type: :uart,
      device: System.get_env("SERIAL_DEVICE", "/dev/serial0"),
      baud: ConfigHelpers.parse_int("SERIAL_BAUD", 921_600)
    },
    %{
      name: "video0",
      type: :udp_server,
      address: "0.0.0.0",
      port: 14560,
      allow_msg_ids: ConfigHelpers.parse_list(
        "VIDEO0_ALLOWED_MSGS",
        [0, 4, 76, 322, 323]
      )
    }
  ]
```

### Advanced: Dynamic Configuration

```elixir
import Config

# Load endpoints from environment or defaults
endpoints =
  case System.get_env("ROUTER_ENDPOINTS") do
    nil ->
      # Default endpoints
      [
        %{name: "FlightController", type: :uart, device: "/dev/serial0", baud: 921_600}
      ]

    json_string ->
      # Load from JSON if provided
      json_string
      |> Jason.decode!()
      |> Enum.map(fn endpoint ->
        # Convert string keys to atoms
        Map.new(endpoint, fn {k, v} -> {String.to_atom(k), v} end)
      end)
  end

config :router_ex,
  general: [tcp_server_port: 5760],
  endpoints: endpoints
```

### Type Specifications

For better type safety, define endpoint schemas:

```elixir
# lib/router_ex/config/schema.ex
defmodule RouterEx.Config.Schema do
  @moduledoc """
  Configuration schemas and validation for Router-Ex.
  """

  @type endpoint_type :: :uart | :udp_server | :udp_client | :tcp_server | :tcp_client

  @type uart_endpoint :: %{
    required(:name) => String.t(),
    required(:type) => :uart,
    required(:device) => String.t(),
    required(:baud) => pos_integer(),
    optional(:allow_msg_ids) => [non_neg_integer()],
    optional(:block_msg_ids) => [non_neg_integer()]
  }

  @type udp_server_endpoint :: %{
    required(:name) => String.t(),
    required(:type) => :udp_server,
    required(:address) => String.t(),
    required(:port) => :inet.port_number(),
    optional(:allow_msg_ids) => [non_neg_integer()],
    optional(:block_msg_ids) => [non_neg_integer()]
  }

  @type endpoint :: uart_endpoint() | udp_server_endpoint() | map()

  @type config :: %{
    general: keyword(),
    endpoints: [endpoint()]
  }

  @doc "Validate configuration at compile time or runtime"
  def validate!(config) do
    # Validation logic
    config
  end
end
```

---

## YAML Configuration

### Why YAML?

**Advantages:**
- ✅ Human-readable and writable
- ✅ Standard in Kubernetes ecosystem
- ✅ Good for ConfigMaps
- ✅ Supports complex nested structures
- ✅ Comments supported

**Disadvantages:**
- ⚠️ Requires `yaml_elixir` or `yamerl` dependency
- ⚠️ No type safety
- ⚠️ Indentation-sensitive

### Configuration Structure

**File:** `config/router.yaml`

```yaml
# Router-Ex Configuration
general:
  tcp_server_port: 5760
  report_stats: false
  mavlink_dialect: auto
  log_level: info

endpoints:
  # Flight controller serial connection
  - name: FlightController
    type: uart
    device: /dev/serial0
    baud: 921600

  # Video component endpoints
  - name: video0
    type: udp_server
    address: 0.0.0.0
    port: 14560
    # Only camera-related messages
    allow_msg_ids:
      - 0    # HEARTBEAT
      - 4    # PING
      - 76   # COMMAND_LONG
      - 322  # CAMERA_INFORMATION
      - 323  # VIDEO_STREAM_INFORMATION

  - name: video1
    type: udp_server
    address: 0.0.0.0
    port: 14561
    allow_msg_ids: [0, 4, 76, 322, 323]

  # Ground control station
  - name: GCS
    type: udp_client
    address: 10.10.10.70
    port: 14550
```

### Loading YAML in Elixir

```elixir
# config/runtime.exs
import Config

# Load YAML configuration
yaml_config =
  case System.get_env("ROUTER_CONFIG_YAML") do
    nil ->
      # Try to load from file
      "config/router.yaml"
      |> File.read!()
      |> YamlElixir.read_from_string!()

    yaml_string ->
      YamlElixir.read_from_string!(yaml_string)
  end

# Convert YAML keys to atoms for Elixir config
config :router_ex,
  general: Enum.map(yaml_config["general"], fn {k, v} -> {String.to_atom(k), v} end),
  endpoints: Enum.map(yaml_config["endpoints"], fn endpoint ->
    Map.new(endpoint, fn {k, v} -> {String.to_atom(k), v} end)
  end)
```

### Kubernetes ConfigMap

```yaml
# config/router-ex-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: router-ex-config
  namespace: rpiuav
data:
  router.yaml: |
    general:
      tcp_server_port: 5760
      report_stats: false

    endpoints:
      - name: FlightController
        type: uart
        device: /dev/serial0
        baud: 921600

      - name: video0
        type: udp_server
        address: 0.0.0.0
        port: 14560
        allow_msg_ids: [0, 4, 76, 322, 323]
```

**Deployment:**
```yaml
volumeMounts:
  - name: config
    mountPath: /etc/router-ex
volumes:
  - name: config
    configMap:
      name: router-ex-config
```

---

## TOML Configuration

### Why TOML?

**Advantages:**
- ✅ More structured than INI
- ✅ Better type support (integers, arrays, tables)
- ✅ Human-readable
- ✅ Good error messages

**Disadvantages:**
- ⚠️ Requires `toml` dependency
- ⚠️ Less common in Elixir ecosystem

### Configuration Structure

**File:** `config/router.toml`

```toml
# Router-Ex Configuration

[general]
tcp_server_port = 5760
report_stats = false
mavlink_dialect = "auto"
log_level = "info"

# Flight controller
[[endpoints]]
name = "FlightController"
type = "uart"
device = "/dev/serial0"
baud = 921600

# Video component 0
[[endpoints]]
name = "video0"
type = "udp_server"
address = "0.0.0.0"
port = 14560
allow_msg_ids = [0, 4, 76, 322, 323]

# Video component 1
[[endpoints]]
name = "video1"
type = "udp_server"
address = "0.0.0.0"
port = 14561
allow_msg_ids = [0, 4, 76, 322, 323]

# Ground control station
[[endpoints]]
name = "GCS"
type = "udp_client"
address = "10.10.10.70"
port = 14550
```

### Loading TOML in Elixir

```elixir
# config/runtime.exs
import Config

# Load TOML configuration
toml_config =
  case System.get_env("ROUTER_CONFIG_TOML") do
    nil ->
      "config/router.toml"
      |> File.read!()
      |> Toml.decode!()

    toml_string ->
      Toml.decode!(toml_string)
  end

config :router_ex,
  general: Enum.map(toml_config["general"], fn {k, v} -> {String.to_atom(k), v} end),
  endpoints: Enum.map(toml_config["endpoints"], fn endpoint ->
    Map.new(endpoint, fn {k, v} -> {String.to_atom(k), v} end)
  end)
```

---

## Backward Compatible: INI Format

For migration from mavlink-router. See [configuration-reference.md](configuration-reference.md) for complete INI format documentation.

**File:** `config/main.conf`

```ini
[General]
TcpServerPort=5760
ReportStats=false
MavlinkDialect=auto

[UartEndpoint FlightController]
Device = /dev/serial0
Baud = 921600

[UdpEndpoint video0]
Mode = Server
Address = 0.0.0.0
Port = 14560
AllowMsgIdOut = 0,4,76,322,323
```

### Loading INI in Elixir

```elixir
# lib/router_ex/config/ini_parser.ex
defmodule RouterEx.Config.IniParser do
  @moduledoc """
  Parser for INI-style configuration (mavlink-router compatibility).
  """

  def parse(content) when is_binary(content) do
    content
    |> String.split("\n")
    |> parse_lines(%{general: [], endpoints: []}, nil)
  end

  defp parse_lines([], acc, _current_section), do: acc

  defp parse_lines([line | rest], acc, current_section) do
    case parse_line(String.trim(line)) do
      {:section, section_name} ->
        parse_lines(rest, acc, section_name)

      {:key_value, key, value} when current_section != nil ->
        acc = add_to_section(acc, current_section, key, value)
        parse_lines(rest, acc, current_section)

      :skip ->
        parse_lines(rest, acc, current_section)
    end
  end

  # Implementation details...
end
```

---

## Configuration Precedence

Router-Ex loads configuration in the following order (later sources override earlier):

1. **Default values** (hardcoded in application)
2. **config/config.exs** (compile-time Elixir config)
3. **config/runtime.exs** (runtime Elixir config)
4. **Configuration files** (YAML/TOML/INI from filesystem or env var)
5. **Environment variables** (individual overrides)

### Example Precedence

```elixir
# 1. Default values (in code)
tcp_port = 5760

# 2. config.exs (compile-time)
config :router_ex, tcp_server_port: 5760

# 3. runtime.exs (runtime)
config :router_ex,
  tcp_server_port: System.get_env("TCP_PORT", "5760") |> String.to_integer()

# 4. Configuration file (if ROUTER_CONFIG_YAML env var is set)
# Loaded in runtime.exs

# 5. Direct environment variable (highest priority)
config :router_ex,
  tcp_server_port: System.get_env("ROUTER_EX_TCP_PORT",
                                  Application.get_env(:router_ex, :tcp_server_port))
```

---

## Migration Strategies

### Strategy 1: Direct Migration (INI → Elixir)

**Best for:** New Elixir-native deployments

1. Convert INI to Elixir config
2. Update deployment to use runtime.exs
3. Remove INI parsing dependency

**Before (INI):**
```ini
[UartEndpoint FlightController]
Device = /dev/serial0
Baud = 921600
```

**After (Elixir):**
```elixir
config :router_ex,
  endpoints: [
    %{
      name: "FlightController",
      type: :uart,
      device: "/dev/serial0",
      baud: 921_600
    }
  ]
```

### Strategy 2: YAML Transition (INI → YAML → Elixir)

**Best for:** Kubernetes-native deployments

1. Convert INI to YAML (easier for ops team)
2. Use YAML in ConfigMaps
3. Eventually migrate to Elixir when ready

**Step 1: INI → YAML**
```yaml
endpoints:
  - name: FlightController
    type: uart
    device: /dev/serial0
    baud: 921600
```

**Step 2: YAML → Elixir (when ready)**
```elixir
config :router_ex, endpoints: [...]
```

### Strategy 3: Dual Support (Gradual Migration)

**Best for:** Large deployments with mixed environments

Support both formats simultaneously:

```elixir
# config/runtime.exs
import Config

config_data = cond do
  # Prefer Elixir-native config if available
  System.get_env("ROUTER_CONFIG_ELIXIR") ->
    load_elixir_config()

  # Fall back to YAML
  System.get_env("ROUTER_CONFIG_YAML") ->
    load_yaml_config()

  # Finally try INI for backward compatibility
  System.get_env("ROUTER_CONFIG") ->
    RouterEx.Config.IniParser.parse(System.get_env("ROUTER_CONFIG"))

  # Use defaults
  true ->
    default_config()
end

config :router_ex,
  general: config_data.general,
  endpoints: config_data.endpoints
```

---

## Recommended Approach

### For New Deployments

**Use Elixir configuration:**

```elixir
# config/runtime.exs
import Config

config :router_ex,
  general: [
    tcp_server_port: System.get_env("TCP_PORT", "5760") |> String.to_integer()
  ],
  endpoints: [
    %{
      name: "FlightController",
      type: :uart,
      device: System.get_env("SERIAL_DEVICE", "/dev/serial0"),
      baud: System.get_env("SERIAL_BAUD", "921600") |> String.to_integer()
    }
  ]
```

**Benefits:**
- Type safety
- Better error messages
- Hot reload support
- Native Elixir integration

### For Migrating from mavlink-router

**Phase 1: Support INI**
- Keep existing INI configuration
- Router-Ex parses INI format
- Zero config changes needed

**Phase 2: Transition to YAML**
- Convert INI → YAML
- Easier for Kubernetes team
- Better structure than INI

**Phase 3: Move to Elixir** (optional)
- Convert YAML → Elixir config
- Full type safety
- Maximum flexibility

---

## Configuration Validation

### Elixir Config Validation

```elixir
defmodule RouterEx.Config.Validator do
  def validate!(config) do
    with :ok <- validate_general(config.general),
         :ok <- validate_endpoints(config.endpoints) do
      config
    else
      {:error, reason} -> raise "Invalid configuration: #{reason}"
    end
  end

  defp validate_general(general) do
    tcp_port = Keyword.get(general, :tcp_server_port)

    cond do
      !is_integer(tcp_port) ->
        {:error, "tcp_server_port must be an integer"}
      tcp_port < 1 or tcp_port > 65535 ->
        {:error, "tcp_server_port must be 1-65535"}
      true ->
        :ok
    end
  end

  defp validate_endpoints(endpoints) when is_list(endpoints) do
    Enum.reduce_while(endpoints, :ok, fn endpoint, :ok ->
      case validate_endpoint(endpoint) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_endpoint(%{type: :uart} = endpoint) do
    cond do
      !Map.has_key?(endpoint, :device) ->
        {:error, "UART endpoint missing required field: device"}
      !Map.has_key?(endpoint, :baud) ->
        {:error, "UART endpoint missing required field: baud"}
      true ->
        :ok
    end
  end
end
```

### Runtime Validation

```elixir
# lib/router_ex/config_manager.ex
def init(_opts) do
  config = load_config()

  # Validate before starting
  validated_config = RouterEx.Config.Validator.validate!(config)

  {:ok, %{config: validated_config}}
end
```

---

## Comparison Summary

| Feature | Elixir | YAML | TOML | INI |
|---------|--------|------|------|-----|
| **Type Safety** | ✅ Excellent | ❌ None | ⚠️ Basic | ❌ None |
| **Validation** | ✅ Compile-time | ⏱️ Runtime | ⏱️ Runtime | ⏱️ Runtime |
| **Comments** | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes |
| **Nesting** | ✅ Unlimited | ✅ Good | ✅ Good | ❌ Limited |
| **Hot Reload** | ✅ Yes | ⏱️ Possible | ⏱️ Possible | ⏱️ Possible |
| **Elixir Native** | ✅ Yes | ❌ No | ❌ No | ❌ No |
| **K8s Integration** | ⚠️ Via env | ✅ ConfigMap | ⚠️ ConfigMap | ⚠️ ConfigMap |
| **Readability** | ⚠️ Elixir knowledge | ✅ Very good | ✅ Good | ⚠️ Limited |
| **Dependencies** | ✅ None | ⚠️ yaml_elixir | ⚠️ toml | ⚠️ Custom parser |

**Recommendation:**
- **Production:** Elixir config (best type safety and integration)
- **Kubernetes:** YAML (best for ops team familiarity)
- **Migration:** INI (temporary backward compatibility)

---

**Document Version:** 1.0
**Last Updated:** 2025-10-23
**Status:** Complete
