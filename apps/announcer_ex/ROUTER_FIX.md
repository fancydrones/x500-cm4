# ROUTER CONFIGURATION FIX - CRITICAL ISSUE FOUND!

## Problem Identified ✅

The **mavlink-router is filtering out camera messages**!

In the router configuration (`rpi4-config` ConfigMap), the `video0` endpoint has:

```ini
[UdpEndpoint video0]
Mode = Server
Address = 0.0.0.0
Port = 14560
AllowMsgIdOut = 0,4,76,322,323
```

This `AllowMsgIdOut` filter **only allows** these message IDs to be sent OUT from this endpoint:
- **0** = HEARTBEAT ✅ (allowed - this is why QGC sees the camera exists)
- **4** = PING ✅
- **76** = COMMAND_LONG ✅ (allowed - this is why commands FROM QGC can reach the camera)
- **322** = ?
- **323** = ?

But it **BLOCKS** the camera's responses:
- **259** = CAMERA_INFORMATION ❌ BLOCKED!
- **269** = VIDEO_STREAM_INFORMATION ❌ BLOCKED!
- **270** = VIDEO_STREAM_STATUS ❌ BLOCKED!
- **75** = COMMAND_ACK ❌ BLOCKED!

So the flow is:
1. Camera sends HEARTBEAT (msg 0) → **Allowed through** → QGC sees camera exists
2. QGC sends COMMAND_LONG (msg 76) requesting CAMERA_INFORMATION → **Allowed through** → Camera receives it
3. Camera sends COMMAND_ACK (msg 75) → **BLOCKED!** → QGC never gets ACK
4. Camera sends CAMERA_INFORMATION (msg 259) → **BLOCKED!** → QGC never gets info
5. QGC gives up, camera never appears

## Solution

You need to add the camera message IDs to the `AllowMsgIdOut` list.

### Option 1: Allow All Camera Messages (Recommended)

Update the router config to allow all camera-related messages:

```ini
[UdpEndpoint video0]
Mode = Server
Address = 0.0.0.0
Port = 14560
AllowMsgIdOut = 0,4,75,76,259,269,270,322,323
```

Added message IDs:
- **75** = COMMAND_ACK (acknowledgments)
- **259** = CAMERA_INFORMATION
- **269** = VIDEO_STREAM_INFORMATION
- **270** = VIDEO_STREAM_STATUS

### Option 2: Remove the Filter (Easiest)

If you want to allow all messages through:

```ini
[UdpEndpoint video0]
Mode = Server
Address = 0.0.0.0
Port = 14560
# AllowMsgIdOut removed - allows all messages
```

## How to Apply the Fix

### Method 1: Edit ConfigMap Directly

```bash
kubectl edit configmap rpi4-config -n rpiuav
```

Find the `ROUTER_CONFIG` section and update the `[UdpEndpoint video0]` section with one of the options above.

### Method 2: Apply from File

1. Get the current configmap:
```bash
kubectl get configmap rpi4-config -n rpiuav -o yaml > /tmp/router-config.yaml
```

2. Edit `/tmp/router-config.yaml` and update the `AllowMsgIdOut` line

3. Apply the changes:
```bash
kubectl apply -f /tmp/router-config.yaml
```

### Method 3: Patch the ConfigMap

```bash
# This adds the camera message IDs to the filter
kubectl patch configmap rpi4-config -n rpiuav --type merge -p '{"data":{"ROUTER_CONFIG":"[General]\nDebugLogLevel = info\nSnifferSysid=254\nReportStats=false\nMavlinkDialect=auto\n\n[UartEndpoint FlightControllerSerial]\nDevice = /dev/serial0\nBaud = 921600\n\n[UdpEndpoint video0]\nMode = Server\nAddress = 0.0.0.0\nPort = 14560\nAllowMsgIdOut = 0,4,75,76,259,269,270,322,323\n\n[UdpEndpoint Cmpsrv]\nMode = Server\nAddress = 0.0.0.0\nPort = 14561\nAllowMsgIdOut = 0,4,75,76,259,269,270,322,323\n\n[UdpEndpoint GCS3]\nMode = Normal\nAddress = 10.10.10.98\nPort = 14550\n\n[UdpEndpoint GCS4]\nMode = Normal\nAddress = 10.10.10.126\nPort = 14550\n\n[UdpEndpoint GCS5]\nMode = Normal\nAddress = 10.10.10.102\nPort = 14550\n\n[UdpEndpoint Companion]\nMode = Normal\nAddress = 10.10.10.99\nPort = 14550"}}'
```

## Restart the Router

After updating the ConfigMap, restart the router to apply changes:

```bash
kubectl rollout restart deployment/router -n rpiuav
```

Wait for the router to restart:
```bash
kubectl rollout status deployment/router -n rpiuav
```

## Verify the Fix

1. Check router is running:
```bash
kubectl get pods -n rpiuav | grep router
```

2. Check announcer-ex logs for commands:
```bash
kubectl logs -n rpiuav <announcer-pod> -f | grep "Processing command"
```

You should now see:
```
[info] Processing command 512 from 255/190 for target 1/0 (we are 1/100)
[info] Request for message ID: 259 (param2: 0.0)
[info] Sending CAMERA_INFORMATION to 255/190
[info] Sent CAMERA_INFORMATION
```

3. Check QGroundControl - the camera should now appear in the camera list!

## Why Was This Filter There?

The `AllowMsgIdOut` filter was likely added to:
1. Reduce bandwidth on the video streaming port
2. Prevent certain messages from being sent to video recording/streaming endpoints
3. Isolate video-related traffic

But it was too restrictive and blocked the camera discovery protocol messages.

## Alternative: Use a Different Port for Camera Discovery

If you want to keep the video0 endpoint restricted, you could configure the announcer-ex to use a different router endpoint (like `Cmpsrv` on port 14561) which might have different filters.

Update the announcer-ex deployment:
```yaml
- name: SYSTEM_PORT
  value: "14561"  # Use Cmpsrv endpoint instead
```

But you'll need to make sure that endpoint also allows the camera messages through!
