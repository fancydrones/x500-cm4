# Main Profile Deployment Guide

## Changes Made

### 1. Camera Encoder Configuration
**File**: `apps/video_streamer/lib/membrane_rpicam/source.ex:161`

Changed from Baseline to Main Profile with CM5 optimizations:
```elixir
# Before:
--profile baseline

# After:
--profile main --level 4.0 --libav-video-codec-opts preset=fast,tune=zerolatency
```

### 2. SDP Profile-Level-ID
**File**: `apps/video_streamer/lib/video_streamer/rtsp/sdp.ex:88`

Changed profile-level-id from Constrained Baseline to Main:
```elixir
# Before:
profile_level_id = "42C01F"  # Constrained Baseline, Level 3.1

# After:
profile_level_id = "4D0028"  # Main Profile, Level 4.0
```

### 3. SPS/PPS (Needs Update After Deployment)
**Status**: ⚠️ TEMPORARY - Still using Baseline SPS/PPS

The current SPS/PPS are from Baseline Profile and don't match the new Main Profile stream. This will work but is not optimal. Must be updated after deployment.

## Deployment Steps

### Step 1: Deploy Code ✅
```bash
# On Raspberry Pi CM5
cd /path/to/x500-cm4
git pull
cd apps/video_streamer
mix deps.get
mix compile

# Restart service
sudo systemctl restart video_streamer
# OR if running manually:
# pkill -f video_streamer && iex -S mix
```

### Step 2: Verify Stream Works ✅
Test that basic streaming still works:
```bash
# From Mac
vlc rtsp://10.5.0.26:8554/video
```

Expected: Video plays (may have minor issues due to SPS/PPS mismatch)

### Step 3: Extract Main Profile SPS/PPS 🔄

#### 3a. Capture H.264 Stream
```bash
# On your Mac, capture ~10 seconds of Main Profile stream
timeout 10 ffmpeg -rtsp_transport udp -i rtsp://10.5.0.26:8554/video \
  -vframes 1 -c copy -f h264 -y /tmp/main_profile.h264
```

#### 3b. Create Extraction Script
```bash
cat > /tmp/extract_sps_pps.py << 'SCRIPT'
#!/usr/bin/env python3
import base64

# Read the H.264 file
with open('/tmp/main_profile.h264', 'rb') as f:
    data = f.read()

# Find NAL units (start with 00 00 00 01)
nal_units = []
i = 0
while i < len(data):
    if i + 4 <= len(data) and data[i:i+4] == b'\x00\x00\x00\x01':
        start = i + 4  # Skip start code
        # Find next start code
        next_start = data.find(b'\x00\x00\x00\x01', start)
        if next_start == -1:
            next_start = len(data)

        nal_type = data[start] & 0x1F
        nal_data = data[start:next_start]
        nal_units.append((nal_type, nal_data))
        i = next_start
    else:
        i += 1

# Extract SPS (type 7) and PPS (type 8)
sps = None
pps = None

for nal_type, nal_data in nal_units:
    if nal_type == 7:
        sps = nal_data
        print(f"SPS found: {len(nal_data)} bytes")
        print(f"SPS hex: {nal_data.hex()}")
        print(f"SPS base64: {base64.b64encode(nal_data).decode()}")

        # Extract profile-level-id from SPS
        if len(nal_data) >= 4:
            profile = nal_data[1]
            constraints = nal_data[2]
            level = nal_data[3]
            profile_level_id = f"{profile:02X}{constraints:02X}{level:02X}"
            print(f"Profile-Level-ID: {profile_level_id}")

    elif nal_type == 8:
        pps = nal_data
        print(f"\nPPS found: {len(nal_data)} bytes")
        print(f"PPS hex: {nal_data.hex()}")
        print(f"PPS base64: {base64.b64encode(pps).decode()}")

if sps and pps:
    sps_b64 = base64.b64encode(sps).decode()
    pps_b64 = base64.b64encode(pps).decode()
    sprop = f"{sps_b64},{pps_b64}"
    print(f"\n=== RESULT ===")
    print(f"sprop-parameter-sets: {sprop}")
    print(f"\nAdd this to sdp.ex line 99:")
    print(f'default_sps_pps = "{sprop}"')
else:
    print("\nERROR: Could not find both SPS and PPS")
SCRIPT

chmod +x /tmp/extract_sps_pps.py
```

#### 3c. Run Extraction
```bash
python3 /tmp/extract_sps_pps.py
```

**Expected output:**
```
SPS found: XX bytes
SPS hex: 674d0028...
SPS base64: Z00AKD...
Profile-Level-ID: 4D0028  ← Should be Main Profile (4D), Level 4.0 (28)

PPS found: X bytes
PPS hex: 68...
PPS base64: aM...

=== RESULT ===
sprop-parameter-sets: Z00AKD...,aM...

Add this to sdp.ex line 99:
default_sps_pps = "Z00AKD...,aM..."
```

#### 3d. Verify Profile
The extracted Profile-Level-ID should be:
- **4D0028** = Main Profile (4D), Level 4.0 (28)
- NOT 42C01F (Constrained Baseline)

If you see 42C01F, the camera is still using Baseline - check deployment!

### Step 4: Update SDP with Real SPS/PPS ✅

Edit `apps/video_streamer/lib/video_streamer/rtsp/sdp.ex` line 99:

```elixir
# Replace:
default_sps_pps = "Z0LAH9oBQBbpqAgICgAAAwACAD0JAB4wZUA=,aM4PyA=="

# With the extracted value from Step 3c:
default_sps_pps = "Z00AKD...,aM..."  # Your extracted Main Profile SPS/PPS
```

### Step 5: Recompile and Restart ✅
```bash
# On Raspberry Pi CM5
cd apps/video_streamer
mix compile
sudo systemctl restart video_streamer
```

### Step 6: Verify Final Configuration ✅

#### 6a. Check SDP
```bash
# From Mac
echo "DESCRIBE rtsp://10.5.0.26:8554/video RTSP/1.0
CSeq: 1
Accept: application/sdp

" | nc 10.5.0.26 8554 | grep "a=fmtp"
```

**Expected:**
```
a=fmtp:96 packetization-mode=1;profile-level-id=4D0028;sprop-parameter-sets=Z00AKD...,aM...
```

Verify:
- ✅ `profile-level-id=4D0028` (Main Profile, Level 4.0)
- ✅ `sprop-parameter-sets` matches what you extracted
- ❌ NOT `42C01F` or old Baseline SPS/PPS

#### 6b. Test All Clients
1. **macOS VLC**: Should work perfectly
2. **iOS IP Camera Viewer**: Should work (test!)
3. **QGroundControl**: Test when available

#### 6c. Check Stream Properties
```bash
ffprobe -rtsp_transport udp rtsp://10.5.0.26:8554/video 2>&1 | grep -E "Stream|profile|bitrate"
```

**Expected:**
```
Stream #0:0: Video: h264 (Main), yuv420p(tv, bt709, progressive), 1280x720, 30 fps
                           ^^^^
bitrate: ~2000 kb/s  (down from ~2500 kb/s with Baseline)
```

### Step 7: Performance Monitoring

#### CPU Usage
```bash
# On Raspberry Pi
top -p $(pgrep rpicam-vid)
```
**Expected**: ~40% of one core @ 720p30 (acceptable)

#### Bitrate
```bash
# From Mac
ffprobe -rtsp_transport udp rtsp://10.5.0.26:8554/video 2>&1 | grep bitrate
```
**Expected**: ~2.0 Mbps (down from ~2.5 Mbps Baseline)
**Savings**: ~20% bandwidth reduction

#### Latency
Test glass-to-glass latency with stopwatch in frame.
**Expected**: <200ms total (may be +30ms vs Baseline due to software encoding)

## Troubleshooting

### Issue: Stream won't start
**Symptom**: rpicam-vid fails to start or errors immediately

**Check**:
```bash
# Manually test rpicam-vid command
rpicam-vid -t 5000 --codec h264 --profile main --level 4.0 \
  --libav-format h264 --libav-video-codec-opts preset=fast,tune=zerolatency \
  --framerate 30 --width 1280 --height 720 --nopreview -o /tmp/test.h264
```

**If fails**: Check rpicam-vid version, libx264 installation
**Solution**: Ensure Raspberry Pi OS is up to date

### Issue: Clients can't decode video
**Symptom**: Black screen or "codec not supported" errors

**Cause**: SPS/PPS mismatch (using Baseline SPS/PPS with Main Profile stream)

**Solution**: Complete Steps 3-5 to extract and update Main Profile SPS/PPS

### Issue: Very high CPU usage
**Symptom**: CPU >80%, dropped frames, choppy video

**Cause**: `preset=fast` may be too slow for your CM5 workload

**Solution**: Reduce preset to `superfast`:
```elixir
# In source.ex line 161, change:
--libav-video-codec-opts preset=superfast,tune=zerolatency
```
**Trade-off**: Slightly less compression (~2.1 Mbps instead of 2.0 Mbps)

### Issue: High latency (>300ms)
**Symptom**: Noticeable delay glass-to-glass

**Cause**: Software encoding + `fast` preset adds latency

**Solution**: Use `superfast` or `ultrafast` preset, or increase GOP size:
```elixir
# Reduce latency (less compression):
--libav-video-codec-opts preset=superfast,tune=zerolatency,g=30

# g=30 means keyframe every 30 frames (1 second @ 30fps)
```

### Issue: iOS still shows "audio-only"
**Symptom**: iOS VLC still broken

**Status**: This is an iOS VLC bug, unrelated to profile change

**Solution**: Use IP Camera Viewer or wait for VLC update

## Expected Results

After complete deployment with Main Profile SPS/PPS:

| Metric | Before (Baseline) | After (Main) | Improvement |
|--------|-------------------|--------------|-------------|
| **Bitrate** | ~2.5 Mbps | ~2.0 Mbps | 20% savings |
| **CPU Usage** | ~30% | ~40% | +10% (acceptable) |
| **Latency** | ~140ms | ~170ms | +30ms (acceptable) |
| **Compatibility** | Universal | Modern (2011+) | Still excellent |
| **Quality** | Good | Better | Same bitrate = better quality |

## Verification Checklist

- [ ] Code deployed to CM5
- [ ] Stream starts successfully
- [ ] SDP shows profile-level-id=4D0028
- [ ] Main Profile SPS/PPS extracted
- [ ] SDP updated with real SPS/PPS
- [ ] macOS VLC plays correctly
- [ ] iOS IP Camera Viewer plays correctly
- [ ] Bitrate reduced to ~2.0 Mbps
- [ ] CPU usage ~40% (acceptable)
- [ ] Latency <200ms
- [ ] Multi-client tested (2+ clients)

## Success Criteria

✅ **Deployment successful when:**
1. Stream plays on all tested clients
2. SDP contains Main Profile parameters (4D0028)
3. SPS/PPS match camera output (extracted from stream)
4. Bitrate ~20% lower than before (~2.0 Mbps)
5. CPU usage acceptable (<50% of one core)
6. Latency acceptable (<200ms)

---

**Status**: Ready to deploy
**Next**: Follow steps 1-7, then update Phase 3 notes with Main Profile completion
