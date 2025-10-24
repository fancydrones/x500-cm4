# Router-Ex Configuration Reference

This document provides a complete reference for Router-Ex configuration, including the INI-style format compatible with mavlink-router and additional Elixir-specific options.

---

## Table of Contents

1. [Configuration Overview](#configuration-overview)
2. [General Section](#general-section)
3. [Endpoint Configuration](#endpoint-configuration)
4. [Environment Variables](#environment-variables)
5. [Configuration Examples](#configuration-examples)
6. [Migration from mavlink-router](#migration-from-mavlink-router)

---

## Configuration Overview

### Configuration Sources (Priority Order)

Router-Ex loads configuration from multiple sources, with later sources overriding earlier ones:

1. **Default values** (hardcoded in application)
2. **INI configuration file** (from ROUTER_CONFIG env var or /etc/mavlink-router/main.conf)
3. **Environment variables** (for runtime overrides)
4. **Runtime.exs** (Elixir-specific configuration)

### Configuration Format

Router-Ex uses the same INI-style format as mavlink-router for compatibility:

```ini
[Section]
Key = Value
```

**Sections:**
- `[General]` - Global router settings
- `[UartEndpoint NAME]` - Serial/UART connections
- `[UdpEndpoint NAME]` - UDP connections (server or client mode)
- `[TcpEndpoint NAME]` - TCP connections (optional, for custom setups)

---

## General Section

### Syntax

```ini
[General]
TcpServerPort=5760
ReportStats=false
MavlinkDialect=auto
DebugLogLevel=info
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| **TcpServerPort** | integer | 5760 | Port for TCP server (GCS connections) |
| **ReportStats** | boolean | false | Enable periodic statistics reporting |
| **MavlinkDialect** | string | auto | MAVLink dialect (auto, common, ardupilotmega) |
| **DebugLogLevel** | string | info | Log level (error, warning, info, debug) |

### Examples

**Minimal configuration:**
```ini
[General]
TcpServerPort=5760
```

**Full configuration:**
```ini
[General]
TcpServerPort=5760
ReportStats=true
MavlinkDialect=common
DebugLogLevel=debug
```

### Router-Ex Extensions

Router-Ex adds the following optional parameters:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| **TelemetryEnabled** | boolean | true | Enable telemetry events |
| **StatsInterval** | integer | 10000 | Stats report interval (ms) |
| **EnableHotReload** | boolean | false | Enable configuration hot reload |

**Example:**
```ini
[General]
TcpServerPort=5760
TelemetryEnabled=true
StatsInterval=5000
```

---

## Endpoint Configuration

### UART Endpoints (Serial)

**Syntax:**
```ini
[UartEndpoint NAME]
Device = /dev/ttyX
Baud = BAUDRATE
```

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| **Device** | string | ✅ Yes | - | Serial device path |
| **Baud** | integer | ✅ Yes | - | Baud rate (9600, 57600, 115200, 921600) |
| **AllowMsgIdOut** | list | ❌ No | all | Whitelist of message IDs to forward |
| **BlockMsgIdOut** | list | ❌ No | none | Blacklist of message IDs to block |

**Example:**
```ini
[UartEndpoint FlightController]
Device = /dev/serial0
Baud = 921600
```

**With filtering:**
```ini
[UartEndpoint FlightController]
Device = /dev/serial0
Baud = 921600
# Only forward heartbeat and attitude messages
AllowMsgIdOut = 0,30
```

**Common baud rates:**
- `9600` - Standard low-speed
- `57600` - Common telemetry rate
- `115200` - High-speed telemetry
- `921600` - Very high-speed (requires good cables)

---

### UDP Endpoints

UDP endpoints can operate in two modes:
1. **Server mode**: Listens on a port and accepts connections from multiple clients
2. **Normal mode**: Sends to a fixed destination (client mode)

#### UDP Server Mode

**Syntax:**
```ini
[UdpEndpoint NAME]
Mode = Server
Address = 0.0.0.0
Port = PORT
```

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| **Mode** | string | ✅ Yes | - | Must be "Server" or "server" |
| **Address** | string | ✅ Yes | - | Bind address (0.0.0.0 for all interfaces) |
| **Port** | integer | ✅ Yes | - | UDP port to listen on |
| **AllowMsgIdOut** | list | ❌ No | all | Whitelist of message IDs |
| **BlockMsgIdOut** | list | ❌ No | none | Blacklist of message IDs |

**Example:**
```ini
[UdpEndpoint video0]
Mode = Server
Address = 0.0.0.0
Port = 14560
# Only forward camera-related messages
AllowMsgIdOut = 0,4,76,322,323
```

**Common use cases:**
- Video component endpoints (14560, 14561)
- Additional GCS connections (14550+)
- Custom application endpoints

#### UDP Client Mode (Normal)

**Syntax:**
```ini
[UdpEndpoint NAME]
Mode = Normal
Address = IP_ADDRESS
Port = PORT
```

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| **Mode** | string | ✅ Yes | - | Must be "Normal" or "normal" |
| **Address** | string | ✅ Yes | - | Destination IP address |
| **Port** | integer | ✅ Yes | - | Destination port |
| **AllowMsgIdOut** | list | ❌ No | all | Whitelist of message IDs |
| **BlockMsgIdOut** | list | ❌ No | none | Blacklist of message IDs |

**Example:**
```ini
[UdpEndpoint GCS]
Mode = Normal
Address = 10.10.10.70
Port = 14550
```

**Common use cases:**
- Fixed ground control station
- Remote telemetry logger
- Cloud telemetry forwarding

---

### TCP Endpoints (Optional)

TCP endpoints are less common but supported for specific use cases.

**Syntax:**
```ini
[TcpEndpoint NAME]
Mode = Server|Client
Address = IP_ADDRESS
Port = PORT
```

**Note:** The `[General]` section's `TcpServerPort` provides a built-in TCP server. Custom TCP endpoints are only needed for advanced setups.

---

## Message Filtering

### AllowMsgIdOut (Whitelist)

**Purpose:** Only forward messages with specific IDs

**Format:** Comma-separated list of message IDs

**Example:**
```ini
AllowMsgIdOut = 0,4,76,322,323
```

**Common message IDs:**
- `0` - HEARTBEAT
- `4` - PING
- `30` - ATTITUDE
- `33` - GLOBAL_POSITION_INT
- `76` - COMMAND_LONG
- `322` - CAMERA_INFORMATION
- `323` - VIDEO_STREAM_INFORMATION

**Full list:** See [MAVLink message definitions](https://mavlink.io/en/messages/common.html)

### BlockMsgIdOut (Blacklist)

**Purpose:** Block specific message IDs from being forwarded

**Format:** Comma-separated list of message IDs

**Example:**
```ini
# Block high-frequency debug messages
BlockMsgIdOut = 120,121,122
```

### Filter Precedence

When both `AllowMsgIdOut` and `BlockMsgIdOut` are specified:
1. Message ID is checked against `AllowMsgIdOut` (whitelist)
2. If allowed, checked against `BlockMsgIdOut` (blacklist)
3. Message forwarded only if allowed AND not blocked

**Example:**
```ini
AllowMsgIdOut = 0,30,33,76
BlockMsgIdOut = 33
# Result: Only 0, 30, 76 are forwarded (33 is blocked)
```

---

## Environment Variables

Router-Ex supports environment variable overrides for runtime configuration.

### Standard Variables

| Variable | Type | Description | Example |
|----------|------|-------------|---------|
| **ROUTER_CONFIG** | string | Full INI configuration content | See examples below |
| **MAVLINK20** | boolean | Enable MAVLink 2.0 protocol | `1` or `true` |
| **LOG_LEVEL** | string | Override log level | `debug`, `info`, `warning`, `error` |

### Router-Ex Specific Variables

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| **ROUTER_EX_TELEMETRY** | boolean | Enable telemetry | `true` |
| **ROUTER_EX_STATS_INTERVAL** | integer | Stats interval (ms) | `10000` |
| **ROUTER_EX_HOT_RELOAD** | boolean | Enable config reload | `false` |

### Usage in Kubernetes

```yaml
env:
- name: ROUTER_CONFIG
  valueFrom:
    configMapKeyRef:
      name: rpi4-config
      key: ROUTER_CONFIG
- name: MAVLINK20
  value: "1"
- name: LOG_LEVEL
  value: "info"
```

### Usage in Docker

```bash
docker run -e MAVLINK20=1 \
           -e ROUTER_CONFIG="$(cat main.conf)" \
           router-ex:latest
```

---

## Configuration Examples

### Example 1: Minimal Setup (Flight Controller Only)

**Use case:** Simple drone with just flight controller connection

```ini
[General]
TcpServerPort=5760

[UartEndpoint FlightController]
Device = /dev/serial0
Baud = 921600
```

**What this does:**
- Connects to flight controller on /dev/serial0
- Provides TCP server on port 5760 for QGroundControl
- Forwards all messages between serial and TCP

---

### Example 2: Drone with Video System (Current x500-cm4 Setup)

**Use case:** Full x500-cm4 configuration with announcer-ex

```ini
[General]
TcpServerPort=5760
ReportStats=false
MavlinkDialect=auto

[UartEndpoint FlightControllerSerial]
Device = /dev/serial0
Baud = 921600

[UdpEndpoint FlightControllerUDP]
Mode = Server
Address = 0.0.0.0
Port = 14555

[UdpEndpoint video0]
Mode = Server
Address = 0.0.0.0
Port = 14560
# Only camera-related messages
AllowMsgIdOut = 0,4,76,322,323

[UdpEndpoint video1]
Mode = Server
Address = 0.0.0.0
Port = 14561
AllowMsgIdOut = 0,4,76,322,323

[UdpEndpoint GCS]
Mode = Normal
Address = 10.10.10.70
Port = 14550
```

**What this does:**
- Connects to flight controller via serial
- Provides TCP server for QGroundControl (port 5760)
- Provides UDP server for alternative FC connection (port 14555)
- Provides filtered UDP servers for video components (ports 14560, 14561)
- Forwards to ground station at 10.10.10.70:14550

---

### Example 3: Development/Testing Setup

**Use case:** Testing with SITL (Software In The Loop)

```ini
[General]
TcpServerPort=5760
ReportStats=true
DebugLogLevel=debug

[TcpEndpoint SITL]
Mode = Client
Address = 127.0.0.1
Port = 5762

[UdpEndpoint QGC]
Mode = Server
Address = 0.0.0.0
Port = 14550
```

**What this does:**
- Connects to SITL on localhost:5762
- Provides UDP server for QGroundControl
- Enables debug logging and statistics

---

### Example 4: High-Security Setup with Filtering

**Use case:** Restrict message types for security

```ini
[General]
TcpServerPort=5760

[UartEndpoint FlightController]
Device = /dev/serial0
Baud = 921600

[UdpEndpoint ExternalGCS]
Mode = Server
Address = 0.0.0.0
Port = 14550
# Only allow monitoring, block commands
AllowMsgIdOut = 0,30,33,74,147
BlockMsgIdOut = 76,77,180,181,182
```

**Allowed messages:**
- 0: HEARTBEAT (status)
- 30: ATTITUDE (monitoring)
- 33: GLOBAL_POSITION_INT (monitoring)
- 74: VFR_HUD (monitoring)
- 147: BATTERY_STATUS (monitoring)

**Blocked messages:**
- 76: COMMAND_LONG (commands)
- 77: COMMAND_INT (commands)
- 180-182: SET_* (parameter changes)

---

### Example 5: Multi-Drone Setup

**Use case:** Router managing multiple drones

```ini
[General]
TcpServerPort=5760

[UartEndpoint Drone1]
Device = /dev/ttyUSB0
Baud = 921600

[UartEndpoint Drone2]
Device = /dev/ttyUSB1
Baud = 921600

[UdpEndpoint GCS]
Mode = Server
Address = 0.0.0.0
Port = 14550
```

**What this does:**
- Connects to two drones on different serial ports
- Provides single UDP endpoint for GCS
- Routes messages based on system ID awareness

---

## Migration from mavlink-router

### Configuration Compatibility

Router-Ex is **100% compatible** with mavlink-router configuration files. You can use your existing `main.conf` file without modifications.

### Migration Steps

1. **Backup existing configuration:**
   ```bash
   cp /etc/mavlink-router/main.conf /etc/mavlink-router/main.conf.backup
   ```

2. **Verify configuration:**
   ```bash
   # Test parse with Router-Ex
   kubectl set env deployment/router-ex ROUTER_CONFIG="$(cat main.conf)"
   ```

3. **Update deployment:**
   ```bash
   # Change image from router to router-ex
   kubectl set image deployment/router router=router-ex:latest -n rpiuav
   ```

4. **Monitor startup:**
   ```bash
   kubectl logs -f deployment/router-ex -n rpiuav
   ```

5. **Verify functionality:**
   - Check flight controller connection
   - Verify GCS connectivity
   - Test announcer-ex connection
   - Monitor for errors

### Configuration Differences

Router-Ex supports all mavlink-router options plus additional features:

**New in Router-Ex:**
- `TelemetryEnabled` - Enable/disable telemetry
- `StatsInterval` - Configure stats reporting frequency
- `EnableHotReload` - Allow configuration reload without restart

**Future Router-Ex features** (planned):
- Message rate limiting
- Connection grouping
- Advanced filtering (regex patterns)
- Message logging to file

---

## Configuration Validation

### Validation Rules

Router-Ex validates configuration on startup:

1. **Required fields** must be present
2. **Port numbers** must be valid (1-65535)
3. **Baud rates** must be supported
4. **IP addresses** must be valid
5. **Message IDs** must be integers
6. **Modes** must be valid (Server, Normal)

### Common Validation Errors

**Error:** `Missing required field: Device`
```ini
# Wrong:
[UartEndpoint FC]
Baud = 921600

# Correct:
[UartEndpoint FC]
Device = /dev/serial0
Baud = 921600
```

**Error:** `Invalid baud rate: 12345`
```ini
# Wrong:
Baud = 12345

# Correct:
Baud = 115200
```

**Error:** `Invalid IP address: 999.999.999.999`
```ini
# Wrong:
Address = 999.999.999.999

# Correct:
Address = 10.10.10.70
```

### Testing Configuration

**Before deployment:**
```bash
# Parse configuration locally
cd apps/router_ex
iex -S mix

config_text = File.read!("/path/to/main.conf")
RouterEx.ConfigManager.parse_config(config_text)
```

**After deployment:**
```bash
# Check logs for configuration errors
kubectl logs deployment/router-ex -n rpiuav | grep -i "config"
```

---

## Troubleshooting

### Configuration Not Loading

**Symptom:** Router starts with default configuration

**Causes:**
1. ROUTER_CONFIG environment variable not set
2. ConfigMap not mounted correctly
3. Parse error in configuration

**Solution:**
```bash
# Check environment variable
kubectl exec deployment/router-ex -n rpiuav -- env | grep ROUTER_CONFIG

# Check ConfigMap
kubectl get configmap rpi4-config -n rpiuav -o yaml

# Check logs for parse errors
kubectl logs deployment/router-ex -n rpiuav | grep -i error
```

### Endpoint Not Starting

**Symptom:** No connection to serial/UDP/TCP

**Causes:**
1. Device not available (/dev/serial0 missing)
2. Port already in use
3. Permission denied
4. Invalid configuration

**Solution:**
```bash
# Check device exists
kubectl exec deployment/router-ex -n rpiuav -- ls -l /dev/serial0

# Check port binding
kubectl exec deployment/router-ex -n rpiuav -- netstat -tuln | grep 14560

# Check container privileges
kubectl get pod -n rpiuav -o yaml | grep privileged
```

### Messages Not Being Filtered

**Symptom:** All messages forwarded despite AllowMsgIdOut

**Causes:**
1. Filter configuration incorrect
2. Message ID typo
3. Filter not applied to correct endpoint

**Solution:**
```bash
# Check configuration parsing
kubectl logs deployment/router-ex -n rpiuav | grep "Filter"

# Verify message IDs
# Enable debug logging to see filter decisions
kubectl set env deployment/router-ex LOG_LEVEL=debug -n rpiuav
```

---

## Best Practices

### 1. Use Descriptive Names

```ini
# Good:
[UartEndpoint FlightController]
[UdpEndpoint CameraComponent]
[UdpEndpoint GroundControlStation]

# Avoid:
[UartEndpoint uart1]
[UdpEndpoint udp1]
```

### 2. Document Your Filters

```ini
[UdpEndpoint RestrictedGCS]
Mode = Server
Address = 0.0.0.0
Port = 14550
# Allow: Heartbeat, position, attitude
# Block: Commands (security)
AllowMsgIdOut = 0,30,33
BlockMsgIdOut = 76,77
```

### 3. Start Minimal, Add as Needed

Begin with basic configuration and add endpoints/filters as requirements grow.

### 4. Use Environment Variables for Deployment-Specific Values

```ini
# In main.conf (generic)
[UdpEndpoint GCS]
Mode = Normal
Address = ${GCS_IP}
Port = 14550
```

Note: Router-Ex doesn't currently support variable substitution, but you can use environment variables in Kubernetes deployment to customize the entire ROUTER_CONFIG.

### 5. Test Configuration Changes Locally First

Always validate configuration changes in development before deploying to production.

---

## Reference Tables

### Standard MAVLink Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 5760 | TCP | QGroundControl default |
| 14550 | UDP | GCS default |
| 14555 | UDP | Alternative GCS |
| 14560+ | UDP | Additional components |

### Common Baud Rates

| Baud Rate | Use Case |
|-----------|----------|
| 9600 | Legacy telemetry |
| 57600 | Standard telemetry |
| 115200 | High-speed telemetry |
| 230400 | Very high-speed |
| 921600 | Maximum speed (short cables) |

### Common Message IDs (Subset)

| ID | Name | Description |
|----|------|-------------|
| 0 | HEARTBEAT | System status |
| 4 | PING | Link test |
| 30 | ATTITUDE | Vehicle attitude |
| 33 | GLOBAL_POSITION_INT | GPS position |
| 76 | COMMAND_LONG | Command message |
| 322 | CAMERA_INFORMATION | Camera info |
| 323 | VIDEO_STREAM_INFORMATION | Video stream info |

Full list: https://mavlink.io/en/messages/common.html

---

**Document Version:** 1.0
**Last Updated:** 2025-10-23
**Status:** Complete
