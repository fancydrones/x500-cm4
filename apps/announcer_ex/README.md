# AnnouncerEx

An Elixir implementation of the MAVLink camera announcer service. This application acts as a MAVLink camera component, broadcasting camera capabilities and responding to camera protocol commands.

## Features

- **Heartbeat Broadcasting**: Sends heartbeat messages every second identifying as a camera component
- **Camera Protocol Support**: Handles MAVLink camera commands including:
  - Camera information requests
  - Video stream information requests
  - Camera settings requests
  - Video stream status requests
  - Storage information requests (ACK only)
  - Camera zoom commands (no-op)
  - Camera capture status requests (unsupported response)
- **External Router Connection**: Connects to external MAVLink router service via UDP
- **OTP Supervision**: Built on Elixir/OTP for fault tolerance and crash recovery

## Configuration

The application is configured via environment variables:

- `CAMERA_ID` - MAVLink component ID (e.g., 100)
- `CAMERA_NAME` - Name of the camera (e.g., "Front")
- `CAMERA_URL` - RTSP stream URL
- `SYSTEM_ID` - MAVLink system ID
- `SYSTEM_HOST` - Router service hostname (default: "router-service.rpiuav.svc.cluster.local")
- `SYSTEM_PORT` - Router service port (default: "14560")
- `MAVLINK20` - Set to "1" to use MAVLink 2.0 protocol

## Installation

```bash
mix deps.get
mix compile
```

## Running Tests

```bash
mix test
```

## Running Locally

```bash
export CAMERA_ID=100
export CAMERA_NAME="Test Camera"
export CAMERA_URL="rtsp://localhost:554/stream"
export SYSTEM_ID=1
export SYSTEM_HOST=localhost
export SYSTEM_PORT=14550
export MAVLINK20=1

mix run --no-halt
```

## Building Docker Image

```bash
docker build -t announcer-ex:latest .
```

## Deployment

The application is deployed to Kubernetes using the deployment file at:
`/deployments/apps/announcer-ex-deployment.yaml`

## Architecture

- `AnnouncerEx.Application` - OTP application supervisor
- `AnnouncerEx.CameraManager` - GenServer managing camera lifecycle and heartbeats
- `AnnouncerEx.CommandHandler` - Handles incoming MAVLink camera commands
- `AnnouncerEx.MessageBuilder` - Builds MAVLink messages for responses
- `AnnouncerEx.Config` - Environment variable configuration management

## Performance

Expected performance improvements over Python implementation:
- Memory: ~30-50MB (vs ~200MB Python)
- CPU: <0.1 core idle, <0.3 core active (vs 0.5 Python)
- Latency: <5ms response time (vs ~10-20ms Python)
- Startup: <2s (vs ~5s Python)

## Dependencies

- `xmavlink` ~> 0.4.1 - MAVLink protocol implementation
- `xmavlink_util` ~> 0.4.2 - MAVLink Common dialect and utilities

