# iOS VLC Fix - Real SPS/PPS Parameter Sets

## Problem Summary
iOS VLC was showing "audio-only" track while macOS VLC worked perfectly. The root cause was a mismatch between the SPS/PPS (Sequence/Picture Parameter Sets) advertised in the SDP and the actual SPS/PPS sent by the camera in the H.264 stream.

## Root Cause Analysis

### What are SPS/PPS?
- **SPS (Sequence Parameter Set)**: Contains H.264 stream parameters like resolution, profile, level
- **PPS (Picture Parameter Set)**: Contains picture coding parameters
- These are critical NAL units that decoders need to initialize before decoding video

### Why iOS is Strict
- **iOS VLC**: Pre-initializes decoder using SPS/PPS from SDP's `sprop-parameter-sets` field
- **macOS VLC**: More forgiving, can initialize decoder when it receives SPS/PPS in the stream
- **Result**: If SDP SPS/PPS don't match stream SPS/PPS, iOS decoder fails to decode

### The Mismatch
**Before (Generic SPS/PPS):**
```
sprop-parameter-sets=Z0IAH6aAoD2A,aM4G8g==
```
This was a generic Baseline Profile parameter set that didn't match our camera.

**After (Real Camera SPS/PPS):**
```
sprop-parameter-sets=Z0LAH9oBQBbpqAgICgAAAwACAD0JAB4wZUA=,aM4PyA==
```
Extracted from actual rpicam-vid H.264 stream.

## How the Fix Was Applied

### Step 1: Extract Real SPS/PPS from Camera
```bash
# Capture actual H.264 stream from camera
timeout 10 ffmpeg -rtsp_transport udp -i rtsp://10.5.0.26:8554/video \
  -vframes 1 -c copy -f h264 -y /tmp/test.h264
```

### Step 2: Parse NAL Units
Created Python script to extract NAL units from H.264 file:
- Found SPS (NAL type 7): 26 bytes
- Found PPS (NAL type 8): 4 bytes
- Base64 encoded both

### Step 3: Verify Profile-Level-ID
Extracted from SPS:
- Profile: `0x42` (Baseline)
- Constraints: `0xC0` (Constrained)
- Level: `0x1F` (3.1)
- Result: **42C01F** ✓ (matches what we set)

### Step 4: Update SDP Module
Updated `apps/video_streamer/lib/video_streamer/rtsp/sdp.ex`:
```elixir
# Old:
profile_level_id = Map.get(codec_params, :profile_level_id, "42E01F")
default_sps_pps = "Z0IAH6aAoD2A,aM4G8g=="

# New:
profile_level_id = Map.get(codec_params, :profile_level_id, "42C01F")
default_sps_pps = "Z0LAH9oBQBbpqAgICgAAAwACAD0JAB4wZUA=,aM4PyA=="
```

## Verification After Deployment

### 1. Check SDP on Server
```bash
echo "DESCRIBE rtsp://10.5.0.26:8554/video RTSP/1.0
CSeq: 1
Accept: application/sdp

" | nc 10.5.0.26 8554
```

**Expected in SDP:**
```
a=fmtp:96 packetization-mode=1;profile-level-id=42C01F;sprop-parameter-sets=Z0LAH9oBQBbpqAgICgAAAwACAD0JAB4wZUA=,aM4PyA==
```

### 2. Test with iOS VLC
1. Open VLC on iPad/iPhone
2. Connect to: `rtsp://10.5.0.26:8554/video`
3. **Expected**: Video should now display correctly (not just audio)

### 3. Verify with ffprobe
```bash
ffprobe -rtsp_transport udp rtsp://10.5.0.26:8554/video
```

**Expected**: No errors like "non-existing PPS 0 referenced"

### 4. Multi-Device Test
- macOS VLC: Should still work ✓
- iOS VLC: Should now work ✓
- QGroundControl: Should work ✓

## Technical Details

### Actual SPS Breakdown
```
Hex: 6742c01fda014016e9a808080a0000030002003d09001e306540
Base64: Z0LAH9oBQBbpqAgICgAAAwACAD0JAB4wZUA=

Byte 0: 0x67 = NAL type 7 (SPS)
Byte 1: 0x42 = Profile IDC (Baseline)
Byte 2: 0xC0 = Constraint flags (Constrained Baseline)
Byte 3: 0x1F = Level IDC (3.1)
Bytes 4-25: Additional SPS parameters (resolution, timing, etc.)
```

### Actual PPS Breakdown
```
Hex: 68ce0fc8
Base64: aM4PyA==

Byte 0: 0x68 = NAL type 8 (PPS)
Bytes 1-3: PPS parameters
```

## Why This Matters

1. **iOS Compatibility**: Essential for drone operators using iPads for ground control
2. **QGroundControl**: May have similar strict requirements
3. **Reliability**: Ensures decoder initialization matches actual stream
4. **Standard Compliance**: RFC 6184 recommends including sprop-parameter-sets

## Commits
- `97bf670` - fix: Use real camera SPS/PPS in SDP for iOS VLC compatibility

## References
- RFC 6184: RTP Payload Format for H.264 Video
- RFC 4566: SDP: Session Description Protocol
- H.264 Specification: ITU-T Rec. H.264

## Next Steps After This Fix
Once iOS VLC works, complete Phase 3 testing:
- Multi-client stress test (3+ simultaneous iOS/macOS clients)
- Performance metrics collection
- QGroundControl compatibility verification
- Update implementation checklist

---
**Status**: Ready for deployment and testing on hardware
