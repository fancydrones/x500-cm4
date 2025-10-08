# Final Diagnostic - Camera Still Not Showing

## Current Status ✅

- Camera is running and broadcasting every 5s:
  - HEARTBEAT (0)
  - CAMERA_INFORMATION (259)
  - VIDEO_STREAM_INFORMATION (269)
  - VIDEO_STREAM_STATUS (270)

- Router filter is configured correctly
- System ID and Component ID are correct (1/100)

## CRITICAL QUESTIONS

### Question 1: Do Messages Appear in QGC MAVLink Inspector?

Open **QGC → Analyze Tools → MAVLink Inspector** and check:

**Do you see these messages appearing?**
- [ ] HEARTBEAT (0) - from System 1, Component 100 - every 1s
- [ ] CAMERA_INFORMATION (259) - from System 1, Component 100 - every 5s ← **NEW, critical!**
- [ ] VIDEO_STREAM_INFORMATION (269) - from System 1, Component 100 - every 5s ← **NEW, critical!**
- [ ] VIDEO_STREAM_STATUS (270) - from System 1, Component 100 - every 2s

**If you see message 259 and 269:** Messages are getting through ✅ → Go to Question 2
**If you DON'T see 259 and 269:** Messages are blocked → See "Messages Not Reaching QGC" section below

### Question 2: What Does QGC Camera Dropdown Show?

In QGC, check for camera selector:
- Some versions: Top toolbar, camera icon/dropdown
- Some versions: Video widget settings (gear icon)
- Some versions: **Vehicle → Camera** menu

**Does "Front" camera appear anywhere?**
- [ ] Yes → Camera is discovered! Check video settings
- [ ] No → QGC not recognizing camera from messages

### Question 3: How is QGC Connected?

**Connection type:**
- [ ] UDP to 10.10.10.2:14550
- [ ] UDP to different IP/port: _______________
- [ ] TCP to 10.10.10.2:5760
- [ ] TCP to different IP/port: _______________

**This matters because:**
- Router has different endpoints with different filters
- TCP port 5760 is commented out in config
- GCS endpoints (GCS3, GCS4, GCS5) might have different filters

## Troubleshooting Paths

### Path A: Messages Not Reaching QGC

If CAMERA_INFORMATION (259) and VIDEO_STREAM_INFORMATION (269) don't appear in MAVLink Inspector:

**Cause:** Router is still filtering or not forwarding to QGC endpoint

**Solution 1: Check Which Router Endpoint QGC Uses**

The router has these endpoints:
- GCS3: 10.10.10.98:14550 (Normal mode)
- GCS4: 10.10.10.126:14550 (Normal mode)
- GCS5: 10.10.10.102:14550 (Normal mode)
- video0: Server on 0.0.0.0:14560
- Cmpsrv: Server on 0.0.0.0:14561

Check what IP address QGC is running on:
```bash
# On QGC computer
ifconfig | grep "inet "
```

If QGC is at 10.10.10.XXX, it should match one of the GCS endpoints.

**Solution 2: Check GCS Endpoint Filters**

The GCS endpoints (GCS3, GCS4, GCS5) might also have `AllowMsgIdOut` filters!

Check router config:
```bash
kubectl get configmap rpi4-config -n rpiuav -o yaml | grep -A 5 "GCS"
```

If GCS endpoints have filters, they also need: `75,76,259,269,270`

**Solution 3: Use TCP Instead**

Enable TCP server in router and connect QGC via TCP:

1. Uncomment TcpServerPort in router config:
   ```ini
   TcpServerPort=5760
   ```

2. Restart router

3. In QGC, add connection: TCP to 10.10.10.2:5760

### Path B: Messages Reach QGC But Camera Not Shown

If you SEE messages 259 and 269 in MAVLink Inspector but camera doesn't appear:

**Possible Causes:**

1. **QGC doesn't recognize camera from broadcasts alone**
   - Some QGC versions need request/response handshake
   - Solution: Wait for QGC to send MAV_CMD_REQUEST_MESSAGE

2. **Camera URL format issue**
   - Current: `rtsp://10.10.10.2:8554/cam`
   - QGC might need different format
   - Try: `rtsp://10.10.10.2:8554/video0` (matches old annotation)

3. **CAMERA_INFORMATION has invalid fields**
   - Check vendor_name, model_name are valid strings
   - Check flags are correct bitmap

4. **QGC 5.0.7 specific issue**
   - This version might have bugs/quirks with camera discovery
   - Try latest QGC daily build

### Path C: Manual Configuration as Workaround

If auto-discovery doesn't work, manually configure video:

1. In QGC: **Settings → General → Video**
2. Set **Video Source** to: **RTSP Video Stream**
3. Set **RTSP URL** to: `rtsp://10.10.10.2:8554/cam`
4. Video should appear

This bypasses MAVLink discovery entirely.

## Debugging Commands

### Check Actual Message Content

Enable detailed logging:
```bash
# Add to camera_manager.ex in handle_info(:send_camera_info)
Logger.info("CAMERA_INFO: #{inspect(camera_info)}")
Logger.info("STREAM_INFO: #{inspect(stream_info)}")
```

Redeploy and check logs for exact message content.

### Capture MAVLink Traffic

On the drone (if accessible):
```bash
# Capture packets on router's video0 port
tcpdump -i any -n port 14560 -w /tmp/mavlink.pcap -c 1000
```

Download and analyze with Wireshark + MAVLink dissector.

### Test Direct Connection

Bypass router - connect camera directly to QGC:

1. Change announcer deployment:
   ```yaml
   - name: SYSTEM_HOST
     value: "10.10.10.XXX"  # QGC IP directly
   - name: SYSTEM_PORT
     value: "14550"
   ```

2. In QGC, add UDP connection on port 14550
3. See if camera appears

If this works, it's a router configuration issue.

## Most Likely Issues (Ranked)

### 1. GCS Endpoints Also Have Filters (90% likely)

The `AllowMsgIdOut` filter on video0 was fixed, but GCS endpoints (GCS3, GCS4, GCS5) might also filter outgoing messages.

**Check:**
```bash
kubectl get configmap rpi4-config -n rpiuav -o yaml | grep -B 2 -A 5 "GCS"
```

If GCS endpoints have `AllowMsgIdOut`, update them to include: `259,269,270`

### 2. Camera Messages Going to video0, QGC Connected to Different Endpoint (50% likely)

Camera sends to port 14560 (video0 endpoint)
QGC might be connected via GCS endpoint

Router might not forward between endpoints correctly.

**Solution:** Check how QGC is connected and ensure it uses an endpoint that receives camera messages.

### 3. QGC Version Quirk (30% likely)

QGC 5.0.7 might have specific requirements or bugs.

**Solution:** Try QGC daily build or version 4.3.x

### 4. URL Format Issue (10% likely)

Stream URL `rtsp://10.10.10.2:8554/cam` might not match what QGC expects.

**Solution:** Try changing to `/video0` or absolute URL format.

## Next Steps

1. **Answer Question 1**: Do messages 259 and 269 appear in QGC MAVLink Inspector?

2. **If NO:**
   - Check GCS endpoint filters
   - Check which endpoint QGC is connected to
   - Try enabling TCP server and connecting via TCP

3. **If YES:**
   - Check if there's a camera dropdown/selector in QGC
   - Check QGC logs for camera discovery
   - Try manual RTSP configuration as workaround
   - Consider QGC version issue

**Please answer Question 1 first** - everything else depends on whether the messages are actually reaching QGC or not!
