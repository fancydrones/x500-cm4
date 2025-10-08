# System ID Mismatch - Camera Not Discovered by QGC

## Root Cause Found! ✅

**QGC System ID: 255** (Ground Control Station)
**Camera System ID: 1**
**Flight Controller System ID: ?** (need to check)

QGC **only discovers cameras on the same system as the vehicle**, not on its own system (255).

## The Issue

In MAVLink:
- **System ID 255** = Reserved for Ground Control Stations (QGC)
- **System ID 1** = Typical vehicle/autopilot system
- **Component IDs** = Different components within a system (autopilot=1, camera=100, etc.)

QGC discovers cameras by looking for:
1. HEARTBEAT from `type=MAV_TYPE_CAMERA` on **the vehicle's system**
2. Then sends `MAV_CMD_REQUEST_MESSAGE` to that system/component

If the camera is on System 1 but the vehicle (flight controller) is on a different system, QGC won't discover it.

## Diagnostic: Find Flight Controller System ID

Check what system ID the flight controller is using:

```bash
# Look for autopilot heartbeats in QGC MAVLink Inspector
# The autopilot should show type=MAV_TYPE_QUADROTOR (or similar)
# Note its System ID
```

Or check router logs for autopilot messages:

```bash
kubectl logs -n rpiuav <router-pod> --tail=1000 | grep -i "endpoint\|sysid"
```

## Solution Options

### Option 1: Match Flight Controller System ID (Recommended)

If flight controller is on System ID 1:
- Camera is already on System 1 ✅
- Something else is wrong (continue debugging)

If flight controller is on a different System ID (e.g., 2, 3, etc.):
- Update camera to match that system ID

```bash
# If flight controller is on system 2
kubectl set env deployment/announcer-ex -n rpiuav ANNOUNCER_SYSTEM_ID=2
```

### Option 2: Check if Flight Controller is on Serial (System 1)

The router shows:
```
[UartEndpoint FlightControllerSerial]
Device = /dev/serial0
```

This is the autopilot connection. Messages from here should be system ID 1.

**Check in QGC MAVLink Inspector:**
- Look for HEARTBEAT messages with `type=MAV_TYPE_QUADROTOR` (or HELICOPTER, VTOL, etc.)
- What System ID does it show?
- If it shows System 1, the camera is on the correct system

### Option 3: Camera as Separate System (Not Recommended)

Some setups use cameras as independent systems:
- Flight controller: System 1
- Camera 1: System 2
- Camera 2: System 3

But QGC typically doesn't discover cameras this way - they should be components of the vehicle system.

## Understanding the MAVLink Inspector Output

You see in QGC MAVLink Inspector:
- **HEARTBEAT (0)** from System 1, Component 100 ← Camera heartbeat
- **VIDEO_STREAM_STATUS (270)** from System 1, Component 100 ← Camera stream status

This is CORRECT! The camera is announcing itself.

**What should happen next:**
1. QGC sees HEARTBEAT from type=MAV_TYPE_CAMERA on System 1, Component 100 ✅
2. QGC should send `COMMAND_LONG` with command 512 (MAV_CMD_REQUEST_MESSAGE) to System 1, Component 100 ❌ Not happening
3. Camera responds with CAMERA_INFORMATION

## Why QGC Might Not Request Camera Info

### Reason 1: QGC is connected to a different vehicle system
If QGC thinks it's connected to System 2 (for example), it will only discover cameras on System 2.

**Check:** In QGC, what does the vehicle dropdown show? It should show the system ID.

### Reason 2: QGC Camera Discovery Not Enabled
In QGC v5.0.7, camera discovery might require:
- Video Source set to "Disabled" ✅ You have this
- Vehicle must be ARMED or in specific state ← Check this
- Camera capability flags must be set ← Let's verify

### Reason 3: Missing or Incorrect Component ID
QGC expects `MAV_COMP_ID_CAMERA` (100) ✅ You have this

## Verification Steps

### Step 1: Check Flight Controller System ID

In QGC MAVLink Inspector:
1. Filter messages to show only HEARTBEAT (ID 0)
2. Look for heartbeat from autopilot (type will be QUADROTOR, HELICOPTER, etc., NOT camera)
3. Note its System ID and Component ID

**Expected:**
- System ID: Should be 1 (if camera is on 1)
- Component ID: Should be 1 (MAV_COMP_ID_AUTOPILOT1)

### Step 2: Verify Camera Capability Flags

Check the camera's CAMERA_INFORMATION flags are correct.

Current setting in message_builder.ex:
```elixir
flags: MapSet.new([:camera_cap_flags_has_video_stream])
```

This might need to be a bitmap integer, not a MapSet. Let me check the xmavlink definition...

### Step 3: Test Direct Command

If you have pymavlink or can send MAVLink commands, manually request camera info:

```python
from pymavlink import mavutil

# Connect to router
mav = mavutil.mavlink_connection('udp:10.10.10.2:14560')

# Manually request CAMERA_INFORMATION from System 1, Component 100
mav.mav.command_long_send(
    1,      # target_system (camera system)
    100,    # target_component (camera component)
    512,    # MAV_CMD_REQUEST_MESSAGE
    0,      # confirmation
    259,    # param1 (CAMERA_INFORMATION message ID)
    0, 0, 0, 0, 0, 0
)

# Wait for response
msg = mav.recv_match(type='CAMERA_INFORMATION', blocking=True, timeout=5)
print(msg)
```

If this works, the camera is functioning - QGC just isn't sending the command.

## Most Likely Issue

Based on your symptoms, the most likely issue is:

**QGC is connected to a vehicle on a different system ID than 1.**

### To Fix:

1. **Find the actual vehicle system ID** in QGC (check vehicle dropdown or MAVLink Inspector for autopilot heartbeat)

2. **Update camera to match:**
   ```bash
   kubectl set env deployment/announcer-ex -n rpiuav ANNOUNCER_SYSTEM_ID=<vehicle-system-id>
   ```

3. **Restart and test:**
   ```bash
   kubectl rollout restart deployment/announcer-ex -n rpiuav
   ```

## Alternative: Force QGC to See Camera

If the system IDs are correct but QGC still doesn't discover:

### Try periodic CAMERA_INFORMATION broadcast

Some QGC versions require cameras to periodically announce themselves, not just respond to requests.

We can re-enable periodic camera info broadcast (we removed this earlier):

```bash
# Edit the deployment to disable stream status and enable camera info broadcast
kubectl set env deployment/announcer-ex -n rpiuav ENABLE_STREAM_STATUS=false
```

And update the code to broadcast CAMERA_INFORMATION every 5 seconds instead.

## Next Step

**Please check in QGC MAVLink Inspector:**
1. Find HEARTBEAT messages with type = autopilot/quadrotor (not camera)
2. What System ID is shown for those messages?
3. Report back - if it's not 1, we'll change the camera to match!
