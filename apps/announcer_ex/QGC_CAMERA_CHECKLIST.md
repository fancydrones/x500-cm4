# QGroundControl Camera Not Showing - Diagnostic Checklist

## Current Status

✅ Router filter fixed - camera messages are allowed through
✅ Camera is sending heartbeats with `type=MAV_TYPE_CAMERA`
✅ Camera is broadcasting VIDEO_STREAM_STATUS
❌ QGC is NOT sending any camera discovery commands

This means **QGC is not recognizing the camera from the heartbeats**.

## Critical Questions to Answer

### 1. QGroundControl Version
**What version of QGC are you using?**

Different QGC versions have different camera discovery mechanisms:
- **QGC 4.1.x and earlier**: May require manual video stream configuration
- **QGC 4.2.x+**: Should support MAVLink camera protocol v2 auto-discovery
- **QGC Daily builds**: Latest camera discovery features

Check: **Application Settings → General → About**

### 2. QGC Connection Method
**How is QGC connected to the drone?**

- [ ] UDP connection to IP: _______________ Port: _______________
- [ ] TCP connection to IP: _______________ Port: _______________
- [ ] Serial connection
- [ ] Other: _______________

The camera is on **System ID 1, Component ID 100** sending to router port **14560**.

### 3. MAVLink Protocol Version
**In QGC Settings:**
- Go to **Application Settings → General → Miscellaneous**
- Check **MAVLink** section
- What is selected?
  - [ ] MAVLink 1
  - [ ] MAVLink 2
  - [ ] Forward MAVLink (enabled/disabled)

**The camera uses MAVLink 2** - ensure this is enabled.

### 4. Video Settings in QGC
**In QGC Settings → General → Video:**
- What is **Video Source** set to?
  - [ ] Disabled (this allows auto-discovery in some QGC versions)
  - [ ] RTSP Video Stream
  - [ ] UDP Video Stream
  - [ ] TCP-MPEG2 Video Stream
  - [ ] Mock Video Stream

**Try setting it to "Disabled"** - some QGC versions auto-discover when disabled.

### 5. System ID Matching
The camera announces on **System ID 1**.

**In QGC, what system ID is the connected vehicle?**
- Check the vehicle dropdown in QGC toolbar
- If the vehicle is on a different system ID, QGC might not discover camera components on system 1

### 6. Camera List in QGC
**Does QGC have a camera selector/list?**
- Some QGC versions show camera list in **Vehicle → Camera** menu
- Or in the video widget settings (gear icon on video display)
- Check if camera "Front" appears anywhere

## Diagnostic Commands

### Test 1: Verify Messages Reach Router
```bash
# Watch router traffic for camera messages
kubectl exec -n rpiuav <router-pod> -- tcpdump -i any -n port 14560 -c 20
```

You should see periodic traffic from the camera (heartbeats every 1s).

### Test 2: Check if QGC is Connected
```bash
# Check router endpoints
kubectl logs -n rpiuav <router-pod> | grep "Opened\|Accepted"
```

Look for GCS connections. If QGC is connected, you should see its endpoint.

### Test 3: Manually Trigger Camera Discovery
If QGC has a MAVLink console or inspector:
1. Open **Analyze View → MAVLink Inspector**
2. Look for messages from System 1, Component 100
3. You should see HEARTBEAT (0) and VIDEO_STREAM_STATUS (270)

### Test 4: Check Camera Messages are Sent
```bash
# Enable debug in announcer to see message details
kubectl set env deployment/announcer-ex -n rpiuav LOG_LEVEL=debug
kubectl logs -n rpiuav <announcer-pod> -f
```

Watch for heartbeat and stream status messages.

## Possible Issues and Solutions

### Issue 1: QGC Doesn't Support Auto-Discovery
**Symptoms:** QGC never sends camera discovery commands
**Solution:** Manually configure video in QGC:
1. Go to **Settings → General → Video**
2. Set **Video Source** to **RTSP Video Stream**
3. Set **RTSP URL** to: `rtsp://10.10.10.2:8554/cam`
4. Video should appear (but camera won't be "discovered" via MAVLink)

### Issue 2: QGC on Different System ID
**Symptoms:** QGC connected but not seeing camera
**Solution:**
- Check vehicle system ID in QGC
- Update camera to match: change `ANNOUNCER_SYSTEM_ID` in deployment
- Or configure QGC to connect to system 1

### Issue 3: Component ID Not Recognized
**Symptoms:** QGC sees heartbeat but doesn't recognize as camera
**Possible causes:**
- QGC version doesn't support component-level camera discovery
- QGC expects camera on specific component ID (like MAV_COMP_ID_CAMERA = 100)

**Current config:** Component ID 100 is correct for MAV_COMP_ID_CAMERA

### Issue 4: QGC Expects Camera on Different System
Some QGC setups expect cameras to be on:
- **Same system as autopilot** (System ID 1) ✅ This is configured
- **Different component than autopilot** (Component 100) ✅ This is configured

But some expect:
- **Separate system ID** for cameras (System ID 2, etc.)

**Test:** Try changing `ANNOUNCER_SYSTEM_ID` to `2`:
```bash
kubectl set env deployment/announcer-ex -n rpiuav ANNOUNCER_SYSTEM_ID=2
```

## Alternative Approaches

### Approach 1: Use CAMERA_INFORMATION Broadcast (Legacy)
Some older QGC versions expected cameras to periodically broadcast CAMERA_INFORMATION.

We removed this, but you can re-enable it temporarily:
```elixir
# In camera_manager.ex, re-add periodic camera info broadcast
@camera_info_interval 5000

# In init, add:
schedule_camera_info()

# Add handler:
def handle_info(:send_camera_info, state) do
  camera_info = MessageBuilder.build_camera_information(state)
  Router.pack_and_send(camera_info)
  schedule_camera_info()
  {:noreply, state}
end
```

### Approach 2: Manual Video Configuration
Simplest solution if auto-discovery doesn't work:
1. In QGC: **Settings → Video → RTSP Video Stream**
2. URL: `rtsp://10.10.10.2:8554/cam`
3. Accept that MAVLink discovery isn't working in your QGC version

### Approach 3: Update QGC
Try the latest QGC daily build which has better camera support:
- https://docs.qgroundcontrol.com/master/en/getting_started/download_and_install.html#daily-builds

## Next Steps

Please provide:
1. **QGC version number**
2. **Video source setting in QGC**
3. **System ID of connected vehicle in QGC**
4. **Screenshot of QGC MAVLink Inspector** (if available) showing messages from System 1, Component 100

Then we can determine the exact cause and solution.

## Quick Test: Manual Video

While debugging, test if the video stream itself works:
1. In QGC: **Settings → General → Video**
2. Set **Source** to **RTSP Video Stream**
3. Set **RTSP URL** to: `rtsp://10.10.10.2:8554/cam`

Does video appear? If yes, the stream works but MAVLink discovery is the issue.
