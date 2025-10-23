# Video Streamer Architecture

This document provides a detailed architectural overview of the video streaming service for the x500-cm4 UAV platform.

## Table of Contents

- [Overview](#overview)
- [System Architecture](#system-architecture)
- [Component Details](#component-details)
- [Pipeline Flow](#pipeline-flow)
- [RTSP Protocol Flow](#rtsp-protocol-flow)
- [RTP Packet Flow](#rtp-packet-flow)
- [Multi-Client Architecture](#multi-client-architecture)
- [Error Handling & Recovery](#error-handling--recovery)
- [Performance Considerations](#performance-considerations)

## Overview

The video streamer is built using the [Membrane Framework](https://membrane.stream), a multimedia processing framework for Elixir. It leverages:

- **Hardware acceleration**: Raspberry Pi GPU encoding via `rpicam-apps`
- **OTP supervision**: Fault-tolerant process supervision
- **Functional programming**: Immutable data structures, pattern matching
- **Actor model**: Message-passing between independent processes

### Design Goals

1. **Low Latency**: Sub-500ms glass-to-glass latency for real-time UAV operations
2. **Reliability**: Automatic recovery from camera/network failures
3. **Scalability**: Support multiple simultaneous clients
4. **Maintainability**: Clean separation of concerns, testable components
5. **Performance**: Efficient resource usage on embedded hardware

## System Architecture

### High-Level Component Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          OTP Application                                 │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                   VideoStreamer.Supervisor                        │  │
│  │  (strategy: one_for_one)                                          │  │
│  └────┬─────────────────────┬───────────────────────┬───────────────┘  │
│       │                     │                       │                   │
│       ▼                     ▼                       ▼                   │
│  ┌─────────┐         ┌─────────────┐       ┌──────────────────┐       │
│  │Telemetry│         │ RTSP Server │       │ PipelineManager  │       │
│  │Supervisor│        │  (GenServer)│       │   (GenServer)    │       │
│  └─────────┘         └──────┬──────┘       └────────┬─────────┘       │
│                              │                       │                  │
└──────────────────────────────┼───────────────────────┼─────────────────┘
                               │                       │
                               │                       ▼
                               │              ┌─────────────────┐
                               │              │ Membrane        │
                               │              │ Pipeline        │
                               │              │ (Bin Supervisor)│
                               │              └────────┬────────┘
                               │                       │
                               ▼                       ▼
                        ┌──────────────┐    ┌──────────────────┐
                        │ TCP Socket   │    │  Camera Source   │
                        │ (Ranch)      │    │  H.264 Parser    │
                        │              │    │  RTP Payloader   │
                        │ Client Conn  │    │  Tee (multi-out) │
                        └──────────────┘    └──────────────────┘
```

### Process Hierarchy

```
VideoStreamer.Application (Supervisor)
├── VideoStreamer.Telemetry (Supervisor)
│   ├── Telemetry.Metrics
│   └── Telemetry.Poller
├── VideoStreamer.RTSP.Server (GenServer)
│   └── Ranch (TCP acceptor pool)
│       ├── Client Connection 1
│       ├── Client Connection 2
│       └── Client Connection N
└── VideoStreamer.PipelineManager (GenServer)
    └── VideoStreamer.Pipeline (Membrane.Pipeline)
        ├── Membrane.Rpicam.Source
        ├── Membrane.H26x.Parser
        ├── Membrane.RTP.H264.Payloader
        └── Membrane.Tee
            ├── Branch 1 (UDP sink to Client 1)
            ├── Branch 2 (UDP sink to Client 2)
            └── Branch N (UDP sink to Client N)
```

## Component Details

### VideoStreamer.Application

**Type**: OTP Application Supervisor
**File**: `lib/video_streamer/application.ex`

**Responsibilities**:
- Start and supervise top-level processes
- Handle application lifecycle (start/stop)
- Configure supervision strategy (one-for-one)

**Children**:
1. `VideoStreamer.Telemetry` - Metrics collection
2. `VideoStreamer.RTSP.Server` - RTSP protocol handler
3. `VideoStreamer.PipelineManager` - Pipeline lifecycle management

**Supervision Strategy**: `:one_for_one`
- If one child crashes, only that child is restarted
- Other children continue running
- Suitable for independent services

### VideoStreamer.PipelineManager

**Type**: GenServer
**File**: `lib/video_streamer/pipeline_manager.ex`

**Responsibilities**:
- Manage Membrane pipeline lifecycle
- Handle pipeline crashes and restarts
- Coordinate client connections with pipeline state
- Aggregate telemetry data

**State**:
```elixir
%{
  pipeline_pid: pid() | nil,
  restart_count: integer(),
  last_restart: DateTime.t() | nil,
  config: map()
}
```

**API**:
- `start_link/1` - Start the manager
- `get_pipeline_pid/0` - Get current pipeline PID
- `restart_pipeline/0` - Manually restart pipeline
- `add_client/1` - Register new client connection
- `remove_client/1` - Unregister client

**Restart Logic**:
- Exponential backoff on repeated failures
- Maximum 5 restarts per minute
- Logs restart events for monitoring

### VideoStreamer.Pipeline

**Type**: Membrane.Pipeline
**File**: `lib/video_streamer/pipeline.ex`

**Responsibilities**:
- Define multimedia processing graph
- Link Membrane elements
- Handle dynamic client connections
- Manage element lifecycle

**Pipeline Structure**:
```elixir
camera_source
|> child(:parser, Membrane.H26x.Parser)
|> child(:payloader, Membrane.RTP.H264.Payloader)
|> child(:tee, Membrane.Tee.Parallel)
```

**Dynamic Tee Branching**:
- New clients trigger `add_child` for UDP sink
- Clients get unique pad ID (`:output_N`)
- Disconnection removes branch dynamically

### VideoStreamer.RTSP.Server

**Type**: GenServer + Ranch TCP Acceptor
**File**: `lib/video_streamer/rtsp/server.ex`

**Responsibilities**:
- Accept RTSP TCP connections
- Parse RTSP requests
- Generate RTSP responses
- Coordinate RTP session setup
- Track active sessions

**RTSP Methods Supported**:
- `OPTIONS` - Query supported methods
- `DESCRIBE` - Get SDP description
- `SETUP` - Establish RTP transport
- `PLAY` - Start streaming
- `TEARDOWN` - End session

**Session State**:
```elixir
%{
  session_id: String.t(),
  client_ip: :inet.ip_address(),
  client_port: integer(),
  transport: :udp | :tcp,
  state: :init | :ready | :playing
}
```

### VideoStreamer.RTSP.Protocol

**Type**: Module (stateless functions)
**File**: `lib/video_streamer/rtsp/protocol.ex`

**Responsibilities**:
- Parse RTSP request messages
- Build RTSP response messages
- Serialize responses to wire format
- Extract headers (CSeq, Session, etc.)

**Key Functions**:
```elixir
@spec parse_request(binary()) :: {:ok, request()} | {:error, term()}
@spec build_options_response(cseq()) :: response()
@spec build_describe_response(cseq(), sdp()) :: response()
@spec build_setup_response(cseq(), session_id(), transport()) :: response()
@spec build_play_response(cseq(), session_id()) :: response()
@spec serialize_response(response()) :: binary()
```

### VideoStreamer.RTSP.SDP

**Type**: Module (SDP generation)
**File**: `lib/video_streamer/rtsp/sdp.ex`

**Responsibilities**:
- Generate RFC 4566 compliant SDP
- Include H.264 codec parameters (RFC 6184)
- Extract SPS/PPS from stream
- Build fmtp lines with profile-level-id

**SDP Structure**:
```
v=0                                    # Version
o=- <session-id> <version> IN IP4 <ip> # Origin
s=VideoStreamer H.264 Stream           # Session name
c=IN IP4 <ip>                          # Connection info
t=0 0                                  # Time (unlimited)
a=control:*                            # Aggregate control
a=range:npt=0-                         # Range (live)
m=video 0 RTP/AVP 96                   # Media description
a=rtpmap:96 H264/90000                 # RTP mapping
a=fmtp:96 <h264-params>                # Format parameters
a=control:<path>/trackID=0             # Media control
```

### Membrane.Rpicam.Source

**Type**: Membrane.Source
**File**: `lib/membrane_rpicam/source.ex`

**Responsibilities**:
- Spawn `rpicam-vid` process
- Capture H.264 encoded stream
- Handle camera failures with retry logic
- Convert raw bytes to Membrane buffers

**Error Handling**:
- Retry camera open failures (3 attempts)
- Exponential backoff between retries
- Emit error events to pipeline
- Graceful shutdown on persistent failures

**Port Communication**:
```elixir
Port.open(
  {:spawn, "rpicam-vid -t 0 --codec h264 --profile main ..."},
  [:binary, :exit_status, {:env, [{'LIBCAMERA_LOG_LEVELS', '*:3'}]}]
)
```

## Pipeline Flow

### Initialization Sequence

```
1. Application.start
   └─> VideoStreamer.Application.start/2
       ├─> Start Telemetry Supervisor
       ├─> Start RTSP.Server (listen on port 8554)
       └─> Start PipelineManager
           └─> Start VideoStreamer.Pipeline
               ├─> Initialize camera source
               ├─> Link H.264 parser
               ├─> Link RTP payloader
               └─> Initialize Tee (no outputs yet)
```

### Data Flow (Active Streaming)

```
┌──────────────┐
│ RPi Camera   │ CSI Bus
│ (IMX477)     │
└──────┬───────┘
       │ RAW sensor data
       ▼
┌──────────────┐
│ rpicam-vid   │ GPU encoding
│ (H.264)      │
└──────┬───────┘
       │ H.264 NAL units (stdout)
       ▼
┌──────────────┐
│ Rpicam.Source│ Erlang Port
│              │
└──────┬───────┘
       │ Membrane.Buffer{payload: <<NAL unit>>}
       ▼
┌──────────────┐
│ H26x.Parser  │ Parse NAL types
│              │ Extract SPS/PPS
└──────┬───────┘
       │ Membrane.Buffer{metadata: %{type: :idr/:non_idr}}
       ▼
┌──────────────┐
│ RTP.H264     │ RFC 6184 packaging
│ .Payloader   │ MTU segmentation (1200 bytes)
└──────┬───────┘
       │ RTP packets
       ▼
┌──────────────┐
│ Tee.Parallel │ Dynamic branching
│              │
└──────┬───────┘
       │
       ├─────────────────┬─────────────────┐
       ▼                 ▼                 ▼
┌──────────┐      ┌──────────┐      ┌──────────┐
│ UDP Sink │      │ UDP Sink │      │ UDP Sink │
│ (QGC)    │      │ (VLC)    │      │ (ATAK)   │
└──────────┘      └──────────┘      └──────────┘
```

### Buffer Format

**After Camera Source**:
```elixir
%Membrane.Buffer{
  payload: <<H.264 NAL unit bytes>>,
  pts: timestamp_ns,
  metadata: %{}
}
```

**After H.264 Parser**:
```elixir
%Membrane.Buffer{
  payload: <<NAL unit>>,
  pts: timestamp_ns,
  metadata: %{
    type: :idr | :non_idr | :sps | :pps,
    h264: %{
      new_access_unit: boolean(),
      key_frame?: boolean()
    }
  }
}
```

**After RTP Payloader**:
```elixir
%Membrane.Buffer{
  payload: <<RTP packet (header + payload)>>,
  pts: timestamp_ns,
  metadata: %{
    rtp: %{
      marker: boolean(),
      sequence_number: integer(),
      timestamp: integer(),
      ssrc: integer()
    }
  }
}
```

## RTSP Protocol Flow

### Client Connection Sequence

```
Client                          Server
  │                               │
  │─────── TCP Connect ──────────>│
  │<───── TCP Accept ─────────────│
  │                               │
  │─────── OPTIONS * ────────────>│
  │<───── 200 OK ─────────────────│
  │       Public: OPTIONS, DESCRIBE, SETUP, PLAY, TEARDOWN
  │                               │
  │─────── DESCRIBE /video ──────>│
  │<───── 200 OK ─────────────────│
  │       Content-Type: application/sdp
  │       [SDP body with H.264 parameters]
  │                               │
  │─────── SETUP trackID=0 ──────>│
  │       Transport: RTP/AVP;unicast;client_port=50000-50001
  │<───── 200 OK ─────────────────│
  │       Session: 12345678
  │       Transport: RTP/AVP;unicast;client_port=50000-50001;server_port=50002-50003
  │                               │
  │─────── PLAY /video ──────────>│
  │       Session: 12345678
  │<───── 200 OK ─────────────────│
  │       RTP-Info: url=/video/trackID=0;seq=1;rtptime=0
  │                               │
  │<═══════ RTP Packets ══════════│ (UDP stream)
  │<═══════ RTP Packets ══════════│
  │<═══════ RTP Packets ══════════│
  │                               │
  │─────── TEARDOWN /video ──────>│
  │       Session: 12345678
  │<───── 200 OK ─────────────────│
  │                               │
  │───── TCP Close ───────────────│
```

### RTSP Request Format

```
<METHOD> <URI> RTSP/1.0\r\n
CSeq: <sequence-number>\r\n
[Additional headers]\r\n
\r\n
[Optional body]
```

Example:
```
DESCRIBE rtsp://10.10.10.2:8554/video RTSP/1.0\r\n
CSeq: 2\r\n
Accept: application/sdp\r\n
\r\n
```

### RTSP Response Format

```
RTSP/1.0 <status-code> <reason>\r\n
CSeq: <sequence-number>\r\n
[Additional headers]\r\n
\r\n
[Optional body]
```

Example:
```
RTSP/1.0 200 OK\r\n
CSeq: 2\r\n
Content-Type: application/sdp\r\n
Content-Length: 456\r\n
\r\n
v=0\r\n
o=- 1234567890 1234567890 IN IP4 10.10.10.2\r\n
...
```

## RTP Packet Flow

### RTP Packet Structure

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|V=2|P|X|  CC   |M|     PT      |       Sequence Number         |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                           Timestamp                           |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                             SSRC                              |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                         RTP Payload ...                       |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

**Header Fields**:
- **V (Version)**: 2
- **P (Padding)**: 0
- **X (Extension)**: 0
- **CC (CSRC Count)**: 0
- **M (Marker)**: 1 for last packet of frame
- **PT (Payload Type)**: 96 (dynamic, H.264)
- **Sequence Number**: Incremented for each packet
- **Timestamp**: 90kHz clock (90000 / fps)
- **SSRC**: Synchronization source identifier

### H.264 RTP Payload (RFC 6184)

**Single NAL Unit Packet** (NAL < MTU):
```
+-+-+-+-+-+-+-+-+
|F|NRI|  Type   |  NAL Header
+-+-+-+-+-+-+-+-+
|               |
|   NAL Unit    |
|     Data      |
|               |
+-+-+-+-+-+-+-+-+
```

**Fragmentation Unit (FU-A)** (NAL > MTU):
```
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|F|NRI|  Type=28  | S|E|R| Type |  FU Indicator + FU Header
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                               |
|       Fragment Data           |
|                               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

- **S (Start)**: 1 for first fragment
- **E (End)**: 1 for last fragment
- **R (Reserved)**: 0

### Packetization Example

**1080p30 H.264 Stream**:
- Framerate: 30 FPS
- Keyframe interval: 30 frames (1 GOP/second)
- Average frame size: ~50 KB (keyframe), ~10 KB (P-frame)
- MTU: 1200 bytes (safe for most networks)

**Keyframe Packetization**:
```
NAL Unit: 50,000 bytes (IDR frame)
RTP Packets: 50000 / (1200 - 12 - 2) ≈ 43 packets
  Packet 1: FU-A (S=1, E=0) + 1186 bytes
  Packet 2: FU-A (S=0, E=0) + 1186 bytes
  ...
  Packet 43: FU-A (S=0, E=1) + 1186 bytes (M=1)
```

**P-Frame Packetization**:
```
NAL Unit: 10,000 bytes (P frame)
RTP Packets: 10000 / 1186 ≈ 9 packets
```

**Packets Per Second**:
- Keyframes: 1 × 43 packets = 43 packets/second
- P-frames: 29 × 9 packets = 261 packets/second
- **Total: ~304 packets/second**

## Multi-Client Architecture

### Dynamic Tee Branching

The Membrane.Tee element provides dynamic output branching:

```elixir
# Initial pipeline (no clients)
camera -> parser -> payloader -> tee

# Client 1 connects
tee -> udp_sink_1 (10.0.0.5:50000)

# Client 2 connects
tee -> udp_sink_1 (10.0.0.5:50000)
    \-> udp_sink_2 (10.0.0.8:50000)

# Client 3 connects
tee -> udp_sink_1
    \-> udp_sink_2
    \-> udp_sink_3 (10.0.0.12:50000)
```

### Adding Client (Message Flow)

```
1. Client sends PLAY request to RTSP.Server
   │
   ▼
2. RTSP.Server sends message to PipelineManager
   PipelineManager.add_client(%{
     ip: {10, 0, 0, 5},
     port: 50000,
     session_id: "12345678"
   })
   │
   ▼
3. PipelineManager sends message to Pipeline
   Pipeline.handle_info({:add_client, client_info}, state)
   │
   ▼
4. Pipeline adds child dynamically
   Membrane.Pipeline.add_child(
     :udp_sink_client_12345678,
     %Membrane.UDP.Sink{
       destination_address: {10, 0, 0, 5},
       destination_port: 50000
     }
   )
   │
   ▼
5. Pipeline links Tee to new sink
   Membrane.Pipeline.link(:tee, :udp_sink_client_12345678)
   │
   ▼
6. RTP packets start flowing to new client
```

### Removing Client (Cleanup)

```
1. Client sends TEARDOWN or disconnects
   │
   ▼
2. RTSP.Server notifies PipelineManager
   PipelineManager.remove_client(session_id)
   │
   ▼
3. Pipeline removes child
   Membrane.Pipeline.remove_child(:udp_sink_client_12345678)
   │
   ▼
4. Tee automatically handles output removal
   (other clients continue unaffected)
```

## Error Handling & Recovery

### Supervision Tree Strategy

```
VideoStreamer.Supervisor (one_for_one)
├── Telemetry (one_for_one)
│   └── If crashes: Restart independently, minor impact
├── RTSP.Server (one_for_one)
│   └── If crashes: New clients can't connect, existing streams continue
└── PipelineManager (one_for_one)
    └── If crashes: All streaming stops, clients disconnect
        └── Pipeline (auto-restart by manager)
            └── If crashes: Manager restarts with backoff
```

### Camera Failure Handling

**Failure Scenarios**:
1. Camera not detected at startup
2. Camera disconnects during streaming
3. rpicam-vid process crashes

**Recovery**:
```
Camera Source (Membrane.Rpicam.Source)
├── handle_info({:EXIT, port}, state)
│   ├── Retry 1: Immediate retry
│   ├── Retry 2: 1 second delay
│   └── Retry 3: 2 second delay
│       └── If all fail: Raise error to Pipeline
│
Pipeline receives error
└── Crashes and supervisor restarts entire pipeline
    └── PipelineManager tracks restart count
        └── If >5 restarts/minute: Alert and longer backoff
```

### Network Failure Handling

**Client Disconnection**:
- UDP is connection-less, so no direct disconnect notification
- RTSP TEARDOWN explicitly ends session
- Timeout mechanism for inactive sessions (future enhancement)

**Server Network Issues**:
- RTSP.Server crash: Supervisor restarts, clients reconnect
- UDP sink failure: Individual client affected, others continue

## Performance Considerations

### Latency Sources

Total latency = Capture + Encode + Parse + Packetize + Network + Decode + Display

**Breakdown**:
1. **Capture**: ~16ms (60fps) to ~33ms (30fps)
2. **GPU Encoding**: ~20-50ms (hardware accelerated)
3. **Parse + Packetize**: <5ms (in-memory processing)
4. **Network**: ~10-50ms (LAN), ~50-200ms (WiFi)
5. **Client Decode + Display**: ~50-100ms

**Optimization Targets**:
- Use 30fps or 60fps (lower capture latency)
- Baseline profile (faster encoding)
- Low keyframe interval (faster resync)
- Wired Ethernet (lower network jitter)

### Resource Usage

**Expected Resource Consumption** (Raspberry Pi 4, 1080p30):
- **CPU**: 30-50% (rpicam-vid encoding + Elixir processing)
- **Memory**: ~150MB (application + dependencies)
- **Network**: 4-8 Mbps (main profile)
- **GPU**: 70-90% (H.264 encoding)

**Scaling Considerations**:
- Each additional client: +~5MB memory (pipeline branch)
- Network bandwidth multiplied by client count (unicast)
- CPU impact minimal (Tee just copies buffers)

### Throughput Limits

**Theoretical Maximum**:
- 100 Mbps Ethernet / 8 Mbps per client ≈ 12 simultaneous clients
- Practical limit: 3-5 clients (system resources, network overhead)

**Bottlenecks**:
1. **Network bandwidth** (primary)
2. **GPU encoding** (fixed, not affected by client count)
3. **Memory** (each client branch allocates buffers)
4. **Erlang scheduler** (unlikely bottleneck for video streaming)

---

For operational details, see [operations.md](operations.md).
For development guidelines, see [development.md](development.md).
