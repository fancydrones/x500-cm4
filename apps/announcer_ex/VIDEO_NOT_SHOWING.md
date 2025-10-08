# Camera Discovered But Video Not Showing

## Current Status ✅

- ✅ CAMERA_INFORMATION (259) appearing in QGC MAVLink Inspector
- ✅ VIDEO_STREAM_INFORMATION (269) appearing in QGC MAVLink Inspector
- ✅ VIDEO_STREAM_STATUS (270) appearing in QGC MAVLink Inspector
- ✅ Both messages pack successfully (`:ok` in logs)
- ❌ Video feed not displaying in QGC

## This Means

The **MAVLink camera discovery protocol is working correctly!** QGC is receiving all the camera information. The issue is now with:
1. QGC recognizing the camera in its UI
2. QGC connecting to the video stream
3. Or the video stream URL/format

## Diagnostic Questions

### Q1: Does "Front" camera appear in QGC UI?

Check these locations in QGC v5.0.7:
- **Top toolbar** - Camera icon/selector
- **Video widget** - Click gear icon → Camera selector
- **Vehicle menu** - Look for Camera submenu
- **Fly view** - Video widget settings

**If camera appears in UI:**
- Select it and see if video starts
- Check for error messages
- Go to Q2

**If camera does NOT appear in UI:**
- QGC might not support MAVLink camera discovery in this version
- Or requires additional configuration
- Go to Q3

### Q2: What happens when you select the camera?

If camera appears in selector:
- Does clicking it do anything?
- Any error messages?
- Does video widget change state?

### Q3: Does manual RTSP work?

To isolate if it's a MAVLink issue or stream issue:

1. QGC → **Settings → General → Video**
2. **Source**: RTSP Video Stream
3. **RTSP URL**: `rtsp://10.10.10.2:8554/cam`
4. **Does video appear?**

**If YES:** Stream works, MAVLink discovery/selection issue
**If NO:** Stream itself has issues (network, codec, etc.)

## Common Issues

### Issue 1: QGC Doesn't Show Camera UI (Most Likely)

**Symptoms:** Messages appear in Inspector but no camera in QGC UI

**Cause:** QGC v5.0.7 might not have camera selector UI, or it's hidden

**Solutions:**

1. **Check if video source is still "Disabled"**
   - Settings → Video → Source should be "Disabled" or "Auto"
   - Not manually set to RTSP/UDP

2. **Look for video widget settings**
   - Right-click on video widget
   - Look for camera selection

3. **Check QGC version/build**
   - Some builds don't include camera UI
   - Try QGC daily build

### Issue 2: URI Format Issue

**Symptoms:** Camera appears but video doesn't load

**Cause:** QGC expects different URI format

**Current URI:** `rtsp://10.10.10.2:8554/cam`

**Try alternatives:**
- `rtsp://10.10.10.2:8554/video0` (matches old config)
- Full URI with auth if needed
- Check if stream path is correct

**To change:**
```bash
kubectl edit configmap rpi4-config -n rpiuav
# Change ANNOUNCER_CAMERA_URL
kubectl rollout restart deployment/announcer-ex -n rpiuav
```

### Issue 3: Video Encoding/Codec

**Symptoms:** Camera detected but playback fails

**Cause:** QGC can't decode the stream format

**Check:**
- Is mediamtx/streamer actually running?
- Does the stream work in VLC/other player?
- Codec compatibility with QGC

### Issue 4: Network/Routing

**Symptoms:** Discovery works but can't connect to stream

**Cause:** QGC can reach MAVLink but not video port

**Check:**
- Can QGC reach 10.10.10.2:8554?
- Firewall/network rules
- Try from same network as drone

### Issue 5: QGC Auto-Discovery Not Fully Implemented

**Symptoms:** Everything looks right but nothing happens

**Cause:** QGC 5.0.7 might have incomplete camera discovery

**Evidence:**
- Messages arrive correctly
- No errors
- Just no UI response

**Solution:** Use manual RTSP configuration as workaround

## Testing Steps

### Step 1: Verify Stream Works

Test stream with VLC or ffplay:
```bash
ffplay rtsp://10.10.10.2:8554/cam
# or
vlc rtsp://10.10.10.2:8554/cam
```

If this fails, the stream itself is broken (not a QGC issue).

### Step 2: Check QGC Video Settings

1. **Settings → General → Video**
2. Current settings:
   - Source: _____________
   - RTSP URL: _____________
   - Connection: _____________

3. Try setting:
   - Source: **Disabled** (for auto-discovery)
   - Or Source: **RTSP** with manual URL

### Step 3: Check QGC MAVLink Inspector Details

In Inspector, expand message 269 (VIDEO_STREAM_INFORMATION):
- `uri`: Should show `rtsp://10.10.10.2:8554/cam`
- `type`: Should show RTSP
- `flags`: Should show RUNNING
- `stream_id`: Should be 1
- `count`: Should be 1

### Step 4: Check QGC Logs

Look for camera-related errors:
- Linux: `~/.config/QGroundControl/QGroundControl.log`
- macOS: `~/Library/Application Support/QGroundControl/QGroundControl.log`
- Windows: `%LOCALAPPDATA%\QGroundControl\QGroundControl.log`

Search for: "camera", "video", "stream", "RTSP"

### Step 5: Try QGC Daily Build

QGC 5.0.7 might have issues. Try latest:
- https://docs.qgroundcontrol.com/master/en/getting_started/download_and_install.html#daily-builds

## Most Likely Scenarios

### Scenario A: QGC v5.0.7 Doesn't Have Camera UI (70% likely)

Even though it processes the MAVLink messages, it might not have the UI to display/select cameras.

**Test:** Try manual RTSP configuration
**Solution:** Either upgrade QGC or use manual config

### Scenario B: Video Source Still Manually Set (20% likely)

If video source is set to anything other than "Disabled", QGC won't use auto-discovery.

**Test:** Check Settings → Video → Source
**Solution:** Set to "Disabled"

### Scenario C: Stream URL Wrong (10% likely)

The stream path might be incorrect.

**Test:** Try `rtsp://10.10.10.2:8554/video0` instead of `/cam`
**Solution:** Update ANNOUNCER_CAMERA_URL

## Quick Workaround

While debugging, use manual configuration:

1. QGC → **Settings → General → Video**
2. **Source**: RTSP Video Stream
3. **RTSP URL**: `rtsp://10.10.10.2:8554/cam`

This bypasses MAVLink discovery entirely and should show video if the stream works.

## What to Report Back

Please check and report:

1. ✅/❌ Does "Front" camera appear anywhere in QGC UI?
2. ✅/❌ Does manual RTSP configuration (`rtsp://10.10.10.2:8554/cam`) show video?
3. What does QGC Settings → Video → Source show?
4. What does message 269 `uri` field show in Inspector?

This will tell us exactly where the issue is!
