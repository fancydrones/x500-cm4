# Plan: Reimplement Announcer App in Elixir

## Overview
Create a new Elixir application `announcer_ex` that replaces the Python announcer using xmavlink and xmavlink_util libraries. The app connects to the **external MAVLink router** service (running separately) via UDP.

## Current Python Announcer Features Analysis

**Core Functionality:**
1. Connects to external MAVLink router via UDP (`udpout:{SYSTEM_HOST}:{SYSTEM_PORT}`)
2. Acts as MAVLink camera component (system_id from env, component_id = CAMERA_ID)
3. Heartbeat broadcasting (every 1 second)
4. Handles MAVLink camera protocol commands:
   - `MAV_CMD_REQUEST_CAMERA_INFORMATION` → sends `CAMERA_INFORMATION`
   - `MAV_CMD_REQUEST_VIDEO_STREAM_INFORMATION` → sends `VIDEO_STREAM_INFORMATION`
   - `MAV_CMD_REQUEST_CAMERA_SETTINGS` → sends `CAMERA_SETTINGS`
   - `MAV_CMD_REQUEST_VIDEO_STREAM_STATUS` → sends `VIDEO_STREAM_STATUS`
   - `MAV_CMD_REQUEST_CAMERA_CAPTURE_STATUS` → responds with UNSUPPORTED
   - `MAV_CMD_REQUEST_STORAGE_INFORMATION` → ACKs but doesn't send data
   - `MAV_CMD_SET_CAMERA_ZOOM` → ACKs (no-op)
5. Parameter handling (PARAM_EXT_REQUEST_READ, PARAM_EXT_SET) - stub implementation (unused)
6. Graceful shutdown on SIGINT/SIGTERM
7. Environment-based configuration

## Implementation Steps

### 1. Create New Elixir Application Structure
- Generate new Mix project: `mix new announcer_ex --sup`
- Location: `/Users/royveshovda/src/fancydrones/x500-cm4/apps/announcer_ex/`
- Add dependencies: `xmavlink ~> 0.3.x`, `xmavlink_util ~> 0.4.1`

### 2. Configure MAVLink Connection to External Router
**File:** `config/config.exs`

- Set dialect to `Common`
- Configure connection as **UDP out to external router**:
  ```elixir
  config :xmavlink,
    dialect: Common,
    system: {:system, "SYSTEM_ID", 1},
    component: {:system, "CAMERA_ID", 100},
    connections: [{:system, "ROUTER_CONNECTION"}]
  ```

**File:** `config/runtime.exs` (for runtime env vars)
- Build connection string: `"udpout:#{SYSTEM_HOST}:#{SYSTEM_PORT}"`
- Read from environment variables:
  - `SYSTEM_HOST` (default: "router-service.rpiuav.svc.cluster.local")
  - `SYSTEM_PORT` (default: "14560")
  - `SYSTEM_ID` (MAVLink system ID)
  - `CAMERA_ID` (MAVLink component ID, e.g., 100)
  - `CAMERA_NAME` (e.g., "Front")
  - `CAMERA_URL` (RTSP stream URL)

### 3. Create Main Camera Manager GenServer
**File:** `lib/announcer_ex/camera_manager.ex`

**Responsibilities:**
- Subscribe to MAVLink `COMMAND_LONG` messages targeting this component
- Maintain camera state (camera_id, camera_name, stream_url)
- Send heartbeat every 1000ms via timer
- Handle incoming commands and dispatch to handlers
- Send responses via XMAVLink.Router.send_message/1

**State Structure:**
```elixir
%{
  camera_id: integer,
  camera_name: String.t(),
  stream_url: String.t(),
  system_id: integer,
  boot_time: integer (monotonic time)
}
```

**Key Implementation Details:**
- `init/1`: Subscribe with `XMAVLink.Router.subscribe([message: Common.Message.CommandLong])`
- Start heartbeat timer: `Process.send_after(self(), :send_heartbeat, 1000)`
- `handle_info({:mavlink_message, frame}, state)`: Route commands to handlers
- `handle_info(:send_heartbeat, state)`: Send heartbeat, reschedule timer

### 4. Implement Command Handlers Module
**File:** `lib/announcer_ex/command_handler.ex`

**Functions:**
- `handle_command/2` - Main dispatcher based on command ID
- `handle_request_camera_information/2` - Send ACK + `CAMERA_INFORMATION`
- `handle_request_video_stream_information/2` - Send ACK + `VIDEO_STREAM_INFORMATION`
- `handle_request_camera_settings/2` - Send ACK + `CAMERA_SETTINGS`
- `handle_request_video_stream_status/2` - Send ACK + `VIDEO_STREAM_STATUS`
- `handle_request_storage_information/2` - Send ACK only
- `handle_request_capture_status/2` - Send ACK with UNSUPPORTED
- `handle_set_camera_zoom/2` - Send ACK (no-op)

**Important:**
- Extract source_system and source_component from incoming frame
- Send `COMMAND_ACK` as targeted message (not broadcast)
- Send data messages (CAMERA_INFORMATION, etc.) as broadcast
- Use `XMAVLink.Router.send_message/1` for all outgoing messages

### 5. Implement Message Builder Module
**File:** `lib/announcer_ex/message_builder.ex`

**Functions:**
- `build_heartbeat/0` - Returns `%Common.Message.Heartbeat{}`
  - type: `:mav_type_camera`
  - autopilot: `:mav_autopilot_generic`
  - system_status: `:mav_state_standby`
  - mavlink_version: 3

- `build_camera_information/1` - Returns `%Common.Message.CameraInformation{}`
  - vendor_name: camera_name (padded to 32 bytes)
  - model_name: camera_name (padded to 32 bytes)
  - firmware_version: 1
  - resolution_h: 1280, resolution_v: 720
  - flags: `:camera_cap_flags_has_video_stream`
  - cam_definition_version: 1

- `build_video_stream_information/1` - Returns `%Common.Message.VideoStreamInformation{}`
  - stream_id: 1, count: 1
  - type: `:video_stream_type_rtsp`
  - flags: `:video_stream_status_flags_running`
  - framerate: 30, resolution_h: 1280, resolution_v: 720
  - bitrate: 5000
  - rotation: 0, hfov: 63
  - name: camera_name (padded to 32 bytes)
  - uri: stream_url (padded to 160 bytes)

- `build_camera_settings/1` - Returns `%Common.Message.CameraSettings{}`
  - mode_id: 1, zoomLevel: 1.0, focusLevel: 1.0

- `build_video_stream_status/1` - Returns `%Common.Message.VideoStreamStatus{}`
  - stream_id: 1, flags: `:video_stream_status_flags_running`
  - resolution_h: 1280, resolution_v: 720
  - bitrate: 5000, rotation: 0, hfov: 63

- `build_command_ack/3` - Returns `%Common.Message.CommandAck{}`
  - command: command_id
  - result: result_enum (`:mav_result_accepted` or `:mav_result_unsupported`)
  - target_system: source_system, target_component: source_component

**Helpers:**
- `boot_timestamp/1` - Calculate milliseconds since boot
- `pad_string/2` - Pad string to specific byte length with zeros

### 6. Create Application Supervisor
**File:** `lib/announcer_ex/application.ex`

**Start XMAVLink application first:**
```elixir
def start(_type, _args) do
  # XMAVLink is a separate application, ensure it's started
  Application.ensure_all_started(:xmavlink)

  children = [
    AnnouncerEx.CameraManager
  ]

  opts = [strategy: :one_for_one, name: AnnouncerEx.Supervisor]
  Supervisor.start_link(children, opts)
end
```

**Note:** XMAVLink.Router runs in its own supervision tree (from xmavlink app)

### 7. Configuration Management
**File:** `lib/announcer_ex/config.ex`

**Functions:**
- `camera_url!/0` - Get CAMERA_URL or raise
- `camera_id!/0` - Get CAMERA_ID as integer or raise
- `camera_name!/0` - Get CAMERA_NAME or raise
- `system_host!/0` - Get SYSTEM_HOST or raise
- `system_port!/0` - Get SYSTEM_PORT as integer or raise
- `system_id!/0` - Get SYSTEM_ID as integer or raise
- `router_connection_string!/0` - Build "udpout:host:port"

**Validation:**
- Ensure all required vars are present at startup
- Parse integers with proper error messages
- Fail fast with clear error messages

### 8. Create Dockerfile
**File:** `Dockerfile`

```dockerfile
FROM hexpm/elixir:1.15.7-erlang-26.1.2-alpine-3.18.4 AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache build-base git

# Install hex and rebar
RUN mix local.hex --force && mix local.rebar --force

# Copy dependency files
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy application files
COPY lib ./lib
COPY config ./config

# Compile and build release
ENV MIX_ENV=prod
RUN mix compile
RUN mix release

# Runtime stage
FROM alpine:3.18.4

RUN apk add --no-cache libstdc++ openssl ncurses-libs

WORKDIR /app

COPY --from=builder /app/_build/prod/rel/announcer_ex ./

ENV MAVLINK20=1

CMD ["/app/bin/announcer_ex", "start"]
```

### 9. Create Kubernetes Deployment
**File:** `/deployments/apps/announcer-ex-deployment.yaml`

- Same structure as `announcer-deployment.yaml`
- Image: `ghcr.io/fancydrones/x500-cm4/announcer-ex:latest`
- Environment variables (same as Python version):
  - CAMERA_URL, CAMERA_ID, CAMERA_NAME
  - SYSTEM_HOST, SYSTEM_PORT, SYSTEM_ID
  - MAVLINK20=1
- Resources: CPU 1/0.5, Memory 500Mi/200Mi

### 10. CI/CD Pipeline
**File:** `.github/workflows/process-announcer-ex.yaml`

- Trigger on changes to `apps/announcer_ex/**`
- Build Docker image with Elixir/Alpine
- Push to `ghcr.io/fancydrones/x500-cm4/announcer-ex`
- Update deployment image tag

## Test Plan

### Unit Tests

**`test/announcer_ex/message_builder_test.exs`**
- ✓ Heartbeat message has correct type and autopilot
- ✓ Camera information has HAS_VIDEO_STREAM flag
- ✓ Video stream information encodes RTSP URL correctly (160 bytes)
- ✓ Camera name padding (32 bytes)
- ✓ Command ACK with target system/component
- ✓ Boot timestamp calculation

**`test/announcer_ex/command_handler_test.exs`**
- ✓ Dispatcher routes to correct handler based on command ID
- ✓ Each handler returns correct ACK result code
- ✓ Handlers return correct message types
- ✓ Unknown commands ignored gracefully

**`test/announcer_ex/config_test.exs`**
- ✓ Load all environment variables correctly
- ✓ Raise on missing required variables
- ✓ Parse integers correctly
- ✓ Build connection string correctly

### Integration Tests

**`test/announcer_ex/camera_manager_test.exs`**
- ✓ GenServer starts with valid config
- ✓ Subscribes to COMMAND_LONG messages on init
- ✓ Heartbeat timer fires every 1000ms
- ✓ Handles incoming COMMAND_LONG messages
- ✓ Sends messages via XMAVLink.Router
- ✓ Ignores commands for other components

**`test/integration/mavlink_flow_test.exs`**
- ✓ Full request/response cycle for each command:
  - Mock incoming COMMAND_LONG frame
  - Verify COMMAND_ACK sent with correct target
  - Verify data message sent (where applicable)
- ✓ Test all 7 supported commands

### End-to-End Tests

**`test/e2e/announcer_system_test.exs`**
- ✓ Start announcer with test config
- ✓ Connect to test router instance
- ✓ Verify heartbeat transmission every 1s
- ✓ Send camera information request
- ✓ Verify ACK + CAMERA_INFORMATION response
- ✓ Graceful shutdown

**Manual Testing Checklist:**
- [ ] Deploy to dev cluster
- [ ] Verify connection to router service
- [ ] Use QGroundControl to request camera info
- [ ] Verify camera appears in GCS
- [ ] Verify RTSP stream URL correct
- [ ] Check resource usage vs Python version
- [ ] Test graceful shutdown

## Migration Strategy

1. **Development:** Build and test Elixir version locally
2. **Parallel Deployment:** Deploy both versions to dev cluster
   - Python: camera_id=100
   - Elixir: camera_id=101
3. **Validation:** Compare MAVLink traffic using Wireshark/mavproxy
4. **Staging:** Deploy Elixir version to staging, monitor for 48h
5. **Production Rollout:** Replace Python deployment
6. **Monitoring:** Watch logs, resource usage, GCS compatibility
7. **Rollback Plan:** Keep Python deployment yaml committed
8. **Cleanup:** Remove Python version after 2 weeks

## Key Differences from Python Implementation

**Removed Features:**
- PARAM_EXT_REQUEST_READ / PARAM_EXT_SET handlers (unused, not in current deployment)
- V4L2 camera control integration (was stubbed anyway)
- BeautifulSoup XML parsing for camera definitions (not used)

**Architectural Improvements:**
- Separate router connection (cleaner separation of concerns)
- GenServer for state management and supervision
- Pattern matching for command routing
- Immutable state management
- Better error handling and crash recovery via OTP
- Lower memory footprint (BEAM vs Python)

## Performance Expectations

- **Memory:** ~30-50MB (vs ~200MB Python)
- **CPU:** <0.1 core idle, <0.3 core active (vs 0.5 Python)
- **Latency:** <5ms response time (vs ~10-20ms Python)
- **Startup:** <2s (vs ~5s Python)
