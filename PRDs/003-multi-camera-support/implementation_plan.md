# Implementation Plan: Multi-Camera RTSP Streaming Support

## Executive Summary

This document outlines the implementation plan for extending the video streaming service (PRD-002) to support multiple cameras on a single host. Each camera will be accessible via separate RTSP paths on the same port, with external service announcement integration.

## Project Context

### Overview
- **Prerequisite:** PRD-002 (Low-Latency RTSP Video Streaming) must be completed
- **Platform:** Raspberry Pi CM5 with multiple cameras
- **Deployment:** K3s cluster on companion computer
- **Software Stack:** Elixir + Membrane Framework (extending existing video_streamer app)
- **Protocol:** RTSP/RTP over UDP (with TCP fallback)
- **Codec:** H.264 Main Profile
- **Integration:** External service announcement (announcer_ex from PRD-001)

### Key Design Principles
1. **Build on PRD-002:** Extend existing single-camera architecture
2. **Path-Based Routing:** Each camera accessible on unique RTSP path (e.g., `/camera/front`, `/camera/bottom`)
3. **Single Port:** All cameras served on same RTSP port (8554)
4. **Resource Isolation:** Each camera has independent pipeline
5. **Configuration-Driven:** Camera definitions via environment/config
6. **Service Discovery:** Integration with announcer_ex for MAVLink camera component announcement

## Dependency on PRD-002

**IMPORTANT:** This PRD builds directly on PRD-002. The following must be completed first:

- ✅ Phase 1: Basic RTSP streaming infrastructure
- ✅ Phase 2: RTP packetization and streaming
- ✅ Phase 3: Multi-client support per camera
- ⏳ Phase 4: Service integration and configuration (required before PRD-003)

**Rationale:** PRD-003 extends the single-camera architecture with multi-camera routing and management. The complete single-camera implementation provides the foundation for replication and path-based routing.

## Architecture Overview

### High-Level Multi-Camera Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    RTSP Server (Port 8554)                  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐ │
│  │           Path Router / Session Manager               │ │
│  │  - /camera/front  → Camera Pipeline 1                │ │
│  │  - /camera/bottom → Camera Pipeline 2                │ │
│  │  - /camera/rear   → Camera Pipeline 3                │ │
│  └──────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ Camera Pipeline │  │ Camera Pipeline │  │ Camera Pipeline │
│   "front"       │  │   "bottom"      │  │   "rear"        │
│                 │  │                 │  │                 │
│ ┌─────────────┐ │  │ ┌─────────────┐ │  │ ┌─────────────┐ │
│ │ RPi Camera  │ │  │ │ RPi Camera  │ │  │ │ RPi Camera  │ │
│ │ Source      │ │  │ │ Source      │ │  │ │ Source      │ │
│ └──────┬──────┘ │  │ └──────┬──────┘ │  │ └──────┬──────┘ │
│        │        │  │        │        │  │        │        │
│        ▼        │  │        ▼        │  │        ▼        │
│ ┌─────────────┐ │  │ ┌─────────────┐ │  │ ┌─────────────┐ │
│ │ H.264       │ │  │ │ H.264       │ │  │ │ H.264       │ │
│ │ Parser      │ │  │ │ Parser      │ │  │ │ Parser      │ │
│ └──────┬──────┘ │  │ └──────┬──────┘ │  │ └──────┬──────┘ │
│        │        │  │        │        │  │        │        │
│        ▼        │  │        ▼        │  │        ▼        │
│ ┌─────────────┐ │  │ ┌─────────────┐ │  │ ┌─────────────┐ │
│ │ Tee.Parallel│ │  │ │ Tee.Parallel│ │  │ │ Tee.Parallel│ │
│ │ (Multi-     │ │  │ │ (Multi-     │ │  │ │ (Multi-     │ │
│ │  Client)    │ │  │ │  Client)    │ │  │ │  Client)    │ │
│ └─────────────┘ │  │ └─────────────┘ │  │ └─────────────┘ │
└─────────────────┘  └─────────────────┘  └─────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
   RTP Streams          RTP Streams          RTP Streams
   to Clients           to Clients           to Clients
```

### Integration with Announcer Service

```
┌─────────────────────────────────────────────────────────────┐
│                  Announcer Service (announcer_ex)           │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │ Camera Comp  │  │ Camera Comp  │  │ Camera Comp  │     │
│  │ ID: 100      │  │ ID: 101      │  │ ID: 102      │     │
│  │ Name: Front  │  │ Name: Bottom │  │ Name: Rear   │     │
│  │ URL: rtsp:// │  │ URL: rtsp:// │  │ URL: rtsp:// │     │
│  │   .../front  │  │   .../bottom │  │   .../rear   │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
                  MAVLink Network
                  (QGroundControl, ATAK)
```

## Implementation Phases

### Phase 1: Multi-Pipeline Management

**Goal:** Extend PipelineManager to support multiple camera pipelines

**Tasks:**
1. Refactor `PipelineManager` to manage multiple pipelines
   - Convert from single pipeline to map of `camera_id -> pipeline_pid`
   - Add camera registry for path-based lookup
2. Create `CameraConfig` struct for camera definitions
   - Camera ID (unique identifier)
   - Camera name (human-readable)
   - Device path or camera index
   - RTSP path (e.g., `/camera/front`)
   - Resolution, framerate, codec settings
3. Update pipeline initialization
   - Start multiple pipelines based on configuration
   - Each pipeline isolated with own supervision tree
4. Add dynamic camera addition/removal support

**Deliverables:**
- Updated `lib/video_streamer/pipeline_manager.ex`
- New `lib/video_streamer/camera_config.ex`
- Configuration schema for multi-camera setup

### Phase 2: RTSP Path Routing

**Goal:** Extend RTSP server to route requests based on path

**Tasks:**
1. Update RTSP request handler
   - Parse RTSP URL path from DESCRIBE/SETUP requests
   - Route to appropriate camera pipeline based on path
2. Extend session management
   - Track camera_id per RTSP session
   - Ensure clients connect to correct camera pipeline
3. Update SDP generation
   - Generate camera-specific SDP
   - Include correct camera resolution/framerate per camera
4. Path validation and error handling
   - Return 404 for unknown camera paths
   - Clear error messages for misconfigurations

**Deliverables:**
- Updated `lib/video_streamer/rtsp/server.ex`
- Updated `lib/video_streamer/rtsp/session.ex`
- Path-aware SDP generation in `lib/video_streamer/rtsp/sdp.ex`

### Phase 3: Resource Management

**Goal:** Ensure efficient resource usage with multiple cameras

**Tasks:**
1. Pipeline lifecycle management
   - Lazy pipeline startup (on first client connection)
   - Pipeline shutdown on idle timeout
   - Graceful handling of camera device failures
2. Memory and CPU monitoring
   - Track per-camera resource usage
   - Implement backpressure mechanisms
   - Optional: Quality degradation under load
3. Camera device conflict resolution
   - Exclusive camera access per pipeline
   - Clear error messages on device conflicts
4. Testing with multiple simultaneous streams
   - Stress testing with multiple clients per camera
   - Resource usage profiling

**Deliverables:**
- Resource monitoring in `PipelineManager`
- Idle timeout configuration
- Performance benchmarks document

### Phase 4: Configuration and Deployment

**Goal:** Production-ready configuration and deployment

**Tasks:**
1. Environment-based configuration
   - Camera definitions via config/runtime.exs
   - Support for JSON camera config file
2. Docker/K8s configuration
   - Multi-camera deployment manifests
   - ConfigMap for camera definitions
   - Device mounting for multiple cameras
3. Integration with announcer_ex
   - Update announcer to read multi-camera config
   - Create MAVLink camera component per camera
   - Announce each camera with correct RTSP URL
4. Documentation
   - Multi-camera setup guide
   - Configuration examples
   - Troubleshooting guide

**Deliverables:**
- Configuration schemas and examples
- K8s deployment manifests
- Integration documentation

## Technical Considerations

### Camera Device Access

**Physical Cameras:**
- Raspberry Pi supports multiple cameras via:
  - CSI-2 camera ports (CM5 typically has 2 ports)
  - USB cameras (additional cameras)
- Camera selection via `rpicam-vid` with camera index parameter
- Need to verify camera device availability on target hardware

**Device Path Mapping:**
```elixir
# Example camera config
cameras = [
  %{
    id: "front",
    name: "Front Camera",
    device: 0,  # CSI-2 camera 0
    path: "/camera/front",
    width: 1280,
    height: 720,
    framerate: 30
  },
  %{
    id: "bottom",
    name: "Bottom Camera",
    device: 1,  # CSI-2 camera 1
    path: "/camera/bottom",
    width: 1280,
    height: 720,
    framerate: 30
  }
]
```

### RTSP Path Format

**Standard Format:**
```
rtsp://<host>:<port>/camera/<camera_id>
```

**Examples:**
- `rtsp://10.5.0.26:8554/camera/front`
- `rtsp://10.5.0.26:8554/camera/bottom`
- `rtsp://10.5.0.26:8554/camera/rear`

**Backward Compatibility:**
- Consider supporting legacy path `/video` for single-camera systems
- Could redirect `/video` to first configured camera

### Resource Constraints

**Considerations:**
- Each camera pipeline consumes:
  - CPU for H.264 encoding (hardware accelerated, but still has overhead)
  - Memory for buffers and RTP packets
  - Network bandwidth
- CM5 resource limits:
  - Need to benchmark max simultaneous cameras
  - May need quality/framerate limits per camera
  - Consider camera activation policies (active vs. on-demand)

### Service Announcement Integration

**Announcer Updates:**
- Announcer service reads same camera config
- Creates one MAVLink camera component per camera
- Each component gets unique component ID (100, 101, 102, etc.)
- Each announces correct RTSP URL with path

**MAVLink Component IDs:**
```elixir
# Example component mapping
cameras = [
  %{id: "front", component_id: 100, ...},
  %{id: "bottom", component_id: 101, ...},
  %{id: "rear", component_id: 102, ...}
]
```

## Success Criteria

### Functional Requirements
- ✅ Multiple cameras accessible via different RTSP paths
- ✅ All cameras served on single RTSP port (8554)
- ✅ Each camera supports multi-client streaming (from PRD-002 Phase 3)
- ✅ Each camera announced via MAVLink with correct URL
- ✅ Configuration-driven camera setup (no code changes for new cameras)

### Non-Functional Requirements
- ✅ Resource isolation between camera pipelines
- ✅ Graceful handling of camera failures (one camera failure doesn't affect others)
- ✅ Performance: Support at least 2 simultaneous 720p30 streams
- ✅ Latency: Maintain <500ms latency per camera (from PRD-002)
- ✅ Backward compatibility with single-camera deployments

### Integration Requirements
- ✅ Announcer service detects and announces all configured cameras
- ✅ QGroundControl can discover and view all cameras
- ✅ Each camera appears as separate video source in ground station

## Risks and Mitigations

### Risk: Hardware Support
**Risk:** CM5 may not support multiple CSI-2 cameras simultaneously
**Mitigation:**
- Verify hardware capabilities before implementation
- Fall back to single camera + USB camera if needed
- Document tested hardware configurations

### Risk: Resource Constraints
**Risk:** Multiple camera pipelines may exceed CPU/memory limits
**Mitigation:**
- Implement resource monitoring and limits
- Support camera activation policies (active vs. on-demand)
- Allow per-camera quality/framerate configuration
- Benchmark early and adjust expectations

### Risk: Configuration Complexity
**Risk:** Multi-camera configuration may be error-prone
**Mitigation:**
- Provide clear configuration examples
- Add config validation on startup
- Clear error messages for misconfigurations
- Default to single-camera mode if multi-camera config missing

## Future Extensions

### Potential Phase 5 Features
- **Camera Switching:** Allow clients to switch between cameras without reconnecting
- **Composite Streams:** Picture-in-picture or split-screen streams
- **Recording:** Per-camera recording with different policies
- **Adaptive Quality:** Per-camera bitrate adaptation based on network conditions
- **Thermal/IR Cameras:** Support for non-visible spectrum cameras

## Open Questions (To be resolved during implementation)

1. **Camera Selection:**
   - How does rpicam-vid select between multiple CSI-2 cameras?
   - What parameter/flag specifies camera index?

2. **Resource Benchmarks:**
   - What's the actual CPU/memory overhead per camera pipeline?
   - How many simultaneous streams can CM5 reasonably handle?

3. **Hot-Plug Support:**
   - Should we support adding/removing cameras at runtime?
   - Or require service restart for camera config changes?

4. **Path Conventions:**
   - Enforce specific path format or allow custom paths?
   - Support query parameters (e.g., `?quality=high`)?

5. **Configuration Source:**
   - Environment variables, config file, or both?
   - Support dynamic config reload?

## Next Steps

1. **Complete PRD-002 Phase 4** (prerequisite)
2. **Hardware Verification:** Test multi-camera support on CM5
3. **Create Implementation Checklist** (similar to PRD-002)
4. **Begin Phase 1 Implementation**

---

**Document Status:** Draft (awaiting PRD-002 completion)
**Last Updated:** 2025-01-23
**Dependencies:** PRD-002 (video-streamer), PRD-001 (announcer_ex)
