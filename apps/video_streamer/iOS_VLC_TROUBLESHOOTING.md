# iOS VLC "Audio Only" Troubleshooting

## Problem
VLC on iPad shows only an "audio track" when connecting to the RTSP stream, while VLC on macOS works correctly with video.

## Possible Causes & Solutions

### 1. Check the SDP (Most Likely Cause)

The SDP might be confusing iOS VLC. Let's inspect it:

**Test Command (on your Mac):**
```bash
# Connect with curl and capture the DESCRIBE response
curl -v rtsp://<pi-ip>:8554/video \
  -X DESCRIBE \
  -H "Accept: application/sdp"
```

**Look for in the SDP:**
```
m=video 0 RTP/AVP 96          ← Should say "video" not "audio"
a=rtpmap:96 H264/90000         ← Should be H264, not something else
a=fmtp:96 packetization-mode=1;profile-level-id=64001F
a=framerate:30
a=framesize:96 1920-1080
a=type:broadcast               ← New attribute added
a=x-dimensions:1920,1080       ← New attribute added
```

**What to check:**
- First line MUST be `m=video` not `m=audio`
- rtpmap MUST be `H264/90000`
- fmtp should have proper H.264 parameters

### 2. Profile Compatibility Issue

iOS devices may have trouble with H.264 High Profile (64). The camera defaults to High Profile.

**Current profile in SDP:**
```
profile-level-id=64001F
```
- `64` = High Profile
- `00` = Constraints
- `1F` = Level 3.1

**More compatible profile for iOS:**
```
profile-level-id=42E01F
```
- `42` = Baseline Profile (better iOS support)
- `E0` = Constraints
- `1F` = Level 3.1

**Problem:** We can't change the profile in SDP without matching the actual camera output. The camera currently outputs High Profile.

**Solution Options:**

#### Option A: Configure Camera for Baseline Profile (Recommended)
We need to add a `--profile baseline` parameter to rpicam-vid.

Edit `/Users/royveshovda/src/fancydrones/x500-cm4/apps/video_streamer/lib/membrane_rpicam/source.ex` line 156:

```elixir
# Current:
"#{app_binary} -t #{timeout} --codec h264 --libav-format h264 --framerate #{framerate_float} --width #{width} --height #{height} #{verbose_flag} -o -"

# Change to:
"#{app_binary} -t #{timeout} --codec h264 --profile baseline --libav-format h264 --framerate #{framerate_float} --width #{width} --height #{height} #{verbose_flag} -o -"
```

Then update SDP (`sdp.ex` line 88) to match:
```elixir
profile_level_id = Map.get(codec_params, :profile_level_id, "42E01F")  # Baseline
```

####Option B: Keep High Profile, Document iOS Limitation
Leave as-is and document that iOS VLC may not work. High Profile gives better compression.

### 3. Transport Mode Issue

Some iOS clients prefer TCP over UDP for RTSP.

**Test with TCP:**
On iPad VLC, try:
- Settings → Network → RTSP Transport → TCP

**Or specify in URL:**
```
rtsp://<pi-ip>:8554/video?tcp
```

### 4. Port Forwarding / Network Issue

If iPad is on different network than Mac:
- Check firewall allows RTSP (8554) and RTP (50000) ports
- Try from same WiFi network

### 5. VLC iOS Version Quirks

Some VLC iOS versions have H.264 decoding issues.

**Test:**
- Update VLC to latest version on iPad
- Try different iOS RTSP client (e.g., "RTSP Player" from App Store)

### 6. Codec Capabilities

iOS hardware may not support the resolution/profile combination.

**Test with lower resolution:**
Temporarily edit config to 720p:
```elixir
# config/runtime.exs or config/config.exs
camera: [
  width: 1280,
  height: 720,
  framerate: 30
]
```

### 7. SPS/PPS Missing

iOS clients may require SPS/PPS in the SDP.

**Check if we're sending SPS/PPS:**
Currently we're not extracting them from the H.264 stream. This might be the issue!

**Potential Fix:**
We have `repeat_parameter_sets: true` in the H.264 parser, which should include SPS/PPS in the stream, but we're not advertising them in the SDP.

## Diagnostic Steps

### Step 1: Verify SDP is correct
```bash
# Save SDP to file
curl rtsp://<pi-ip>:8554/video \
  -X DESCRIBE \
  -H "Accept: application/sdp" \
  > stream.sdp

# Check content
cat stream.sdp
```

Should look like:
```
v=0
o=- <session-id> <version> IN IP4 <pi-ip>
s=VideoStreamer H.264 Stream
i=Low-latency H.264 video stream
c=IN IP4 <pi-ip>
t=0 0
a=control:*
a=range:npt=0-
m=video 0 RTP/AVP 96
a=rtpmap:96 H264/90000
a=fmtp:96 packetization-mode=1;profile-level-id=64001F
a=control:/video/trackID=0
a=framerate:30
a=framesize:96 1920-1080
a=type:broadcast
a=x-dimensions:1920,1080
```

### Step 2: Test with ffplay on Mac
```bash
# This should work if SDP is correct
ffplay -rtsp_transport tcp rtsp://<pi-ip>:8554/video
```

### Step 3: Test with gstreamer on Mac
```bash
gst-launch-1.0 -v rtspsrc location=rtsp://<pi-ip>:8554/video ! \
  rtph264depay ! h264parse ! avdec_h264 ! videoconvert ! autovideosink
```

This will show detailed info about the H.264 stream including profile.

### Step 4: Check iPad Logs

On iPad with VLC:
1. Settings → Advanced → Network Logging → Enable
2. Connect to stream
3. Check logs for errors

## Recommended Fix Priority

1. **First, verify SDP** (Step 1 above) - make sure it says "m=video"
2. **Try TCP transport** on iPad VLC settings
3. **Switch to Baseline Profile** (Option A above) - best for mobile compatibility
4. **Test with different iOS client** - verify it's not just VLC

## Quick Test: Baseline Profile

If you want to quickly test Baseline Profile:

```bash
# SSH to Raspberry Pi
cd /path/to/x500-cm4/apps/video_streamer

# Edit source.ex line 156, add --profile baseline
nano lib/membrane_rpicam/source.ex

# Edit sdp.ex line 88, change to 42E01F
nano lib/video_streamer/rtsp/sdp.ex

# Recompile
mix compile

# Restart service or re-run
```

Then test iPad VLC again.

## Expected Result

After fixing, iOS VLC should:
- Show both audio and video tracks in player
- Actually play video (not just show audio track)
- Work as smoothly as macOS VLC

## Current Status

- ✅ Multi-client works (macOS VLC + macOS VLC)
- ✅ Desktop VLC works
- ✅ **FIXED** (2025-10-22): Switched to H.264 Baseline Profile for iOS compatibility

## Fix Applied

Changed from H.264 High Profile to Baseline Profile:
- **Camera** (`source.ex`): Added `--profile baseline` parameter to rpicam-vid
- **SDP** (`sdp.ex`): Changed profile-level-id from `64001F` (High) to `42E01F` (Baseline)

### Deployment Steps

1. Pull latest code (commit `0824065`)
2. Recompile: `mix compile`
3. Restart video_streamer service
4. Test with iOS VLC

### Verification

Check SDP has correct profile:
```bash
curl rtsp://<pi-ip>:8554/video -X DESCRIBE -H "Accept: application/sdp" | grep profile-level-id
```

Should show: `a=fmtp:96 packetization-mode=1;profile-level-id=42E01F`

**iOS VLC should now display video correctly!**
