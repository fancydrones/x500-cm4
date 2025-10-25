# Android Video Streaming Setup and Troubleshooting

## Working Configuration

This document describes the optimized video streaming setup for Android devices running QGroundControl (QGC).

### Tested Devices

#### ✅ Working Perfectly
- **Samsung Galaxy A55** - Smooth, jitter-free video streaming

#### ⚠️ Known Issues
- **Samsung Galaxy Tab A9 (SM-X110)** - High latency, jitter, video drops every 30 seconds
  - Root cause: Poor hardware decoder support / QGC Android decoder issues
  - See "Known Device Issues" section below

### Network Setup

- **WiFi**: Local WiFi network (10.10.10.x)
- **VPN**: ZeroTier mesh network for future 4G connectivity
- **Protocol**: RTP over UDP
- **Port**: 14550 (QGC default)

### Video Encoder Settings

All settings are configured in [deployments/apps/video-streamer-deployment.yaml](../deployments/apps/video-streamer-deployment.yaml):

```yaml
# Resolution and framerate
STREAM_WIDTH: "1280"
STREAM_HEIGHT: "720"
STREAM_FPS: "30"

# H.264 encoder settings
H264_PROFILE: "main"              # Main profile for better compression
H264_LEVEL: "4.1"                 # Supports up to 1080p30
H264_BITRATE: "5000000"           # 5 Mbps bitrate
KEYFRAME_INTERVAL: "30"           # 1 second (industry standard for streaming)

# Streaming optimizations
H264_INLINE_HEADERS: "true"       # SPS/PPS before every keyframe (mobile compatibility)
H264_FLUSH: "false"               # Allow encoder buffering (matches MediaMTX)
H264_LOW_LATENCY: "true"          # Reduces encoding latency from 8 frames to 1 frame
H264_DENOISE: "cdn_off"           # Disable color denoise (prevents frame jitter)
H264_BUFFER_COUNT: "12"           # Double default buffers (smooths keyframe bursts)
```

### RTP Packetization Settings

Configured in [apps/video_streamer/lib/video_streamer/pipeline.ex](../apps/video_streamer/lib/video_streamer/pipeline.ex):

```elixir
# RTP packet size optimized for WiFi (1200 bytes)
# Reduced from default 1400 to prevent fragmentation
payloader: %Membrane.RTP.H264.Payloader{max_payload_size: 1200}

# H.264 parser settings
output_alignment: :nalu
generate_best_effort_timestamps: true
repeat_parameter_sets: false  # Don't repeat SPS/PPS (already in inline headers)
```

### Critical rpicam-vid Flags

The following flags are essential for smooth Android streaming:

1. **`--low-latency`** (rpicam-vid v1.6.0+)
   - Reduces encoding latency from 8 frames to 1 frame
   - Disables B-frames and arithmetic coding
   - **Critical for eliminating keyframe jitter**

2. **`--denoise cdn_off`**
   - Disables color denoise processing
   - Color denoise causes frame jitter and drops at higher framerates
   - **Essential for smooth streaming**

3. **`--buffer-count 12`**
   - Doubles default buffer count (6 → 12)
   - Smooths out keyframe bursts
   - **Reduces periodic jitter caused by large keyframes**

4. **`--inline`**
   - Inserts SPS/PPS headers before every keyframe
   - Allows Android decoders to start mid-stream
   - **Required for mobile compatibility**

## Optimization Journey

### Problem: Video Jitter Every 2 Seconds

**Initial symptoms:**
- Visible jitter on Android QGC every 2 seconds
- Jitter correlated exactly with keyframe interval (60 frames / 30 fps = 2 seconds)

**Solutions applied:**

1. **Added `--low-latency` flag**
   - Discovered the flag was defined but NOT being passed through pipeline
   - Fixed pipeline.ex to actually use the flag
   - Result: Significant improvement

2. **Added `--denoise cdn_off`**
   - Color denoise processing causes frame jitter
   - MediaMTX uses denoise="off" by default
   - Result: Much smoother video

3. **Disabled `repeat_parameter_sets` in H.264 parser**
   - MediaMTX has `V4L2_CID_MPEG_VIDEO_REPEAT_SEQ_HEADER` disabled
   - We already have inline headers from rpicam-vid
   - Repeating SPS/PPS again was causing overhead
   - Result: Reduced keyframe overhead

4. **Added `--buffer-count 12`**
   - Keyframes are 10x larger than P-frames
   - More buffers smooth out periodic traffic bursts
   - Result: Much better, tiny jitter every 6 seconds

5. **Reduced keyframe interval to 30 frames**
   - Changed from 60 frames (2 seconds) to 30 frames (1 second)
   - Industry standard for streaming is 1-2 seconds
   - Result: ✅ **All jitter eliminated on Samsung A55**

### Timeline of Improvements

| Change | Jitter Pattern |
|--------|----------------|
| Initial (60-frame GOP, no optimizations) | Jitter every 2 seconds |
| After low-latency + denoise | Much better |
| After buffer-count + disable repeat | Tiny jitter every 6 seconds |
| After 30-frame GOP | ✅ No jitter |

## Known Device Issues

### Samsung Galaxy Tab A9 (SM-X110)

**Symptoms:**
- High latency (3-5 seconds)
- Severe jitter
- Video drops completely every ~30 seconds
- Same network as working Samsung A55

**Root Cause:**

QGroundControl on Android 10+ has known video decoder issues:
- Android 10 introduced Codec2.0, replacing ACodec and OpenMAX
- QGC may not be using hardware acceleration on some Android tablets
- Falls back to software decoding, causing poor performance
- GStreamer may not fully support Android's Codec2 API

**Samsung Tab A9 Specific Issues:**
- MediaTek Helio G99 processor with Mali-G57 MC2 GPU
- Known GPU driver performance issues on stock firmware
- Video decoder errors with native resolution support
- February 2025 update partially addressed performance issues

**Possible Solutions:**

1. **Try Baseline Profile (RECOMMENDED)** ⭐
   - Change `H264_PROFILE: "main"` → `H264_PROFILE: "baseline"` in deployment
   - Baseline uses CAVLC entropy coding (simpler than Main's CABAC)
   - Android officially guarantees hardware decoding for baseline profile
   - Main profile support varies by device - Tab A9 might lack it
   - See "Tablet-Optimized Configuration" below

2. **Update QGroundControl** to latest version
   - Check if newer QGC versions have better Android decoder support

3. **Update tablet firmware**
   - Samsung released updates addressing decoder and performance issues
   - Check for latest Android/One UI updates

4. **Reduce H.264 Level**
   - Change from level 4.1 to 3.1 (both support 720p30)
   - Lower levels may have better hardware support

5. **Reduce video resolution/bitrate** (if needed)
   - Try 640x480 or 848x480 instead of 1280x720
   - Reduce bitrate from 5 Mbps to 2-3 Mbps
   - These are workarounds, not ideal solutions

6. **Use different Android device**
   - Samsung A55 works perfectly with current settings
   - Look for devices with Snapdragon processors (better Android codec support)

7. **Test with different QGC video backend** (if available)
   - Some QGC builds may have different decoder options
   - Check QGC settings for hardware acceleration toggles

### Tablet-Optimized Configuration

For Samsung Galaxy Tab A9 and other devices with limited codec support, try these settings:

```yaml
# Tablet-friendly encoder settings
H264_PROFILE: "baseline"          # Changed from "main" - better hardware support
H264_LEVEL: "3.1"                 # Changed from "4.1" - sufficient for 720p30
H264_BITRATE: "3000000"           # Reduced from 5000000 (3 Mbps)
KEYFRAME_INTERVAL: "30"           # Keep at 1 second
STREAM_WIDTH: "1280"              # Keep same
STREAM_HEIGHT: "720"              # Keep same
STREAM_FPS: "30"                  # Keep same

# Keep all other optimization flags
H264_LOW_LATENCY: "true"
H264_DENOISE: "cdn_off"
H264_BUFFER_COUNT: "12"
H264_INLINE_HEADERS: "true"
H264_FLUSH: "false"
```

**Profile Comparison:**

| Feature | Baseline | Main | Impact |
|---------|----------|------|--------|
| Entropy Coding | CAVLC | CABAC | CABAC 10-15% better compression |
| Computational Complexity | Low | Medium | Baseline easier to decode |
| Android Hardware Support | Guaranteed | Varies | Baseline more compatible |
| B-frames | No | Yes | Not used with --low-latency anyway |
| File Size | +10-15% | Baseline | Acceptable trade-off for compatibility |

Since we're using `--low-latency` mode (which already disables B-frames), switching to baseline profile mainly affects entropy coding. The ~10-15% bitrate increase is acceptable for ensuring hardware decoding works.

### References

- QGC Issue #7331: Poor performance in video decoding on Android
- QGC Issue #10301: Android 10+, video decoding using soft decoding
- MediaMTX hardware encoder settings: [mediamtx-rpicamera encoder_hardware_h264.c](https://github.com/bluenviron/mediamtx-rpicamera)

## Video Streaming Architecture

```
┌─────────────────┐
│  Raspberry Pi   │
│   Camera V3     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   rpicam-vid    │
│  - H.264 encode │
│  - Low latency  │
│  - Denoise off  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Membrane        │
│ - H.264 parser  │
│ - RTP payloader │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   UDP Socket    │
│   Port 14550    │
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
┌────────┐ ┌──────────┐
│  WiFi  │ │ ZeroTier │
└────┬───┘ └────┬─────┘
     │          │
     └────┬─────┘
          │
          ▼
    ┌──────────────┐
    │   Router     │
    └──────┬───────┘
           │
      ┌────┴────┐
      │         │
      ▼         ▼
┌──────────┐ ┌──────────┐
│ A55      │ │ Tab A9   │
│ ✅ Works │ │ ⚠️ Issues│
└──────────┘ └──────────┘
```

## Performance Metrics

### Samsung Galaxy A55 (Working)
- **Latency**: ~200-300ms (typical for RTP streaming)
- **Jitter**: None
- **Stability**: No drops
- **CPU Usage**: Low (hardware decoding)

### Samsung Galaxy Tab A9 (Issues)
- **Latency**: 3-5 seconds
- **Jitter**: Severe
- **Stability**: Drops every ~30 seconds
- **CPU Usage**: High (likely software decoding)

## Troubleshooting Tips

### Test Video Quality
1. Compare with VLC on same device
2. Check if other Android devices work
3. Verify network bandwidth (use iperf3)
4. Check QGC logs for decoder messages

### Network Diagnostics
```bash
# Test latency to drone
ping <drone-ip>

# Test bandwidth
iperf3 -c <drone-ip>

# Monitor packet loss
watch -n 1 'netstat -su | grep -i "packet receive errors"'
```

### Encoder Diagnostics
```bash
# View video streamer logs
kubectl logs -n rpiuav -l app=video-streamer-replicaset --tail=50

# Check rpicam-vid command
kubectl exec -n rpiuav -l app=video-streamer-replicaset -- ps aux | grep rpicam
```

## Future Optimizations

Potential improvements to explore:

1. **Adaptive bitrate** based on network conditions
2. **Multiple quality streams** (let client choose)
3. **WebRTC support** (lower latency, better NAT traversal)
4. **Forward Error Correction (FEC)** for packet loss resilience
5. **Dynamic GOP size** based on scene complexity

## Related Documentation

- [Video Streamer Source Code](../apps/video_streamer/)
- [Deployment Configuration](../deployments/apps/video-streamer-deployment.yaml)
- [Membrane Rpicam Source](../apps/video_streamer/lib/membrane_rpicam/source.ex)
- [Video Pipeline](../apps/video_streamer/lib/video_streamer/pipeline.ex)
