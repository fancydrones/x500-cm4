# PRD: Camera Discovery & Stream Announcement via MAVLink 2.0

## Overview
Enhance the `announcer_ex` application to fully comply with the MAVLink 2.0 Camera Protocol v2 specification, ensuring proper camera discovery and video stream announcement in QGroundControl (QGC).

## Background
The current `announcer_ex` implementation handles camera announcements using legacy command IDs and doesn't fully follow the MAVLink 2.0 request/response patterns. According to the Camera Protocol v2 specification, QGC uses `MAV_CMD_REQUEST_MESSAGE` to discover camera capabilities, not the legacy numbered commands.

## Goals
1. Implement proper MAVLink 2.0 Camera Protocol v2 message flow
2. Ensure camera automatically appears in QGroundControl
3. Display video stream in QGC without manual configuration
4. Support multiple video streams (if needed in the future)

## Current Implementation Analysis

### What Works
- ✅ Heartbeat broadcasting (`MAV_TYPE_CAMERA`)
- ✅ Camera information message structure
- ✅ Video stream information message structure
- ✅ Command acknowledgment
- ✅ State management via GenServer

### What Needs Fixing

#### 1. Command Protocol (HIGH PRIORITY)
**Current**: Uses legacy command IDs (521, 2504, etc.)
```elixir
@mav_cmd_request_camera_information 521
@mav_cmd_request_video_stream_information 2504
```

**Required**: Use `MAV_CMD_REQUEST_MESSAGE (512)` with `param1` specifying message ID
- `param1=259` → `CAMERA_INFORMATION`
- `param1=269` → `VIDEO_STREAM_INFORMATION`
- `param1=270` → `VIDEO_STREAM_STATUS`

#### 2. Video Stream Information Flags (HIGH PRIORITY)
**Current**: Uses incorrect flag type
```elixir
flags: :video_stream_status_flags_running  # WRONG enum type
```

**Required**: `VIDEO_STREAM_INFORMATION` doesn't have a `flags` field in the spec. Remove it or use correct field if xmavlink defines it differently.

#### 3. Heartbeat Autopilot Field (LOW PRIORITY)
**Current**:
```elixir
autopilot: :mav_autopilot_generic
```

**Recommended**: For non-autopilot components
```elixir
autopilot: :mav_autopilot_invalid
```

#### 4. Stream URI Encoding (MEDIUM PRIORITY)
**Current**: Direct string padding
```elixir
uri: pad_bytes(state.stream_url, 160)
```

**Required**: Ensure URI format matches stream type
- RTSP: `rtsp://<ip>:<port>/path`
- UDP: Port number or `udp://0.0.0.0:<port>`

#### 5. Camera Capabilities Missing (MEDIUM PRIORITY)
**Current**: Only declares `HAS_VIDEO_STREAM`
```elixir
flags: MapSet.new([:camera_cap_flags_has_video_stream])
```

**Consider Adding**:
- `CAMERA_CAP_FLAGS_CAPTURE_VIDEO` if recording supported
- `CAMERA_CAP_FLAGS_CAPTURE_IMAGE` if snapshots supported
- Other relevant flags based on actual capabilities

## Technical Requirements

### R1: Handle MAV_CMD_REQUEST_MESSAGE Properly
**Priority**: HIGH
**Location**: `command_handler.ex`

Add handler for `MAV_CMD_REQUEST_MESSAGE (512)`:
```elixir
@mav_cmd_request_message 512

def handle_command(command_msg, frame, state) do
  case command_msg.command do
    @mav_cmd_request_message ->
      requested_msg_id = trunc(command_msg.param1)
      handle_request_message(requested_msg_id, command_msg, frame, state)

    # Keep other handlers for backward compatibility if needed
    _ -> ...
  end
end

defp handle_request_message(msg_id, command_msg, frame, state) do
  source_system = frame.source_system
  source_component = frame.source_component

  case msg_id do
    259 -> # CAMERA_INFORMATION
      send_ack(command_msg, :mav_result_accepted, source_system, source_component)
      camera_info = MessageBuilder.build_camera_information(state)
      Router.pack_and_send(camera_info)

    269 -> # VIDEO_STREAM_INFORMATION
      send_ack(command_msg, :mav_result_accepted, source_system, source_component)
      # Send one message per stream
      Enum.each(MessageBuilder.build_all_stream_info(state), &Router.pack_and_send/1)

    270 -> # VIDEO_STREAM_STATUS
      send_ack(command_msg, :mav_result_accepted, source_system, source_component)
      status = MessageBuilder.build_video_stream_status(state)
      Router.pack_and_send(status)

    _ ->
      send_ack(command_msg, :mav_result_unsupported, source_system, source_component)
  end
end
```

### R2: Fix Message Structures
**Priority**: HIGH
**Location**: `message_builder.ex`

1. **Remove incorrect flags from VIDEO_STREAM_INFORMATION**
2. **Update CAMERA_INFORMATION**:
   - Change `autopilot` to `:mav_autopilot_invalid` in heartbeat
   - Set appropriate capability flags
   - Consider providing `cam_definition_uri` (optional)

3. **Ensure proper encoding values**:
   ```elixir
   encoding: :video_stream_encoding_h264  # or appropriate codec
   ```

### R3: Support Multiple Streams
**Priority**: MEDIUM
**Location**: `message_builder.ex`, `camera_manager.ex`

Allow configuration of multiple streams:
```elixir
# In build_all_stream_info/1
def build_all_stream_info(state) do
  streams = state.streams || [default_stream(state)]
  count = length(streams)

  Enum.with_index(streams, 1)
  |> Enum.map(fn {stream, idx} ->
    %Common.Message.VideoStreamInformation{
      stream_id: idx,
      count: count,
      type: stream.type,
      name: pad_bytes(stream.name, 32),
      uri: pad_bytes(stream.uri, 160),
      encoding: stream.encoding,
      framerate: stream.framerate,
      resolution_h: stream.resolution_h,
      resolution_v: stream.resolution_v,
      bitrate: stream.bitrate,
      rotation: stream.rotation,
      hfov: stream.hfov
    }
  end)
end
```

### R4: Periodic Status Broadcasting
**Priority**: MEDIUM
**Location**: `camera_manager.ex`

Currently sends camera info every 5 seconds. Verify this aligns with spec:
- Heartbeat: 1 Hz (✅ implemented)
- Camera info: On request, optionally once at startup (⚠️ currently every 5s)
- Stream status: On request, then at low rate while streaming (❌ not implemented)

**Recommendation**:
- Remove periodic camera info broadcast (line 52, 69-82)
- Add periodic stream status broadcast (only when streaming):
  ```elixir
  @stream_status_interval 2000  # 0.5 Hz

  defp schedule_stream_status do
    Process.send_after(self(), :send_stream_status, @stream_status_interval)
  end
  ```

### R5: Environment Configuration Updates
**Priority**: LOW
**Location**: `config.ex`

Consider adding:
```elixir
def video_encoding! do
  System.get_env("VIDEO_ENCODING") || "h264"
end

def camera_capabilities! do
  # Parse comma-separated capability flags
  System.get_env("CAMERA_CAPABILITIES") || "has_video_stream"
end
```

## Testing Requirements

### T1: QGroundControl Integration Test
- Deploy updated announcer_ex
- Connect QGC
- Verify camera appears in camera list automatically
- Verify video stream appears without manual configuration
- Verify stream controls work

### T2: MAVLink Inspector Verification
- Use MAVLink inspector/analyzer tool
- Verify proper message sequence:
  1. HEARTBEAT broadcasts
  2. QGC sends MAV_CMD_REQUEST_MESSAGE(259)
  3. Camera responds with CAMERA_INFORMATION
  4. QGC sends MAV_CMD_REQUEST_MESSAGE(269)
  5. Camera responds with VIDEO_STREAM_INFORMATION
  6. Video appears in QGC

### T3: Multiple Camera Scenario
- Deploy multiple announcer_ex instances with different CAMERA_ID
- Verify all cameras appear in QGC
- Verify correct component ID routing

## Migration Strategy

### Phase 1: Fix Critical Issues (Week 1)
- Implement MAV_CMD_REQUEST_MESSAGE handler
- Fix VIDEO_STREAM_INFORMATION flags
- Remove periodic camera info broadcast
- Test with QGC

### Phase 2: Enhanced Capabilities (Week 2)
- Add periodic stream status
- Support multiple streams configuration
- Add capability flags configuration
- Test all scenarios

### Phase 3: Polish & Documentation (Week 3)
- Update README with new configuration
- Add troubleshooting guide
- Performance testing
- Update deployment manifests if needed

## Success Criteria
1. ✅ Camera appears automatically in QGC camera list within 2 seconds of connection
2. ✅ Video stream displays in QGC without manual URI entry
3. ✅ Multiple cameras can coexist on same MAVLink network
4. ✅ All MAVLink protocol compliance verified via inspector
5. ✅ No performance regression (maintain <50MB memory, <0.3 core CPU)

## References
- [MAVLink Camera Protocol v2](https://mavlink.io/en/services/camera_v2.html)
- [CAMERA_INFORMATION (259)](https://mavlink.io/en/messages/common.html#CAMERA_INFORMATION)
- [VIDEO_STREAM_INFORMATION (269)](https://mavlink.io/en/messages/common.html#VIDEO_STREAM_INFORMATION)
- [MAV_CMD_REQUEST_MESSAGE](https://mavlink.io/en/services/camera_v2.html#message-intervals-and-requests)
- Current implementation: `apps/announcer_ex/`
- Camera info report: `apps/announcer_ex/CAMERA_INFO.md`
