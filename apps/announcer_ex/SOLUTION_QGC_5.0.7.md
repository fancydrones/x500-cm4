# Solution: QGC v5.0.7 Camera Discovery

## Problem Analysis

Configuration confirmed correct:
- ✅ System ID: 1 (same as autopilot)
- ✅ Component ID: 100 (MAV_COMP_ID_CAMERA)
- ✅ Heartbeat type: MAV_TYPE_CAMERA
- ✅ Router filter: Fixed to allow camera messages
- ✅ QGC sees heartbeat and video stream status in MAVLink Inspector

**But:** QGC v5.0.7 is NOT sending `MAV_CMD_REQUEST_MESSAGE` to discover the camera.

## Root Cause

QGC v5.0.7 appears to expect cameras to **proactively announce themselves** by periodically broadcasting:
- `CAMERA_INFORMATION` (message 259)
- `VIDEO_STREAM_INFORMATION` (message 269)

Instead of only responding to requests. This is a legacy/compatibility mode that some QGC versions use.

## Solution Implemented

Added **periodic camera information broadcast** (defaulting to enabled):

### Changes Made

1. **camera_manager.ex**: Added periodic broadcast every 5 seconds
   - Broadcasts CAMERA_INFORMATION
   - Broadcasts VIDEO_STREAM_INFORMATION
   - Configurable via `ENABLE_CAMERA_INFO_BROADCAST` env var

2. **config.ex**: Added configuration function
   - Defaults to `true` (enabled)
   - Can be disabled by setting `ENABLE_CAMERA_INFO_BROADCAST=false`

3. **announcer-ex-deployment.yaml**: Added env var
   ```yaml
   - name: ENABLE_CAMERA_INFO_BROADCAST
     value: "true"
   ```

## How It Works

**Before (request/response only):**
1. Camera sends HEARTBEAT
2. QGC sees heartbeat
3. QGC should send MAV_CMD_REQUEST_MESSAGE → **Didn't happen**
4. Camera would respond with info → **Never got request**

**After (proactive broadcast):**
1. Camera sends HEARTBEAT every 1s
2. Camera broadcasts CAMERA_INFORMATION every 5s
3. Camera broadcasts VIDEO_STREAM_INFORMATION every 5s
4. Camera broadcasts VIDEO_STREAM_STATUS every 2s (if enabled)
5. **QGC discovers camera from broadcasts**

## Deployment

1. **Build and push new image:**
   ```bash
   cd /Users/royveshovda/src/fancydrones/x500-cm4
   make announcer-ex-build
   make announcer-ex-push
   ```

2. **Update deployment with new image tag**

3. **Deploy:**
   ```bash
   kubectl apply -f deployments/apps/announcer-ex-deployment.yaml
   ```

## Verification

After deployment, check logs:
```bash
kubectl logs -n rpiuav <announcer-pod> -f
```

You should see every 5 seconds:
```
[info] Broadcast CAMERA_INFORMATION and VIDEO_STREAM_INFORMATION
```

In QGC MAVLink Inspector, you should now see:
- HEARTBEAT (0) - every 1s
- CAMERA_INFORMATION (259) - every 5s ← **NEW**
- VIDEO_STREAM_INFORMATION (269) - every 5s ← **NEW**
- VIDEO_STREAM_STATUS (270) - every 2s

And the camera should appear in QGC's camera list!

## Configuration Options

### Enable/Disable Camera Info Broadcast
```yaml
env:
  - name: ENABLE_CAMERA_INFO_BROADCAST
    value: "true"  # or "false" to disable
```

### Enable/Disable Stream Status Broadcast
```yaml
env:
  - name: ENABLE_STREAM_STATUS
    value: "true"  # or "false" to disable
```

## Why This Works

Different QGC versions have different camera discovery mechanisms:

**Modern QGC (4.2+):**
- Discovers cameras via request/response
- Sends MAV_CMD_REQUEST_MESSAGE on seeing camera heartbeat
- More efficient (lower bandwidth)

**Older/Some QGC versions (including 5.0.7 apparently):**
- Expect cameras to proactively broadcast info
- Don't send discovery requests
- Higher bandwidth but more compatible

By enabling periodic broadcasts, we support both discovery methods:
1. Broadcasts work for QGC versions that expect them
2. Request/response still works (we still handle MAV_CMD_REQUEST_MESSAGE)

## Bandwidth Impact

Periodic broadcasts add approximately:
- CAMERA_INFORMATION: ~200 bytes every 5s = 40 bytes/s
- VIDEO_STREAM_INFORMATION: ~200 bytes every 5s = 40 bytes/s
- VIDEO_STREAM_STATUS: ~50 bytes every 2s = 25 bytes/s

**Total: ~105 bytes/second = <1 kbps** - negligible on most MAVLink links.

## Future Optimization

If you confirm this fixes the issue with QGC 5.0.7, we could:

1. **Add auto-detection:** Only broadcast if no requests received within X seconds
2. **Reduce frequency:** Broadcast every 10s instead of 5s once discovered
3. **Stop after discovery:** Stop broadcasting once we receive a request from QGC

For now, keeping it simple with always-on broadcasting (when enabled).

## Troubleshooting

If camera still doesn't appear:

1. **Check logs for broadcasts:**
   ```bash
   kubectl logs -n rpiuav <pod> | grep "Broadcast CAMERA"
   ```

2. **Check MAVLink Inspector in QGC:**
   - Should see CAMERA_INFORMATION (259) appearing every 5s
   - Should see VIDEO_STREAM_INFORMATION (269) appearing every 5s

3. **Verify router isn't blocking:**
   ```bash
   kubectl get configmap rpi4-config -n rpiuav -o yaml | grep AllowMsgIdOut
   ```
   Should include: `0,4,75,76,259,269,270,322,323`

4. **Check camera URL is correct:**
   ```bash
   kubectl logs -n rpiuav <pod> | head -20
   ```
   Look for "Camera initialized" line - verify stream_url is correct

If all else fails, try manual RTSP configuration in QGC as a workaround while we debug further.
