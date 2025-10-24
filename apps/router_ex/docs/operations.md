# Router-Ex Operations Guide

This guide covers deployment, configuration, monitoring, and troubleshooting for Router-Ex in production environments.

## Table of Contents

1. [Deployment](#deployment)
2. [Configuration](#configuration)
3. [Monitoring](#monitoring)
4. [Troubleshooting](#troubleshooting)
5. [Performance Tuning](#performance-tuning)
6. [Backup and Recovery](#backup-and-recovery)

## Deployment

### Prerequisites

- Elixir 1.14+ and Erlang/OTP 25+
- Kubernetes cluster (for containerized deployment)
- Access to serial devices (for UART endpoints)
- Network ports available for MAVLink communication

### Container Deployment (Recommended)

Router-Ex is deployed as a containerized application in the `rpiuav` namespace:

```bash
# Build the container image
docker buildx build \
  --platform linux/arm64 \
  --build-arg APP_NAME=router_ex \
  -t ghcr.io/fancydrones/x500-cm4/router-ex:latest \
  -f apps/router_ex/Dockerfile .

# Push to registry
docker push ghcr.io/fancydrones/x500-cm4/router-ex:latest

# Deploy to Kubernetes
kubectl apply -f deployments/apps/router-ex-deployment.yaml
kubectl apply -f deployments/apps/router-ex-service.yaml
```

### Local Development Deployment

```bash
# Install dependencies
mix deps.get

# Compile the application
mix compile

# Run in interactive mode
iex -S mix

# Run in production mode
MIX_ENV=prod mix release
_build/prod/rel/router_ex/bin/router_ex start
```

## Configuration

Router-Ex supports multiple configuration formats for backward compatibility with mavlink-router.

### Configuration Priority

Configuration is loaded in the following order (later sources override earlier):

1. Application defaults (in `config/runtime.exs`)
2. INI configuration file (mavlink-router compatible)
3. TOML configuration file
4. YAML configuration file
5. `ROUTER_CONFIG` environment variable

### Configuration via Environment Variable (Recommended for Kubernetes)

The `ROUTER_CONFIG` environment variable accepts INI, YAML, or TOML format:

**INI Format (mavlink-router compatible):**

```ini
[General]
TcpServerPort=5760
ReportStats=false
MavlinkDialect=common

[UartEndpoint FlightController]
Device=/dev/serial0
Baud=921600

[UdpEndpoint GroundStation]
Mode=Server
Address=0.0.0.0
Port=14550

[UdpEndpoint QGroundControl]
Mode=Normal
Address=192.168.1.100
Port=14550
AllowMsgIdOut=0,1,33,147
```

**YAML Format:**

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
    address: 0.0.0.0
    port: 14550

  - name: QGroundControl
    type: udp_client
    address: 192.168.1.100
    port: 14550
    allow_msg_ids: [0, 1, 33, 147]
```

### Kubernetes ConfigMap Configuration

Router-Ex loads configuration from the `rpi4-config` ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: rpi4-config
  namespace: rpiuav
data:
  ROUTER_CONFIG: |
    [General]
    TcpServerPort=5760

    [UartEndpoint FlightController]
    Device=/dev/serial0
    Baud=921600

    [UdpEndpoint GCS]
    Mode=Server
    Address=0.0.0.0
    Port=14550
```

Update the ConfigMap and restart the pod:

```bash
kubectl edit configmap rpi4-config -n rpiuav
kubectl rollout restart deployment/router-ex -n rpiuav
```

### Configuration Reload

Router-Ex supports dynamic configuration reload without restart:

```bash
# Via RPC (if deployed in Kubernetes)
kubectl exec -it deployment/router-ex -n rpiuav -- \
  /app/bin/router_ex rpc "RouterEx.ConfigManager.reload_config()"

# Via IEx console
iex> RouterEx.ConfigManager.reload_config()
```

### Endpoint Types

#### UART Endpoint (Serial)

```ini
[UartEndpoint FlightController]
Device=/dev/serial0
Baud=921600
FlowControl=false
```

Parameters:
- `Device`: Serial device path (e.g., `/dev/serial0`, `/dev/ttyUSB0`)
- `Baud`: Baud rate (57600, 115200, 921600, etc.)
- `FlowControl`: Enable hardware flow control (default: false)

#### UDP Server Endpoint

```ini
[UdpEndpoint GroundStation]
Mode=Server
Address=0.0.0.0
Port=14550
```

Listens for incoming UDP connections and tracks client addresses.

Parameters:
- `Mode`: Must be "Server"
- `Address`: Bind address (0.0.0.0 for all interfaces)
- `Port`: UDP port to listen on

#### UDP Client Endpoint

```ini
[UdpEndpoint RemoteGCS]
Mode=Normal
Address=192.168.1.100
Port=14550
```

Sends messages to a specific UDP address/port.

Parameters:
- `Mode`: Must be "Normal" (or omit for default)
- `Address`: Target IP address
- `Port`: Target UDP port

#### TCP Server Endpoint

```ini
[TcpEndpoint MissionPlanner]
Mode=Server
Address=0.0.0.0
Port=5760
```

Accepts incoming TCP connections.

Parameters:
- `Mode`: Must be "Server"
- `Address`: Bind address
- `Port`: TCP port to listen on

#### TCP Client Endpoint

```ini
[TcpEndpoint RemoteServer]
Mode=Normal
Address=192.168.1.200
Port=5760
```

Connects to a remote TCP server.

Parameters:
- `Mode`: Must be "Normal"
- `Address`: Remote server address
- `Port`: Remote server port

### Message Filtering

Filter messages per endpoint using allow lists (whitelist) or block lists (blacklist):

**Allow List (Whitelist):**
```ini
[UdpEndpoint FilteredGCS]
Mode=Server
Address=0.0.0.0
Port=14560
# Only allow HEARTBEAT(0), SYS_STATUS(1), ATTITUDE(33)
AllowMsgIdOut=0,1,33
```

**Block List (Blacklist):**
```ini
[UdpEndpoint VideoStream]
Mode=Server
Address=0.0.0.0
Port=14561
# Block large messages like CAMERA_IMAGE_CAPTURED
BlockMsgIdOut=263
```

**Combined Filtering:**
When both are specified, allow list is checked first, then block list:
```ini
AllowMsgIdOut=0,1,33,147,253
BlockMsgIdOut=253
# Result: Messages 0,1,33,147 are allowed (253 is blocked)
```

## Monitoring

### Health Checks

Router-Ex provides health check endpoints for Kubernetes liveness and readiness probes:

**Liveness Probe:**
```yaml
livenessProbe:
  exec:
    command:
    - /app/bin/router_ex
    - rpc
    - "Process.whereis(RouterEx.RouterCore) != nil"
  initialDelaySeconds: 10
  periodSeconds: 30
```

**Readiness Probe:**
```yaml
readinessProbe:
  exec:
    command:
    - /app/bin/router_ex
    - rpc
    - "length(RouterEx.RouterCore.get_connections()) > 0"
  initialDelaySeconds: 5
  periodSeconds: 10
```

### Logs

View router logs:

```bash
# Kubernetes deployment
kubectl logs -f deployment/router-ex -n rpiuav

# Filter for errors
kubectl logs deployment/router-ex -n rpiuav | grep -i error

# Follow specific events
kubectl logs -f deployment/router-ex -n rpiuav | grep -E "Registered|Routed"
```

**Log Levels:**
- `debug`: Detailed routing and message flow information
- `info`: Connection events, statistics, startup/shutdown
- `warning`: Recoverable errors, retries
- `error`: Serious errors requiring attention

### Statistics

Router-Ex tracks message routing statistics:

```bash
# Get current statistics via RPC
kubectl exec deployment/router-ex -n rpiuav -- \
  /app/bin/router_ex rpc "RouterEx.RouterCore.get_stats()"

# Output:
# %{
#   packets_received: 15234,
#   packets_sent: 45678,
#   bytes_received: 1234567,
#   bytes_sent: 3456789,
#   packets_filtered: 123
# }
```

### Telemetry Events

Router-Ex emits telemetry events that can be consumed by monitoring tools:

**Connection Events:**
- `[:router_ex, :connection, :registered]` - New connection registered
- `[:router_ex, :connection, :unregistered]` - Connection removed

**Message Events:**
- `[:router_ex, :message, :routed]` - Message routed successfully
- `[:router_ex, :message, :filtered]` - Message filtered by policy

**Endpoint Events:**
- `[:router_ex, :endpoint, :started]` - Endpoint started
- `[:router_ex, :endpoint, :stopped]` - Endpoint stopped
- `[:router_ex, :endpoint, :error]` - Endpoint error occurred

### Viewing Active Connections

```bash
# List all active connections
kubectl exec deployment/router-ex -n rpiuav -- \
  /app/bin/router_ex rpc "RouterEx.RouterCore.get_connections()"

# View routing table
kubectl exec deployment/router-ex -n rpiuav -- \
  /app/bin/router_ex rpc "RouterEx.RouterCore.get_routing_table()"
```

## Troubleshooting

### Common Issues

#### 1. No Messages Being Routed

**Symptoms:**
- Zero packets in statistics
- Endpoints registered but no message flow

**Diagnosis:**
```bash
# Check if RouterCore is running
kubectl exec deployment/router-ex -n rpiuav -- \
  /app/bin/router_ex rpc "Process.whereis(RouterEx.RouterCore)"

# Check active connections
kubectl exec deployment/router-ex -n rpiuav -- \
  /app/bin/router_ex rpc "RouterEx.RouterCore.get_connections()"

# View logs for errors
kubectl logs deployment/router-ex -n rpiuav | grep -i error
```

**Solutions:**
- Verify endpoint configuration is correct
- Check network connectivity to remote endpoints
- Ensure serial device permissions (for UART endpoints)
- Verify MAVLink messages are actually being sent from source

#### 2. Messages Filtered Unexpectedly

**Symptoms:**
- `packets_filtered` count increasing
- Expected messages not arriving at destination

**Diagnosis:**
```bash
# Check endpoint filter configuration
kubectl exec deployment/router-ex -n rpiuav -- \
  /app/bin/router_ex rpc "RouterEx.ConfigManager.get_config()"

# Monitor filtered messages
kubectl logs -f deployment/router-ex -n rpiuav | grep filtered
```

**Solutions:**
- Review `AllowMsgIdOut` and `BlockMsgIdOut` settings
- Ensure message IDs are correct (decimal, not hex)
- Remember: AllowMsgIdOut is a whitelist (only listed IDs pass)
- Check for conflicting allow/block rules

#### 3. Serial Port Access Denied

**Symptoms:**
- Error: "Permission denied" when opening serial device
- UART endpoint fails to start

**Diagnosis:**
```bash
# Check device permissions
kubectl exec deployment/router-ex -n rpiuav -- ls -la /dev/serial0

# Check privileged mode
kubectl get pod -n rpiuav -o yaml | grep -A 5 securityContext
```

**Solutions:**
- Ensure pod is running in privileged mode:
  ```yaml
  securityContext:
    privileged: true
  ```
- Verify hostPath volume is mounted:
  ```yaml
  volumeMounts:
  - name: serial-device
    mountPath: /dev/serial0
  ```
- Check serial device exists on host node

#### 4. High Memory Usage

**Symptoms:**
- Pod OOMKilled
- Memory usage growing continuously

**Diagnosis:**
```bash
# Check memory usage
kubectl top pod -n rpiuav | grep router-ex

# Review memory limits
kubectl get deployment router-ex -n rpiuav -o yaml | grep -A 5 resources
```

**Solutions:**
- Increase memory limits in deployment:
  ```yaml
  resources:
    limits:
      memory: 500Mi
    requests:
      memory: 200Mi
  ```
- Check for message buffer buildup
- Review message routing patterns for loops

#### 5. Configuration Not Loading

**Symptoms:**
- Default configuration used instead of custom config
- ConfigMap changes not reflected

**Diagnosis:**
```bash
# Check ConfigMap contents
kubectl get configmap rpi4-config -n rpiuav -o yaml

# Verify environment variable in pod
kubectl exec deployment/router-ex -n rpiuav -- env | grep ROUTER_CONFIG

# Check config loading logs
kubectl logs deployment/router-ex -n rpiuav | grep -i "Loading configuration"
```

**Solutions:**
- Verify ConfigMap key name matches (`ROUTER_CONFIG`)
- Restart pod after ConfigMap changes:
  ```bash
  kubectl rollout restart deployment/router-ex -n rpiuav
  ```
- Check configuration format (INI/YAML/TOML) is valid
- Review logs for parsing errors

#### 6. Connection Drops / Reconnection Issues

**Symptoms:**
- TCP/UDP connections dropping frequently
- Clients disconnecting and not reconnecting

**Diagnosis:**
```bash
# Monitor connection events
kubectl logs -f deployment/router-ex -n rpiuav | grep -E "Connection|Disconnect"

# Check network policies
kubectl get networkpolicy -n rpiuav
```

**Solutions:**
- Review network stability
- Check firewall rules
- Verify keepalive settings for TCP connections
- Ensure client applications handle reconnection

### Debug Mode

Enable debug logging for detailed troubleshooting:

```bash
# Set log level via environment variable
kubectl set env deployment/router-ex LOG_LEVEL=debug -n rpiuav

# Or in config/runtime.exs
config :logger, level: :debug
```

### Crash Dumps

If Router-Ex crashes, examine the crash dump:

```bash
# Find crash dumps
kubectl exec deployment/router-ex -n rpiuav -- ls -la /app/erl_crash.dump

# Copy crash dump for analysis
kubectl cp rpiuav/router-ex-pod:/app/erl_crash.dump ./crash.dump

# Analyze with Erlang
erl -eval "rb:start([{report_dir, \".\"}]), rb:show()."
```

## Performance Tuning

### Message Throughput

Router-Ex is designed to handle high message throughput. Typical performance:

- **Serial (UART)**: Up to 921600 baud (~115 KB/s)
- **UDP**: Limited by network bandwidth
- **TCP**: Limited by network bandwidth
- **Routing overhead**: <1ms per message

### Optimization Tips

1. **Use UDP over TCP** when possible for lower latency
2. **Filter unnecessary messages** to reduce routing overhead
3. **Limit statistics reporting** (set `report_stats: false`)
4. **Use efficient MAVLink dialect** (common vs. all)
5. **Batch message routing** is automatic (via GenServer casts)

### Resource Limits

Recommended Kubernetes resource limits:

```yaml
resources:
  limits:
    cpu: "0.5"
    memory: 500Mi
  requests:
    cpu: "0.25"
    memory: 100Mi
```

For high-throughput scenarios:
```yaml
resources:
  limits:
    cpu: "1.0"
    memory: 1Gi
  requests:
    cpu: "0.5"
    memory: 256Mi
```

### Network Configuration

For minimal latency:

```yaml
spec:
  hostNetwork: true  # Use host network namespace
  dnsPolicy: ClusterFirstWithHostNet
```

**Note:** Using `hostNetwork` means the pod uses the host's network ports directly, which can conflict with other services.

## Backup and Recovery

### Configuration Backup

Backup your Router-Ex configuration:

```bash
# Backup ConfigMap
kubectl get configmap rpi4-config -n rpiuav -o yaml > router-ex-config-backup.yaml

# Backup deployment
kubectl get deployment router-ex -n rpiuav -o yaml > router-ex-deployment-backup.yaml
```

### Disaster Recovery

1. **Pod Failure**: Kubernetes automatically restarts failed pods
2. **Configuration Loss**: Restore from ConfigMap backup
3. **Complete Cluster Failure**: Redeploy from Git repository

```bash
# Restore from backup
kubectl apply -f router-ex-config-backup.yaml
kubectl apply -f router-ex-deployment-backup.yaml
```

### State Recovery

Router-Ex is stateless except for:
- **Routing table**: Rebuilt automatically from observed messages
- **Statistics**: Reset on restart (not persisted)

No external state storage is required.

## Security Considerations

### Network Security

1. **Firewall Rules**: Restrict MAVLink ports to trusted networks
2. **TLS/Encryption**: Not supported in MAVLink protocol (use VPN for sensitive deployments)
3. **Authentication**: MAVLink has no built-in authentication

### Pod Security

```yaml
securityContext:
  privileged: true  # Required for serial device access
  runAsNonRoot: false  # Required for device access
  capabilities:
    add:
    - SYS_ADMIN  # For device management
```

**Note:** Privileged mode is required for serial device access but increases security risk. Consider using device plugins for production.

### Configuration Security

- Store sensitive configuration in Kubernetes Secrets instead of ConfigMaps
- Use RBAC to restrict access to router-ex namespace
- Audit configuration changes via Git

## Maintenance

### Routine Maintenance Tasks

**Daily:**
- Monitor pod health and resource usage
- Review error logs

**Weekly:**
- Check routing statistics for anomalies
- Review connection stability

**Monthly:**
- Update container images
- Review and optimize configuration
- Backup configuration

### Updating Router-Ex

```bash
# Pull latest image
docker pull ghcr.io/fancydrones/x500-cm4/router-ex:latest

# Rolling update
kubectl set image deployment/router-ex \
  router-ex=ghcr.io/fancydrones/x500-cm4/router-ex:latest \
  -n rpiuav

# Monitor rollout
kubectl rollout status deployment/router-ex -n rpiuav

# Rollback if needed
kubectl rollout undo deployment/router-ex -n rpiuav
```

## Support and Resources

### Documentation

- [README.md](../README.md) - Project overview
- [Architecture Guide](architecture.md) - System architecture
- [API Documentation](https://hexdocs.pm/router_ex) - Generated API docs

### Troubleshooting Resources

- **Logs**: Primary source of diagnostic information
- **RPC Commands**: Runtime introspection and control
- **Telemetry**: Real-time metrics and events

### Getting Help

1. Check logs for error messages
2. Review this operations guide
3. Consult the troubleshooting section
4. Open an issue on GitHub with:
   - Log excerpts
   - Configuration (sanitized)
   - Steps to reproduce
   - Expected vs actual behavior

## Appendix

### Useful Commands Reference

```bash
# Health check
kubectl exec deployment/router-ex -n rpiuav -- \
  /app/bin/router_ex rpc "Process.whereis(RouterEx.RouterCore) != nil"

# Get statistics
kubectl exec deployment/router-ex -n rpiuav -- \
  /app/bin/router_ex rpc "RouterEx.RouterCore.get_stats()"

# List connections
kubectl exec deployment/router-ex -n rpiuav -- \
  /app/bin/router_ex rpc "RouterEx.RouterCore.get_connections()"

# View routing table
kubectl exec deployment/router-ex -n rpiuav -- \
  /app/bin/router_ex rpc "RouterEx.RouterCore.get_routing_table()"

# Reload configuration
kubectl exec deployment/router-ex -n rpiuav -- \
  /app/bin/router_ex rpc "RouterEx.ConfigManager.reload_config()"

# Get current config
kubectl exec deployment/router-ex -n rpiuav -- \
  /app/bin/router_ex rpc "RouterEx.ConfigManager.get_config()"

# View logs
kubectl logs -f deployment/router-ex -n rpiuav

# Restart deployment
kubectl rollout restart deployment/router-ex -n rpiuav

# Scale deployment
kubectl scale deployment/router-ex --replicas=0 -n rpiuav
kubectl scale deployment/router-ex --replicas=1 -n rpiuav
```

### MAVLink Message ID Reference (Common)

Commonly used message IDs for filtering:

| ID  | Message Name              | Description                    |
|-----|---------------------------|--------------------------------|
| 0   | HEARTBEAT                 | System heartbeat               |
| 1   | SYS_STATUS                | System status                  |
| 4   | PING                      | Network ping                   |
| 30  | ATTITUDE                  | Attitude (roll, pitch, yaw)    |
| 32  | LOCAL_POSITION_NED        | Local position                 |
| 33  | GLOBAL_POSITION_INT       | Global GPS position            |
| 74  | VFR_HUD                   | HUD display metrics            |
| 76  | COMMAND_LONG              | Command with parameters        |
| 147 | BATTERY_STATUS            | Battery information            |
| 253 | STATUSTEXT                | Status text messages           |
| 322 | CAMERA_INFORMATION        | Camera specifications          |
| 323 | CAMERA_SETTINGS           | Camera settings                |

For complete message definitions, see [MAVLink Common Messages](https://mavlink.io/en/messages/common.html).
