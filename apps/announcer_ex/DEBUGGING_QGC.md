# QGroundControl Camera Discovery Debugging Guide

## 🚨 CRITICAL ISSUE FOUND - ROUTER FILTER BLOCKING MESSAGES

**The mavlink-router is blocking camera response messages!**

See [ROUTER_FIX.md](ROUTER_FIX.md) for the complete solution.

**Quick Fix:**
```bash
kubectl edit configmap rpi4-config -n rpiuav
```

In the `ROUTER_CONFIG` section, find `[UdpEndpoint video0]` and change:
```ini
AllowMsgIdOut = 0,4,76,322,323
```

To:
```ini
AllowMsgIdOut = 0,4,75,76,259,269,270,322,323
```

Also update `[UdpEndpoint Cmpsrv]` the same way.

Then restart the router:
```bash
kubectl rollout restart deployment/router -n rpiuav
```

**This should fix the issue!** The code changes below are also important improvements.

---

## Changes Made to announcer_ex

### 1. Fixed Broadcast Command Handling
- Camera now responds to broadcast requests (`target_component=0` or `target_system=0`)
- This is critical for QGC's initial camera discovery

### 2. Enhanced Logging
- All commands received are now logged with INFO level
- Heartbeat details are logged
- All incoming MAVLink messages are logged

## Deployment Instructions

1. **Build and push new image:**
   ```bash
   # From x500-cm4 root
   make announcer-ex-build
   make announcer-ex-push
   ```

2. **Update deployment image tag in:**
   `deployments/apps/announcer-ex-deployment.yaml`

3. **Redeploy:**
   ```bash
   kubectl apply -f deployments/apps/announcer-ex-deployment.yaml
   kubectl rollout restart deployment/announcer-ex -n rpiuav
   ```

## Diagnostic Steps

### Step 1: Verify Camera is Running
```bash
kubectl get pods -n rpiuav | grep announcer-ex
kubectl logs -n rpiuav <pod-name> --tail=50
```

You should see:
```
[info] Camera initialized: Front (ID: 100) on system 1
[info] Subscribed to CommandLong messages. Waiting for commands from QGC...
[debug] Sent heartbeat: type=:mav_type_camera, autopilot=:mav_autopilot_invalid, system_status=:mav_state_standby
```

### Step 2: Check if QGC is Sending Commands
```bash
kubectl logs -n rpiuav <pod-name> -f | grep -i "processing command"
```

**If you see commands:**
- Good! QGC is communicating with the camera
- Check what message IDs are being requested

**If you see NO commands:**
- QGC is not discovering the camera from heartbeats
- Continue to Step 3

### Step 3: Check QGC MAVLink Settings

1. Open QGroundControl
2. Go to **Settings > General > MAVLink**
3. Ensure:
   - **MAVLink 2** is enabled (not MAVLink 1)
   - **Forward MAVLink** is enabled if using a router
   - **Only accept MAVLink 2** can be checked

### Step 4: Check Video Source Settings

1. In QGC, go to **Settings > General > Video**
2. Set **Video Source** to: **MAVLink Auto Discovery Streams**
3. **NOT** RTSP or UDP manual entry

This is critical - QGC must be set to auto-discover streams via MAVLink!

### Step 5: Check System ID Matching

The camera announces on:
- **System ID:** From `ANNOUNCER_SYSTEM_ID` env var (check deployment yaml)
- **Component ID:** 100

QGC must be connected to a MAVLink system with the same System ID.

To check:
```bash
kubectl logs -n rpiuav <pod-name> | grep "Camera initialized"
```

### Step 6: Check Router Service

The camera sends messages to:
```
router-service.rpiuav.svc.cluster.local:14560
```

Verify the router is:
1. Running and accessible
2. Forwarding messages to QGC
3. Forwarding messages FROM QGC back to the camera

```bash
kubectl get svc -n rpiuav router-service
kubectl logs -n rpiuav <router-pod-name> | grep -i camera
```

### Step 7: Use MAVLink Inspector

If possible, use a MAVLink inspector tool to see raw traffic:
- [QGC MAVLink Inspector](https://docs.qgroundcontrol.com/master/en/analyze_view/mavlink_inspector.html)
- [pymavlink mavlogdump](https://github.com/ArduPilot/pymavlink)

Check for:
1. HEARTBEAT messages with `type=30` (MAV_TYPE_CAMERA)
2. COMMAND_LONG messages being sent from QGC
3. CAMERA_INFORMATION responses
4. VIDEO_STREAM_INFORMATION responses

## Expected Message Flow

When working correctly, you should see:

```
[debug] Sent heartbeat: type=:mav_type_camera, ...
[info] Processing command 512 from 255/190 for target 1/0 (we are 1/100)
[info] Request for message ID: 259 (param2: 0.0)
[info] Sending CAMERA_INFORMATION to 255/190
[info] Sent CAMERA_INFORMATION
[info] Processing command 512 from 255/190 for target 1/100 (we are 1/100)
[info] Request for message ID: 269 (param2: 0.0)
[info] Sending VIDEO_STREAM_INFORMATION (stream_id: 0) to 255/190
[info] Sent 1 VIDEO_STREAM_INFORMATION message(s)
```

Then the camera should appear in QGC's camera list!

## Common Issues

### Issue 1: QGC Not Sending Commands
**Symptoms:** Only see heartbeats, no "Processing command" logs
**Causes:**
- Router not forwarding messages
- QGC not set to MAVLink Auto Discovery
- System ID mismatch
- QGC not connected to the MAVLink network

**Solution:** Check router logs, verify QGC settings, check system IDs

### Issue 2: Commands Being Ignored
**Symptoms:** See "Ignoring command" logs
**Causes:**
- Target system/component mismatch
- Old code before broadcast fix

**Solution:** This should be fixed with the broadcast handling changes

### Issue 3: Camera Info Sent But No Video
**Symptoms:** Camera appears but no video stream
**Causes:**
- CAMERA_URL is incorrect
- Stream URL not accessible from QGC
- VIDEO_STREAM_INFORMATION has wrong URI

**Solution:** Check the actual stream URL:
```bash
kubectl get configmap -n rpiuav rpi4-config -o yaml | grep ANNOUNCER_CAMERA_URL
```

## Testing Locally

You can test the MAVLink protocol flow locally:

1. Run the application:
   ```bash
   cd apps/announcer_ex
   mix deps.get
   CAMERA_URL="rtsp://example.com/stream" \
   CAMERA_ID=100 \
   CAMERA_NAME="Test Camera" \
   SYSTEM_ID=1 \
   iex -S mix
   ```

2. Use pymavlink to send commands:
   ```python
   from pymavlink import mavutil

   # Connect to the camera
   mav = mavutil.mavlink_connection('udpout:localhost:14550')

   # Request camera information
   mav.mav.command_long_send(
       1,    # target_system
       100,  # target_component (camera ID)
       512,  # MAV_CMD_REQUEST_MESSAGE
       0,    # confirmation
       259,  # param1 (CAMERA_INFORMATION message ID)
       0, 0, 0, 0, 0, 0
   )
   ```

## Next Steps

After deploying with enhanced logging:

1. **Check logs for heartbeats** - Are they being sent?
2. **Check logs for commands** - Is QGC requesting info?
3. **Check QGC settings** - Is auto-discovery enabled?
4. **Check router logs** - Are messages being forwarded?

Report back with the log output and we can diagnose further!
