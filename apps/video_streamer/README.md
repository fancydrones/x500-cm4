# Video Streamer Service

Low-latency RTSP video streaming service for x500-cm4 UAV platform.

## Features

- Hardware-accelerated H.264 encoding (Raspberry Pi GPU)
- RTSP/RTP streaming protocol (Phase 2)
- Configurable resolution and framerate
- Multi-client support (Phase 3)
- Sub-500ms latency target
- Automatic restart on failure

## Implementation Status

### Phase 1: Project Setup & Basic Pipeline ✅ COMPLETE

- [x] Create new Elixir application
- [x] Add Membrane dependencies
- [x] Create configuration files (config.exs, dev.exs, test.exs, prod.exs, runtime.exs)
- [x] Implement VideoStreamer.Pipeline module
- [x] Implement VideoStreamer.PipelineManager GenServer
- [x] Implement VideoStreamer.Application supervisor
- [x] Implement VideoStreamer.Telemetry module
- [x] Dependencies resolved and compilation successful

### Next Steps

- Phase 2: RTSP Server Implementation
- Phase 3: RTP Integration & Pipeline Connection
- Phase 4: Container & Deployment
- Phase 5: Testing & Optimization
- Phase 6: Documentation & Deployment Guide

## Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `STREAM_WIDTH` | 1920 | Video width in pixels |
| `STREAM_HEIGHT` | 1080 | Video height in pixels |
| `STREAM_FPS` | 30 | Frames per second |
| `RTSP_PORT` | 8554 | RTSP server port |
| `RTSP_PATH` | /video | Stream path |
| `H264_PROFILE` | baseline | H.264 profile (baseline/main/high) |
| `KEYFRAME_INTERVAL` | 30 | Keyframes per GOP (frames) |

## Development

### Local testing

```bash
cd apps/video_streamer
mix deps.get
mix test
mix compile
```

### Running locally (requires Raspberry Pi camera)

```bash
iex -S mix
```

## Architecture

The video streamer uses the Membrane multimedia framework to build a processing pipeline:

```
Camera → H.264 Parser → RTP Payloader → RTSP Server → Clients
```

### Main Components

- **VideoStreamer.Pipeline**: Main Membrane pipeline that captures video from the Raspberry Pi camera
- **VideoStreamer.PipelineManager**: GenServer that manages pipeline lifecycle (start/stop/restart)
- **VideoStreamer.Application**: OTP application supervisor
- **VideoStreamer.Telemetry**: Telemetry setup for monitoring performance

## Documentation

See [PRD 002 Implementation Plan](../../PRDs/002-video-streamer/implementation_plan.md) for detailed implementation specifications.

