# PRD: Gimbal Protocol v2 Implementation for Pan/Tilt Control

## Overview
Implement MAVLink Gimbal Protocol v2 in the `announcer_ex` application to enable pan/tilt control of the camera via QGroundControl.

## Background
The camera system has pan/tilt capabilities that should be controllable through QGroundControl. MAVLink Gimbal Protocol v2 is the modern standard for gimbal/pan-tilt control, replacing the legacy mount control commands.

## Decision: Separate PRD or Combined?
**RECOMMENDATION: SEPARATE PRD** ✅

**Rationale**:
1. **Distinct Concerns**: Camera discovery is about announcing video capabilities; gimbal control is about accepting attitude setpoints
2. **Optional Feature**: Pan/tilt is optional for camera functionality - camera can work without it
3. **Different Testing**: Camera discovery tested via video appearance; gimbal tested via control inputs
4. **Deployment Flexibility**: Some cameras may not have pan/tilt, so this should be optional/configurable
5. **Complexity**: Gimbal protocol adds significant complexity (manager, device, attitude status, control loop)

## Goals
1. Enable pan/tilt control from QGroundControl
2. Implement Gimbal Protocol v2 (not legacy mount commands)
3. Support Euler angle and quaternion attitude control
4. Broadcast current gimbal attitude
5. Support yaw lock/follow modes (if hardware supports)

## Current Implementation Status
- ❌ No gimbal protocol implementation
- ❌ No gimbal manager
- ❌ No attitude control handlers
- ❌ No attitude status broadcasting

## Architecture Decision

### Option A: Camera Component as Gimbal Manager (RECOMMENDED)
The camera component itself acts as the gimbal manager.

**Pros**:
- Simple: one component, one configuration
- Natural for integrated camera/gimbal units
- Less MAVLink traffic (same component ID)

**Cons**:
- Camera and gimbal lifecycle coupled

### Option B: Separate Gimbal Component
Create separate component with `MAV_TYPE_GIMBAL`.

**Pros**:
- Clear separation of concerns
- Independent fault isolation
- Easier to disable gimbal without affecting camera

**Cons**:
- More complex: two components, two supervisors
- Additional MAVLink overhead
- More configuration needed

**DECISION**: Use **Option A** (camera as gimbal manager) for simplicity, with configuration flag to enable/disable.

## Technical Requirements

### R1: Gimbal Configuration
**Priority**: HIGH
**Location**: `config.ex`

Add gimbal-related configuration:
```elixir
@doc """
Get whether gimbal is enabled.
Defaults to false.
"""
def gimbal_enabled!() do
  case System.get_env("GIMBAL_ENABLED") do
    "true" -> true
    "1" -> true
    _ -> false
  end
end

@doc """
Get gimbal device ID.
For standalone camera with integrated gimbal, use component ID.
"""
def gimbal_device_id!() do
  # Use camera component ID as gimbal device ID for integrated units
  camera_id!()
end

@doc """
Get gimbal pan range in degrees.
Returns {min, max} tuple.
"""
def gimbal_pan_range!() do
  min = System.get_env("GIMBAL_PAN_MIN") |> parse_float(-180.0)
  max = System.get_env("GIMBAL_PAN_MAX") |> parse_float(180.0)
  {min, max}
end

@doc """
Get gimbal tilt range in degrees.
Returns {min, max} tuple.
"""
def gimbal_tilt_range!() do
  min = System.get_env("GIMBAL_TILT_MIN") |> parse_float(-90.0)
  max = System.get_env("GIMBAL_TILT_MAX") |> parse_float(30.0)
  {min, max}
end

defp parse_float(nil, default), do: default
defp parse_float(str, default) do
  case Float.parse(str) do
    {val, _} -> val
    :error -> default
  end
end
```

### R2: Gimbal Manager Module
**Priority**: HIGH
**Location**: NEW `lib/announcer_ex/gimbal_manager.ex`

Create new module to handle gimbal protocol:
```elixir
defmodule AnnouncerEx.GimbalManager do
  @moduledoc """
  Handles Gimbal Protocol v2 for pan/tilt control.

  This module:
  - Responds to GIMBAL_MANAGER_INFORMATION requests
  - Broadcasts GIMBAL_MANAGER_STATUS periodically
  - Handles GIMBAL_MANAGER_SET_ATTITUDE commands
  - Broadcasts GIMBAL_DEVICE_ATTITUDE_STATUS
  - Communicates with hardware pan/tilt controller
  """

  use GenServer

  alias AnnouncerEx.{Config, MessageBuilder}
  alias XMAVLink.Router

  require Logger

  @gimbal_status_interval 200  # 5 Hz

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def set_attitude(quaternion, angular_velocity_x, angular_velocity_y, angular_velocity_z) do
    GenServer.cast(__MODULE__, {:set_attitude, quaternion, angular_velocity_x, angular_velocity_y, angular_velocity_z})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    Logger.info("Starting GimbalManager")

    state = %{
      system_id: Config.system_id!(),
      gimbal_device_id: Config.gimbal_device_id!(),
      camera_id: Config.camera_id!(),
      pan_range: Config.gimbal_pan_range!(),
      tilt_range: Config.gimbal_tilt_range!(),
      # Current attitude (quaternion [w, x, y, z])
      attitude: [1.0, 0.0, 0.0, 0.0],
      # Current Euler angles (yaw, pitch, roll in radians)
      euler: {0.0, 0.0, 0.0},
      boot_time: System.monotonic_time(:millisecond)
    }

    # Subscribe to gimbal commands
    Router.subscribe(message: Common.Message.GimbalManagerSetAttitude, as_frame: true)

    # Start periodic status broadcast
    schedule_status()

    {:ok, state}
  end

  @impl true
  def handle_cast({:set_attitude, quaternion, angular_velocity_x, angular_velocity_y, angular_velocity_z}, state) do
    # TODO: Send to hardware pan/tilt controller
    # This is where you'd integrate with actual hardware

    euler = quaternion_to_euler(quaternion)

    Logger.debug("Setting gimbal attitude: yaw=#{elem(euler, 0)}, pitch=#{elem(euler, 1)}, roll=#{elem(euler, 2)}")

    new_state = %{state | attitude: quaternion, euler: euler}
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:send_status, state) do
    # Broadcast GIMBAL_MANAGER_STATUS
    status = MessageBuilder.build_gimbal_manager_status(state)
    Router.pack_and_send(status)

    # Broadcast GIMBAL_DEVICE_ATTITUDE_STATUS
    attitude_status = MessageBuilder.build_gimbal_device_attitude_status(state)
    Router.pack_and_send(attitude_status)

    schedule_status()
    {:noreply, state}
  end

  @impl true
  def handle_info(frame = %XMAVLink.Frame{message: msg}, state)
      when is_struct(msg, Common.Message.GimbalManagerSetAttitude) do
    # Check if command is for this gimbal
    if msg.target_system == state.system_id and
       msg.target_component == state.camera_id do

      # Extract attitude command
      quaternion = [msg.q[0], msg.q[1], msg.q[2], msg.q[3]]

      set_attitude(quaternion, msg.angular_velocity_x, msg.angular_velocity_y, msg.angular_velocity_z)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  defp schedule_status do
    Process.send_after(self(), :send_status, @gimbal_status_interval)
  end

  defp quaternion_to_euler([w, x, y, z]) do
    # Convert quaternion to Euler angles (yaw, pitch, roll)
    # Standard aerospace sequence

    # Roll (x-axis rotation)
    sinr_cosp = 2 * (w * x + y * z)
    cosr_cosp = 1 - 2 * (x * x + y * y)
    roll = :math.atan2(sinr_cosp, cosr_cosp)

    # Pitch (y-axis rotation)
    sinp = 2 * (w * y - z * x)
    pitch = if abs(sinp) >= 1 do
      :math.copysign(:math.pi() / 2, sinp)  # Use 90 degrees if out of range
    else
      :math.asin(sinp)
    end

    # Yaw (z-axis rotation)
    siny_cosp = 2 * (w * z + x * y)
    cosy_cosp = 1 - 2 * (y * y + z * z)
    yaw = :math.atan2(siny_cosp, cosy_cosp)

    {yaw, pitch, roll}
  end
end
```

### R3: Update Command Handler
**Priority**: HIGH
**Location**: `command_handler.ex`

Add handler for `GIMBAL_MANAGER_INFORMATION` request:
```elixir
defp handle_request_message(msg_id, command_msg, frame, state) do
  source_system = frame.source_system
  source_component = frame.source_component

  case msg_id do
    # ... existing camera message handlers ...

    280 -> # GIMBAL_MANAGER_INFORMATION
      if Config.gimbal_enabled!() do
        send_ack(command_msg, :mav_result_accepted, source_system, source_component)
        info = MessageBuilder.build_gimbal_manager_information(state)
        Router.pack_and_send(info)
      else
        send_ack(command_msg, :mav_result_unsupported, source_system, source_component)
      end

    _ ->
      send_ack(command_msg, :mav_result_unsupported, source_system, source_component)
  end
end
```

### R4: Update Message Builder
**Priority**: HIGH
**Location**: `message_builder.ex`

Add gimbal message builders:
```elixir
@doc """
Build gimbal manager information message.
"""
def build_gimbal_manager_information(state) do
  {pan_min, pan_max} = Config.gimbal_pan_range!()
  {tilt_min, tilt_max} = Config.gimbal_tilt_range!()

  %Common.Message.GimbalManagerInformation{
    time_boot_ms: boot_timestamp(state.boot_time),
    cap_flags: MapSet.new([
      :gimbal_manager_cap_flags_has_retract,
      :gimbal_manager_cap_flags_has_neutral,
      :gimbal_manager_cap_flags_has_roll_axis,
      :gimbal_manager_cap_flags_has_roll_follow,
      :gimbal_manager_cap_flags_has_roll_lock,
      :gimbal_manager_cap_flags_has_pitch_axis,
      :gimbal_manager_cap_flags_has_pitch_follow,
      :gimbal_manager_cap_flags_has_pitch_lock,
      :gimbal_manager_cap_flags_has_yaw_axis,
      :gimbal_manager_cap_flags_has_yaw_follow,
      :gimbal_manager_cap_flags_has_yaw_lock
    ]),
    gimbal_device_id: Config.gimbal_device_id!(),
    roll_min: 0.0,  # Assuming no roll capability
    roll_max: 0.0,
    pitch_min: degrees_to_radians(tilt_min),
    pitch_max: degrees_to_radians(tilt_max),
    yaw_min: degrees_to_radians(pan_min),
    yaw_max: degrees_to_radians(pan_max)
  }
end

@doc """
Build gimbal manager status message.
"""
def build_gimbal_manager_status(state) do
  %Common.Message.GimbalManagerStatus{
    time_boot_ms: boot_timestamp(state.boot_time),
    flags: MapSet.new([:gimbal_manager_flags_neutral]),
    gimbal_device_id: Config.gimbal_device_id!(),
    primary_control_sysid: 0,
    primary_control_compid: 0,
    secondary_control_sysid: 0,
    secondary_control_compid: 0
  }
end

@doc """
Build gimbal device attitude status message.
"""
def build_gimbal_device_attitude_status(state) do
  {yaw, pitch, roll} = state.euler
  [w, x, y, z] = state.attitude

  %Common.Message.GimbalDeviceAttitudeStatus{
    time_boot_ms: boot_timestamp(state.boot_time),
    flags: MapSet.new([
      :gimbal_device_flags_neutral,
      :gimbal_device_flags_yaw_lock
    ]),
    q: [w, x, y, z],
    angular_velocity_x: 0.0,
    angular_velocity_y: 0.0,
    angular_velocity_z: 0.0,
    failure_flags: MapSet.new()
  }
end

defp degrees_to_radians(degrees) do
  degrees * :math.pi() / 180.0
end
```

### R5: Update Application Supervisor
**Priority**: HIGH
**Location**: `application.ex`

Conditionally start gimbal manager:
```elixir
def start(_type, _args) do
  Application.ensure_all_started(:xmavlink)

  children = [
    AnnouncerEx.CameraManager
  ]

  # Add gimbal manager if enabled
  children = if Config.gimbal_enabled!() do
    children ++ [AnnouncerEx.GimbalManager]
  else
    children
  end

  opts = [strategy: :one_for_one, name: AnnouncerEx.Supervisor]
  Supervisor.start_link(children, opts)
end
```

### R6: Update CAMERA_INFORMATION
**Priority**: MEDIUM
**Location**: `message_builder.ex`

Link camera to gimbal:
```elixir
def build_camera_information(state) do
  gimbal_device_id = if Config.gimbal_enabled!() do
    Config.gimbal_device_id!()
  else
    0  # No gimbal
  end

  %Common.Message.CameraInformation{
    # ... existing fields ...
    gimbal_device_id: gimbal_device_id,
    # ... rest of fields ...
  }
end
```

### R7: Hardware Integration Interface
**Priority**: MEDIUM
**Location**: NEW `lib/announcer_ex/gimbal_hardware.ex`

Create behaviour for hardware integration:
```elixir
defmodule AnnouncerEx.GimbalHardware do
  @moduledoc """
  Behaviour for gimbal hardware control.
  Implement this to integrate with actual pan/tilt hardware.
  """

  @callback set_pan_tilt(pan_degrees :: float(), tilt_degrees :: float()) :: :ok | {:error, term()}
  @callback get_current_position() :: {:ok, {pan :: float(), tilt :: float()}} | {:error, term()}
  @callback home() :: :ok | {:error, term()}
  @callback calibrate() :: :ok | {:error, term()}
end

defmodule AnnouncerEx.GimbalHardware.Mock do
  @moduledoc """
  Mock implementation for testing without hardware.
  """

  @behaviour AnnouncerEx.GimbalHardware

  def set_pan_tilt(pan, tilt) do
    # Simulate hardware delay
    Process.sleep(10)
    :ok
  end

  def get_current_position() do
    {:ok, {0.0, 0.0}}
  end

  def home() do
    :ok
  end

  def calibrate() do
    :ok
  end
end
```

## Testing Requirements

### T1: QGroundControl Integration Test
- Enable gimbal in configuration
- Connect QGC
- Verify gimbal controls appear in UI
- Test pan/tilt commands from QGC
- Verify attitude feedback displays correctly

### T2: Message Flow Verification
Using MAVLink inspector:
1. Camera sends HEARTBEAT with gimbal_device_id in CAMERA_INFORMATION
2. QGC requests GIMBAL_MANAGER_INFORMATION (280)
3. Camera responds with capabilities and ranges
4. Camera broadcasts GIMBAL_MANAGER_STATUS at 5 Hz
5. QGC sends GIMBAL_MANAGER_SET_ATTITUDE
6. Camera broadcasts updated GIMBAL_DEVICE_ATTITUDE_STATUS

### T3: Hardware Integration Test
- Mock hardware: Verify commands processed correctly
- Real hardware: Verify physical movement matches commands
- Test limit enforcement (pan/tilt ranges)
- Test rate limiting if needed

### T4: Disabled Gimbal Test
- Set GIMBAL_ENABLED=false
- Verify gimbal manager not started
- Verify GIMBAL_MANAGER_INFORMATION returns unsupported
- Verify no gimbal status broadcasts

## Configuration

New environment variables:
```bash
# Gimbal configuration
GIMBAL_ENABLED=true              # Enable gimbal protocol (default: false)
GIMBAL_PAN_MIN=-180.0            # Minimum pan in degrees (default: -180)
GIMBAL_PAN_MAX=180.0             # Maximum pan in degrees (default: 180)
GIMBAL_TILT_MIN=-90.0            # Minimum tilt in degrees (default: -90)
GIMBAL_TILT_MAX=30.0             # Maximum tilt in degrees (default: 30)
GIMBAL_HARDWARE=mock             # Hardware implementation (default: mock)
```

## Migration Strategy

### Phase 1: Protocol Implementation (Week 1)
- Implement gimbal manager module
- Add message builders
- Add command handlers
- Test with mock hardware

### Phase 2: Hardware Integration (Week 2)
- Define hardware interface
- Implement hardware adapter
- Test with actual pan/tilt unit
- Tune control parameters

### Phase 3: QGC Integration & Polish (Week 3)
- End-to-end testing with QGC
- Performance optimization
- Documentation
- Deployment configuration

## Success Criteria
1. ✅ Gimbal controls appear in QGC when gimbal enabled
2. ✅ Pan/tilt commands from QGC result in correct hardware movement
3. ✅ Attitude feedback displayed accurately in QGC
4. ✅ Gimbal can be disabled via configuration
5. ✅ No performance regression (<5% CPU increase when enabled)
6. ✅ Proper error handling for hardware failures

## Out of Scope (Future Enhancements)
- Gimbal calibration UI
- Advanced stabilization modes
- Tracking modes (point, rectangle)
- Gimbal limits from hardware discovery
- Multiple gimbal support

## Dependencies
- Gimbal Protocol v2 implementation complete before hardware integration
- Camera discovery PRD (PRD_CAMERA_DISCOVERY.md) should be completed first
- Hardware pan/tilt unit with known control interface

## References
- [Gimbal Protocol v2](https://mavlink.io/en/services/gimbal_v2.html)
- [GIMBAL_MANAGER_INFORMATION (280)](https://mavlink.io/en/messages/common.html#GIMBAL_MANAGER_INFORMATION)
- [GIMBAL_MANAGER_SET_ATTITUDE (282)](https://mavlink.io/en/messages/common.html#GIMBAL_MANAGER_SET_ATTITUDE)
- [GIMBAL_DEVICE_ATTITUDE_STATUS (285)](https://mavlink.io/en/messages/common.html#GIMBAL_DEVICE_ATTITUDE_STATUS)
- Camera info report: `apps/announcer_ex/CAMERA_INFO.md`
- Current implementation: `apps/announcer_ex/`
