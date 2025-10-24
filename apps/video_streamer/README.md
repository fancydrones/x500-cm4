# Video Streamer Service

Low-latency RTSP/RTP video streaming service for the x500-cm4 UAV platform using Raspberry Pi Camera (IMX477/IMX219).

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Client Setup](#client-setup)
- [Architecture](#architecture)
- [Development](#development)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)

## Features

- **Low Latency**: Sub-500ms glass-to-glass latency optimized for UAV operations
- **Hardware Acceleration**: Raspberry Pi GPU-accelerated H.264 encoding via rpicam-apps
- **RTSP/RTP Streaming**: Industry-standard protocols compatible with QGroundControl, VLC, ATAK
- **Multi-Client Support**: Simultaneous streaming to multiple clients using dynamic pipeline branching
- **Configurable**: Resolution, framerate, H.264 profile/level, camera orientation all configurable
- **Production Ready**: Containerized deployment with Kubernetes manifests, health checks, and monitoring
- **Automatic Recovery**: Supervisor-based restart on camera or connection failures

## Quick Start

### Accessing the Stream

The video stream is available at:

```
rtsp://<drone-ip>:8554/video
```

Default configuration:
- **Resolution**: 1920x1080 (1080p)
- **Framerate**: 30 FPS
- **H.264 Profile**: Main Profile, Level 4.1
- **Port**: 8554

### Testing with VLC

```bash
vlc rtsp://10.10.10.2:8554/video
```

Or use VLC GUI: Media → Open Network Stream → Enter URL

### Testing with ffplay

```bash
ffplay -rtsp_transport tcp rtsp://10.10.10.2:8554/video
```

## Configuration

All configuration is done via environment variables for containerized deployments.

### Camera Settings

| Variable | Default | Description | Valid Values |
|----------|---------|-------------|--------------|
| `STREAM_WIDTH` | 1920 | Video width in pixels | 640-4056 (depends on camera) |
| `STREAM_HEIGHT` | 1080 | Video height in pixels | 480-3040 (depends on camera) |
| `STREAM_FPS` | 30 | Frames per second | 1-60 (depends on resolution) |
| `CAMERA_HFLIP` | false | Flip image horizontally | true/false |
| `CAMERA_VFLIP` | false | Flip image vertically | true/false |

**Common Resolutions (IMX477)**:
- 1920x1080 @ 30 FPS (default, recommended)
- 1280x720 @ 60 FPS (lower latency)
- 2028x1520 @ 40 FPS (higher quality)

### RTSP Server Settings

| Variable | Default | Description | Valid Values |
|----------|---------|-------------|--------------|
| `RTSP_PORT` | 8554 | RTSP server port | 1-65535 |
| `RTSP_PATH` | /video | Stream path | Any valid path |
| `RTSP_AUTH` | false | Enable authentication | true/false |
| `RTSP_USERNAME` | - | Username (if auth enabled) | String |
| `RTSP_PASSWORD` | - | Password (if auth enabled) | String |

### H.264 Encoder Settings

| Variable | Default | Description | Valid Values |
|----------|---------|-------------|--------------|
| `H264_PROFILE` | main | H.264 encoding profile | baseline/main/high |
| `H264_LEVEL` | 4.1 | H.264 encoding level | 3.1/4.0/4.1 |
| `KEYFRAME_INTERVAL` | 10 | Keyframes per GOP (frames) | 1-120 |
| `H264_BITRATE` | auto | Target bitrate in bits/sec | auto or integer (e.g., 2500000) |
| `H264_INLINE_HEADERS` | true | Insert SPS/PPS before keyframes | true/false |
| `H264_FLUSH` | true | Flush encoder output immediately | true/false |

**Profile Selection Guide**:
- **baseline**: Maximum compatibility, higher bandwidth
- **main**: Recommended - good compression, universal compatibility (~20% bandwidth savings vs baseline)
- **high**: Best compression, requires more client processing power

**Level Selection Guide**:
- **3.1**: Up to 720p30
- **4.0**: Up to 1080p30 (30 Mbps)
- **4.1**: Up to 1080p60 (50 Mbps)

### Latency Optimization

For lowest latency, configure:

```bash
KEYFRAME_INTERVAL=15  # More frequent keyframes (reduce to 10-15 for <300ms)
STREAM_FPS=30         # Higher FPS reduces latency
H264_PROFILE=baseline # Faster encoding
H264_INLINE_HEADERS=true # Ensure headers in stream
```

Trade-off: More frequent keyframes = higher bandwidth usage

### Android/Mobile Optimization

For best performance on Android devices (QGroundControl, ATAK):

```bash
KEYFRAME_INTERVAL=10      # Very frequent keyframes (333ms at 30fps) for low latency
H264_BITRATE=2500000      # 2.5 Mbps target for 720p (prevents spikes)
H264_INLINE_HEADERS=true  # Better mobile decoder compatibility
H264_FLUSH=true           # Flush encoder immediately (reduces buffering)
H264_PROFILE=main         # Good compression, universal support
```

Benefits:
- **Reduces latency**: 10-frame GOP = 333ms maximum latency contribution at 30fps, but average wait is 5 frames (~167ms)
- **Eliminates block artifacts**: Frequent keyframes prevent error propagation
- **Faster decoder recovery**: More I-frames = better error resilience
- **Immediate output**: Flush mode reduces encoder buffering
- **Stable performance**: Bitrate limiting prevents network congestion

**Latency Breakdown** (720p30 with these settings, using average values):
- Encoding: ~33ms (1 frame)
- Network: ~10-50ms (WiFi)
- Keyframe interval: ~167ms (average wait: 5 frames to next I-frame at 30fps; maximum possible: 333ms)
- **Total glass-to-glass**: ~210-250ms (average; optimal for Android)

### Example Configurations

**Low Latency (Sub-300ms)**:
```bash
STREAM_WIDTH=1280
STREAM_HEIGHT=720
STREAM_FPS=30
H264_PROFILE=baseline
H264_LEVEL=4.0
KEYFRAME_INTERVAL=15
```

**High Quality**:
```bash
STREAM_WIDTH=1920
STREAM_HEIGHT=1080
STREAM_FPS=30
H264_PROFILE=main
H264_LEVEL=4.1
KEYFRAME_INTERVAL=30
```

**Bandwidth Constrained**:
```bash
STREAM_WIDTH=1280
STREAM_HEIGHT=720
STREAM_FPS=15
H264_PROFILE=main
H264_LEVEL=3.1
KEYFRAME_INTERVAL=30
```

## Client Setup

### QGroundControl (Recommended)

QGroundControl automatically discovers video streams via MAVLink.

**Manual Configuration**:
1. Open QGroundControl
2. Go to Application Settings → General → Video
3. Set Video Source: "RTSP Video Stream"
4. Set RTSP URL: `rtsp://10.10.10.2:8554/video`
5. Enable "Automatically restore video" (optional)

**Note**: Using Main Profile (H.264 Level 4.0 or 4.1) is recommended for QGroundControl compatibility.

### VLC Media Player

**Desktop (Windows/Mac/Linux)**:
```bash
vlc rtsp://10.10.10.2:8554/video
```

**Command line options**:
```bash
# Lower latency settings
vlc --network-caching=100 --rtsp-tcp rtsp://10.10.10.2:8554/video

# Record while viewing
vlc rtsp://10.10.10.2:8554/video --sout file/ts:recording.ts
```

### ATAK (Android Team Awareness Kit)

1. In ATAK, tap the ⚙️ Settings icon
2. Navigate to Device Preferences → Video
3. Add new video source:
   - **Alias**: "UAV Camera"
   - **URL**: `rtsp://10.10.10.2:8554/video`
   - **Protocol**: RTSP
   - **Preferred Network**: Wi-Fi
4. Tap the video icon to start streaming

### GStreamer

For custom integrations:

```bash
gst-launch-1.0 rtspsrc location=rtsp://10.10.10.2:8554/video ! \
  rtph264depay ! h264parse ! avdec_h264 ! autovideosink
```

### FFmpeg/ffplay

```bash
# View stream
ffplay -rtsp_transport tcp -fflags nobuffer -flags low_delay \
  rtsp://10.10.10.2:8554/video

# Save to file
ffmpeg -rtsp_transport tcp -i rtsp://10.10.10.2:8554/video \
  -c copy output.mp4
```

## Architecture

The video streamer is built on the [Membrane Framework](https://membrane.stream), an Elixir multimedia processing library.

### High-Level Architecture

```
┌─────────────────┐
│  Raspberry Pi   │
│  Camera (CSI)   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  rpicam-vid     │  Hardware-accelerated H.264 encoding
│  (GPU encoding) │
└────────┬────────┘
         │ H.264 stream
         ▼
┌─────────────────┐
│ Membrane.Rpicam │
│    .Source      │  Elixir wrapper for camera
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  H.264 Parser   │  Parse NAL units, SPS/PPS
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  RTP Payloader  │  Package for network streaming
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Membrane.Tee   │  Dynamic multi-client branching
└────────┬────────┘
         │
         ├───────────────────┬───────────────────┐
         ▼                   ▼                   ▼
   ┌─────────┐         ┌─────────┐         ┌─────────┐
   │ Client 1│         │ Client 2│         │ Client 3│
   │  (QGC)  │         │  (VLC)  │         │ (ATAK)  │
   └─────────┘         └─────────┘         └─────────┘
```

### Key Components

- **VideoStreamer.Pipeline**: Main Membrane pipeline, manages camera → encoder → RTP chain
- **VideoStreamer.PipelineManager**: GenServer managing pipeline lifecycle, handles restarts
- **VideoStreamer.RTSP.Server**: TCP server handling RTSP protocol (DESCRIBE, SETUP, PLAY, TEARDOWN)
- **VideoStreamer.RTSP.SDP**: Generates Session Description Protocol messages with H.264 parameters
- **VideoStreamer.Telemetry**: Monitoring and metrics collection
- **Membrane.Rpicam.Source**: Custom camera source with retry logic and error handling

### Data Flow

1. **Camera Capture**: `rpicam-vid` captures from CSI camera, GPU encodes to H.264
2. **H.264 Parsing**: Extract NAL units, identify SPS/PPS for codec parameters
3. **RTP Packaging**: H.264 stream packaged into RTP packets (RFC 6184)
4. **Client Connection**: RTSP handshake (OPTIONS, DESCRIBE, SETUP, PLAY)
5. **Streaming**: RTP packets sent to client, dynamic branching for multiple clients
6. **Client Disconnect**: TEARDOWN command, pipeline branch cleanup

See [docs/architecture.md](docs/architecture.md) for detailed architecture documentation.

## Development

### Prerequisites

- Elixir 1.18+ with OTP 28+
- Raspberry Pi with Camera Module (IMX477 recommended, IMX219 supported)
- Docker (for containerized builds)

### Local Development Setup

```bash
# Clone repository
cd apps/video_streamer

# Install dependencies
mix deps.get

# Run tests
mix test

# Compile
mix compile

# Run locally (requires camera hardware)
iex -S mix
```

### Project Structure

```
apps/video_streamer/
├── lib/
│   ├── video_streamer/
│   │   ├── application.ex        # OTP application supervisor
│   │   ├── pipeline.ex            # Main Membrane pipeline
│   │   ├── pipeline_manager.ex   # Pipeline lifecycle management
│   │   ├── telemetry.ex           # Metrics and monitoring
│   │   └── rtsp/
│   │       ├── server.ex          # RTSP protocol server
│   │       ├── protocol.ex        # RTSP message parsing/building
│   │       └── sdp.ex             # SDP generation
│   ├── membrane_rpicam/
│   │   └── source.ex              # Camera source with error handling
│   └── video_streamer.ex          # Main module
├── test/                          # Unit tests
├── config/                        # Configuration files
├── Dockerfile                     # Multi-stage production build
└── README.md                      # This file
```

### Running Tests

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Run specific test file
mix test test/video_streamer/rtsp/protocol_test.exs
```

Tests run in a special mode where camera and RTSP server are not started, avoiding hardware dependencies.

### Building Docker Image

```bash
# Build for ARM64 (Raspberry Pi)
docker build -t video-streamer:latest .

# Build and tag
docker build -t ghcr.io/fancydrones/x500-cm4/video-streamer:$(date +%Y%m%d) .
```

### Deployment

The service is deployed to Kubernetes on the drone:

```bash
# Deploy to k3s
kubectl apply -f ../../deploy/k8s/video-streamer/

# Check status
kubectl get pods -l app=video-streamer

# View logs
kubectl logs -f deployment/video-streamer

# Port forward for local testing
kubectl port-forward service/video-streamer 8554:8554
```

See [docs/operations.md](docs/operations.md) for complete deployment procedures.

## Troubleshooting

### No Video Stream

**Symptoms**: Cannot connect to RTSP server, connection refused

**Solutions**:
1. Check service is running: `kubectl get pods -l app=video-streamer`
2. Check pod logs: `kubectl logs deployment/video-streamer`
3. Verify network connectivity: `ping 10.10.10.2`
4. Test RTSP port: `nc -zv 10.10.10.2 8554`
5. Check firewall rules

### Camera Not Found

**Symptoms**: Pod logs show "rpicam-vid: not found" or "camera failed to open"

**Solutions**:
1. Verify camera cable connection (CSI port)
2. Enable camera in `raspi-config`: Interface Options → Camera
3. Test camera: `rpicam-vid -t 5000 -o test.h264`
4. Check camera permissions in deployment manifest (`/dev/video*` devices)

### High Latency

**Symptoms**: Video delay >500ms

**Solutions**:
1. Reduce keyframe interval: `KEYFRAME_INTERVAL=15`
2. Use baseline profile: `H264_PROFILE=baseline`
3. Lower resolution: `STREAM_WIDTH=1280 STREAM_HEIGHT=720`
4. Check network latency: `ping 10.10.10.2`
5. Use TCP transport in client: `vlc --rtsp-tcp rtsp://...`

### Video Stuttering/Freezing

**Symptoms**: Video freezes, buffering issues

**Solutions**:
1. Check CPU usage: `kubectl top pod <pod-name>`
2. Reduce framerate: `STREAM_FPS=15`
3. Use lower resolution
4. Check network bandwidth: `iperf3 -c 10.10.10.2`
5. Increase keyframe interval: `KEYFRAME_INTERVAL=60`

### QGroundControl Not Showing Video

**Symptoms**: QGC video widget is black or shows "No Video"

**Solutions**:
1. Ensure using Main or High profile (not baseline for QGC)
2. Set H.264 level to 4.0 or higher: `H264_LEVEL=4.0`
3. Manually configure RTSP URL in QGC settings
4. Check QGC video settings: Application Settings → Video
5. Restart QGC after configuration changes

### Multiple Clients Not Working

**Symptoms**: Second client connection fails or first client drops

**Solutions**:
1. This should work automatically - check logs for errors
2. Verify dynamic Tee branching in logs
3. Check system resources: `kubectl top pod`
4. Each client needs sufficient bandwidth (estimate: resolution × fps × 0.1 bits)

### Pipeline Crashes/Restarts

**Symptoms**: Service restarts frequently, "pipeline crashed" in logs

**Solutions**:
1. Check camera connection and power
2. Review full logs: `kubectl logs deployment/video-streamer --tail=100`
3. Verify resource limits aren't being hit
4. Check for memory leaks: monitor memory usage over time
5. Review telemetry metrics for patterns

## FAQ

### What cameras are supported?

- **Raspberry Pi Camera Module v2** (IMX219) - 8MP, 1080p30
- **Raspberry Pi HQ Camera** (IMX477) - 12MP, 1080p60 (recommended)
- **Raspberry Pi Camera Module 3** (IMX708) - 12MP, should work but untested

Other CSI cameras may work if supported by `rpicam-apps`.

### What is the typical latency?

Glass-to-glass latency depends on configuration:
- **Optimized settings**: 250-350ms
- **Default settings (1080p30, main profile)**: 300-500ms
- **High quality settings**: 400-600ms

Network latency, client buffering, and keyframe interval are the main factors.

### How much bandwidth does it use?

Approximate bandwidth (varies with scene complexity):
- **720p @ 30fps, main profile**: 2-4 Mbps
- **1080p @ 30fps, main profile**: 4-8 Mbps
- **1080p @ 60fps, high profile**: 8-12 Mbps

Baseline profile typically uses 20-30% more bandwidth than main profile.

### Can I record the stream?

Yes, several options:

**VLC**:
```bash
vlc rtsp://10.10.10.2:8554/video --sout file/ts:recording.ts
```

**FFmpeg**:
```bash
ffmpeg -i rtsp://10.10.10.2:8554/video -c copy recording.mp4
```

**QGroundControl**: Has built-in recording in video settings.

### How many simultaneous clients are supported?

The service supports multiple simultaneous clients using dynamic pipeline branching. Tested with:
- ✅ 3+ simultaneous clients (QGC + VLC + ATAK)
- Limited primarily by network bandwidth and system resources
- Each client receives an independent RTP stream

### Why use Main profile instead of Baseline?

Main Profile provides ~20% better compression (lower bandwidth) with minimal additional encoding overhead. It's supported by all modern clients including QGroundControl, VLC, and ATAK. Baseline is only needed for very old or embedded clients.

### Can I use this without a drone/QGroundControl?

Yes! The video streamer is a standalone RTSP/RTP server. You can:
- Use it with any RTSP client (VLC, ffplay, etc.)
- Integrate with custom applications
- Use for general Raspberry Pi camera streaming projects

### How do I change camera orientation?

Use the flip environment variables:

```bash
# Flip horizontally (mirror)
CAMERA_HFLIP=true

# Flip vertically (upside down)
CAMERA_VFLIP=true

# Both
CAMERA_HFLIP=true
CAMERA_VFLIP=true
```

Update the deployment manifest and restart the pod.

### What happens if the camera disconnects?

The service includes automatic retry logic:
- Camera failures trigger automatic restart (3 retries with exponential backoff)
- If retries exhausted, the pod crashes and Kubernetes restarts it
- Clients will need to reconnect after service restart

### Can I enable authentication?

Yes, basic authentication is supported:

```bash
RTSP_AUTH=true
RTSP_USERNAME=admin
RTSP_PASSWORD=secure_password
```

Then connect with: `rtsp://admin:secure_password@10.10.10.2:8554/video`

**Note**: Credentials are sent over the network. Use HTTPS tunneling for production security.

## Additional Documentation

- [Architecture Details](docs/architecture.md) - Deep dive into system design
- [Operations Guide](docs/operations.md) - Deployment, monitoring, maintenance
- [Development Guide](docs/development.md) - Contributing, code style, testing
- [Phase 5 Testing Guide](../../PRDs/002-video-streamer/phase5-testing-guide.md) - Performance testing procedures
- [Implementation Plan](../../PRDs/002-video-streamer/implementation_plan.md) - Complete PRD with specs

## License

Copyright © 2025 FancyDrones. All rights reserved.
