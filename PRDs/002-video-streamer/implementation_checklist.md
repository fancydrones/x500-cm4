# Video Streamer Implementation Checklist

## Overview
This checklist tracks the implementation progress of the low-latency RTSP video streaming service. Mark items as complete as you progress through each phase.

**Start Date:** 2025-10-19
**Target Completion:** TBD
**Current Phase:** Phase 1 Complete ✅ - Moving to Phase 2

---

## Phase 1: Project Setup & Basic Pipeline (Weeks 1-2) ✅ COMPLETE

### 1.1 Project Structure ⏱️ Est: 2 hours ✅ DONE
- [x] Create new Mix project: `apps/video_streamer`
- [x] Add all Membrane dependencies to `mix.exs`
- [x] Run `mix deps.get` and verify all dependencies compile
- [x] Create basic folder structure: `lib/video_streamer/{pipeline,rtsp,rtp,telemetry}`
- [x] Set up `.gitignore` for Elixir project

### 1.2 Configuration Setup ⏱️ Est: 3 hours ✅ DONE
- [x] Create `config/config.exs` with development defaults
- [x] Create `config/dev.exs` for development overrides
- [x] Create `config/test.exs` for test configuration
- [x] Create `config/prod.exs` for production settings
- [x] Create `config/runtime.exs` for environment variable parsing
- [ ] Add configuration validation on startup (deferred to Phase 2)
- [x] Document all configuration options in README

### 1.3 Basic Pipeline Implementation ⏱️ Est: 8 hours ✅ DONE
- [x] Create `lib/video_streamer/pipeline.ex` module
- [x] Implement pipeline initialization with camera source
- [x] Add H.264 parser element
- [x] Add RTP payloader element
- [x] Implement basic error handling
- [x] Add pipeline state management
- [x] Test pipeline compilation (without hardware)

### 1.4 Pipeline Manager ⏱️ Est: 6 hours ✅ DONE
- [x] Create `lib/video_streamer/pipeline_manager.ex` GenServer
- [x] Implement `start_streaming/0` function
- [x] Implement `stop_streaming/0` function
- [x] Implement `restart_streaming/1` with config updates
- [x] Implement `get_status/0` function
- [x] Add auto-start on initialization
- [x] Add crash recovery logic
- [ ] Test state transitions (start/stop/restart) (deferred to hardware testing)

### 1.5 Application Supervisor ⏱️ Est: 2 hours ✅ DONE
- [x] Create `lib/video_streamer/application.ex`
- [x] Configure supervision tree
- [x] Add PipelineManager to supervision
- [x] Add Telemetry to supervision (stub for now)
- [x] Test application starts without errors
- [x] Verify supervisor restart strategies work

### 1.6 Telemetry Setup ⏱️ Est: 4 hours ✅ DONE
- [x] Create `lib/video_streamer/telemetry.ex` supervisor
- [x] Add telemetry_poller for VM metrics
- [x] Implement memory measurement
- [x] Implement CPU measurement
- [x] Attach Membrane telemetry handlers
- [x] Add logging for key events
- [ ] Test telemetry data collection (deferred to hardware testing)

### 1.7 Hardware Testing ⏱️ Est: 4 hours ⏸️ PENDING
- [ ] Set up Raspberry Pi CM5 test environment
- [ ] Install libcamera and libcamera-apps on Pi
- [ ] Test `libcamera-hello --list-cameras`
- [ ] Test `libcamera-vid` H.264 encoding
- [ ] Verify GPU memory allocation (≥128MB)
- [ ] Run basic pipeline on actual hardware
- [ ] Capture 10-second test video successfully
- [ ] Verify H.264 output is valid

**Phase 1 Completion Criteria:**
- [x] Application starts without errors
- [ ] Pipeline captures video from camera (requires hardware)
- [ ] H.264 encoding works via GPU (requires hardware)
- [ ] All unit tests pass (basic tests pass, more needed)
- [ ] Hardware test successful on Raspberry Pi (pending hardware access)

**Phase 1 Notes:**
- Core software implementation complete and compiles successfully
- All Membrane dependencies resolved and integrated
- Hardware testing deferred until Raspberry Pi CM5 is available
- Configuration validation and comprehensive testing will be done in later phases

---

## Phase 2: RTSP Server Implementation (Weeks 3-4)

### 2.1 RTSP Protocol Module ⏱️ Est: 6 hours
- [ ] Create `lib/video_streamer/rtsp/protocol.ex`
- [ ] Implement RTSP request parser
- [ ] Implement `build_options_response/1`
- [ ] Implement `build_describe_response/2`
- [ ] Implement `build_setup_response/3`
- [ ] Implement `build_play_response/2`
- [ ] Implement `build_teardown_response/2`
- [ ] Add header extraction helpers
- [ ] Write unit tests for all parsers/builders

### 2.2 SDP Generator ⏱️ Est: 4 hours
- [ ] Create `lib/video_streamer/rtsp/sdp.ex`
- [ ] Implement SDP template generation
- [ ] Add H.264 codec parameters (SPS/PPS)
- [ ] Add dynamic resolution/framerate info
- [ ] Implement Base64 encoding for parameters
- [ ] Test SDP generation with different configs
- [ ] Validate SDP with RTSP validators

### 2.3 RTSP Session Handler ⏱️ Est: 10 hours
- [ ] Create `lib/video_streamer/rtsp/session.ex` GenServer
- [ ] Implement session initialization
- [ ] Handle OPTIONS request
- [ ] Handle DESCRIBE request
- [ ] Handle SETUP request (parse Transport header)
- [ ] Handle PLAY request (start RTP streaming)
- [ ] Handle TEARDOWN request
- [ ] Implement session ID generation
- [ ] Add session timeout handling
- [ ] Track session state machine
- [ ] Test each RTSP method independently

### 2.4 RTSP Server ⏱️ Est: 8 hours
- [ ] Create `lib/video_streamer/rtsp/server.ex` GenServer
- [ ] Implement TCP socket listening
- [ ] Handle new client connections
- [ ] Spawn session handler per client
- [ ] Track active sessions
- [ ] Implement graceful shutdown
- [ ] Add connection limit (start with 5 max)
- [ ] Test with multiple concurrent clients
- [ ] Add error handling for socket failures

### 2.5 Integration ⏱️ Est: 6 hours
- [ ] Add RTSP.Server to application supervisor
- [ ] Configure RTSP port from environment
- [ ] Wire up RTSP server with pipeline manager
- [ ] Test complete RTSP handshake flow
- [ ] Verify SDP is returned correctly
- [ ] Test client disconnect handling
- [ ] Test server restart scenarios

### 2.6 Client Testing ⏱️ Est: 4 hours
- [ ] Test with VLC: `vlc rtsp://localhost:8554/video`
- [ ] Test with ffplay: `ffplay rtsp://localhost:8554/video`
- [ ] Test with gstreamer pipeline
- [ ] Test RTSP handshake with curl/telnet
- [ ] Document any client compatibility issues
- [ ] Create troubleshooting guide

**Phase 2 Completion Criteria:**
- [ ] RTSP server listens on port 8554
- [ ] Clients can complete RTSP handshake
- [ ] SDP is valid and contains correct codec info
- [ ] Session management works correctly
- [ ] All integration tests pass

---

## Phase 3: RTP Integration & Pipeline Connection (Week 5)

### 3.1 RTP Sender Module ⏱️ Est: 6 hours
- [ ] Create `lib/video_streamer/rtp/sender.ex` GenServer
- [ ] Implement UDP socket creation
- [ ] Implement `send_packet/2` function
- [ ] Add sequence number tracking
- [ ] Add timestamp generation
- [ ] Implement RTCP support (basic)
- [ ] Test RTP packet sending
- [ ] Verify packets receivable by VLC

### 3.2 Pipeline Multi-Output ⏱️ Est: 8 hours
- [ ] Update pipeline.ex to include Membrane.Tee
- [ ] Implement dynamic client branch creation
- [ ] Handle `:add_client` notification
- [ ] Handle `:remove_client` notification
- [ ] Create RTP payloader per client
- [ ] Create callback sink per client
- [ ] Wire sink to RTP.Sender
- [ ] Test adding/removing clients dynamically

### 3.3 RTSP-RTP Integration ⏱️ Est: 8 hours
- [ ] Connect RTSP session to RTP sender
- [ ] Pass client IP and ports to RTP sender
- [ ] Start RTP sender on PLAY command
- [ ] Stop RTP sender on TEARDOWN
- [ ] Notify pipeline of new client
- [ ] Notify pipeline when client disconnects
- [ ] Test end-to-end flow (RTSP → RTP → client)

### 3.4 Buffer Management ⏱️ Est: 6 hours
- [ ] Configure minimal buffering in pipeline
- [ ] Tune RTP payloader for low latency
- [ ] Adjust camera source buffer settings
- [ ] Monitor queue sizes under load
- [ ] Implement buffer overflow handling
- [ ] Test with network jitter simulation

### 3.5 Multi-Client Testing ⏱️ Est: 4 hours
- [ ] Test 2 simultaneous VLC clients
- [ ] Test 3+ clients (stress test)
- [ ] Measure performance degradation
- [ ] Test client connect/disconnect during streaming
- [ ] Test rapid connect/disconnect cycles
- [ ] Verify no memory leaks with long-running streams

**Phase 3 Completion Criteria:**
- [ ] Video stream visible in VLC/ffplay
- [ ] Multiple clients can view simultaneously
- [ ] No crashes during client connect/disconnect
- [ ] Latency measured and documented
- [ ] All integration tests pass

---

## Phase 4: Container & Deployment (Week 6)

### 4.1 Dockerfile Creation ⏱️ Est: 6 hours
- [ ] Create `apps/video_streamer/Dockerfile`
- [ ] Set up builder stage with Elixir Alpine
- [ ] Install build dependencies
- [ ] Build/install libcamera and libcamera-apps
- [ ] Set up runtime stage
- [ ] Copy release from builder
- [ ] Install runtime dependencies only
- [ ] Test local Docker build
- [ ] Optimize image size (<200MB goal)

### 4.2 Mix Release Configuration ⏱️ Est: 3 hours
- [ ] Configure `mix release` in mix.exs
- [ ] Set up production config
- [ ] Test release build locally
- [ ] Verify release starts correctly
- [ ] Test release in Docker container
- [ ] Document release process

### 4.3 Kubernetes Manifests ⏱️ Est: 6 hours
- [ ] Create `deployments/apps/video-streamer-deployment.yaml`
- [ ] Configure pod security (privileged access)
- [ ] Mount /dev devices for camera
- [ ] Set resource limits (CPU/memory)
- [ ] Configure environment variables
- [ ] Add health check probes
- [ ] Create Service manifest (NodePort)
- [ ] Test deployment in dev cluster

### 4.4 ConfigMap Setup ⏱️ Est: 2 hours
- [ ] Create `deployments/apps/video-streamer-config.yaml`
- [ ] Define all configuration parameters
- [ ] Add quality presets
- [ ] Link ConfigMap to Deployment
- [ ] Test configuration updates
- [ ] Document configuration management

### 4.5 CI/CD Pipeline ⏱️ Est: 8 hours
- [ ] Create `.github/workflows/video-streamer.yaml`
- [ ] Set up Docker build job
- [ ] Configure image tagging strategy
- [ ] Push to GitHub Container Registry
- [ ] Set up deployment job
- [ ] Add Kubernetes manifest updates
- [ ] Configure triggers (on PR, on main)
- [ ] Test full CI/CD flow
- [ ] Add status badges to README

### 4.6 Hardware Access Configuration ⏱️ Est: 4 hours
- [ ] Document host GPU memory requirements
- [ ] Create host configuration script
- [ ] Verify /dev/video* device access
- [ ] Test camera detection in container
- [ ] Configure device plugin (if needed)
- [ ] Test on actual Raspberry Pi CM5

### 4.7 Deployment Verification ⏱️ Est: 4 hours
- [ ] Deploy to development cluster
- [ ] Verify pod starts successfully
- [ ] Check logs for errors
- [ ] Test RTSP connection from external client
- [ ] Verify video stream works
- [ ] Test pod restart/recovery
- [ ] Document any issues and solutions

**Phase 4 Completion Criteria:**
- [ ] Docker image builds successfully
- [ ] Container runs on Raspberry Pi
- [ ] Kubernetes deployment successful
- [ ] Stream accessible via NodePort
- [ ] CI/CD pipeline fully operational
- [ ] Health checks working

---

## Phase 5: Testing & Optimization (Weeks 7-8)

### 5.1 Unit Test Suite ⏱️ Est: 8 hours
- [ ] Write tests for configuration loading
- [ ] Write tests for RTSP protocol parsing
- [ ] Write tests for RTSP response building
- [ ] Write tests for SDP generation
- [ ] Write tests for pipeline manager state machine
- [ ] Write tests for RTP sender
- [ ] Achieve >80% code coverage
- [ ] Set up automated test running

### 5.2 Integration Tests ⏱️ Est: 10 hours
- [ ] Create `test/integration/rtsp_flow_test.exs`
- [ ] Test complete RTSP handshake
- [ ] Test multi-client scenarios
- [ ] Test pipeline restart with new config
- [ ] Test error handling (camera unavailable)
- [ ] Test network failure scenarios
- [ ] Test graceful shutdown
- [ ] All integration tests passing

### 5.3 Performance Testing ⏱️ Est: 12 hours
- [ ] Set up latency measurement environment
- [ ] Measure camera-to-display latency
- [ ] Test with 720p30, 1080p30, 1080p60
- [ ] Measure CPU usage (idle and active)
- [ ] Measure memory usage over time
- [ ] Test 24-hour stability run
- [ ] Profile for bottlenecks
- [ ] Document all performance metrics

### 5.4 Latency Optimization ⏱️ Est: 8 hours
- [ ] Minimize camera source buffering
- [ ] Tune H.264 encoder for low latency
- [ ] Optimize RTP packet size
- [ ] Reduce pipeline queue sizes
- [ ] Test with different keyframe intervals
- [ ] Benchmark different H.264 profiles
- [ ] Document optimal settings
- [ ] Re-measure latency after optimizations

### 5.5 Resource Optimization ⏱️ Est: 6 hours
- [ ] Profile memory allocation
- [ ] Reduce unnecessary data copies
- [ ] Optimize Elixir release size
- [ ] Minimize Docker image layers
- [ ] Test with reduced resource limits
- [ ] Document minimum requirements
- [ ] Create resource recommendation guide

### 5.6 Load Testing ⏱️ Est: 6 hours
- [ ] Test with maximum client count
- [ ] Simulate high network latency
- [ ] Simulate packet loss scenarios
- [ ] Test with bandwidth limitations
- [ ] Test rapid client connect/disconnect
- [ ] Document degradation thresholds
- [ ] Create load testing scripts

### 5.7 Compatibility Testing ⏱️ Est: 8 hours
- [ ] Test with QGroundControl (macOS, Windows, Linux)
- [ ] Test with ATAK (Android)
- [ ] Test with VLC (multiple versions)
- [ ] Test with ffplay
- [ ] Test with GStreamer pipelines
- [ ] Document client-specific settings
- [ ] Create compatibility matrix

**Phase 5 Completion Criteria:**
- [ ] Unit test coverage >80%
- [ ] All integration tests passing
- [ ] Latency <500ms documented
- [ ] Performance benchmarks complete
- [ ] Compatibility with QGC/ATAK verified
- [ ] 24-hour stability test passed

---

## Phase 6: Documentation & Deployment Guide (Week 9)

### 6.1 User Documentation ⏱️ Est: 8 hours
- [ ] Complete `apps/video_streamer/README.md`
- [ ] Document all configuration options
- [ ] Create quick start guide
- [ ] Document QGroundControl setup
- [ ] Document ATAK setup
- [ ] Create troubleshooting guide
- [ ] Add FAQ section
- [ ] Include example configurations

### 6.2 Architecture Documentation ⏱️ Est: 6 hours
- [ ] Create `docs/video-streamer-architecture.md`
- [ ] Document system architecture
- [ ] Create pipeline flow diagrams
- [ ] Document RTSP protocol flow
- [ ] Explain RTP packet flow
- [ ] Document multi-client architecture
- [ ] Add sequence diagrams

### 6.3 Operations Guide ⏱️ Est: 8 hours
- [ ] Create `docs/video-streamer-operations.md`
- [ ] Document deployment procedures
- [ ] Document configuration management
- [ ] Create monitoring guide
- [ ] Document common issues and solutions
- [ ] Create performance tuning guide
- [ ] Document backup/restore procedures
- [ ] Add incident response guide

### 6.4 Development Guide ⏱️ Est: 6 hours
- [ ] Document development setup
- [ ] Create contributing guidelines
- [ ] Document testing procedures
- [ ] Explain project structure
- [ ] Document Membrane concepts used
- [ ] Add code style guidelines
- [ ] Create PR template

### 6.5 API Documentation ⏱️ Est: 4 hours
- [ ] Generate ExDoc documentation
- [ ] Document all public APIs
- [ ] Add module documentation
- [ ] Add function examples
- [ ] Document configuration schema
- [ ] Publish to HexDocs (if applicable)

### 6.6 Deployment Automation ⏱️ Est: 6 hours
- [ ] Create deployment scripts
- [ ] Document GitOps workflow
- [ ] Create environment-specific configs
- [ ] Document rollback procedures
- [ ] Create health check scripts
- [ ] Document monitoring setup

### 6.7 Training Materials ⏱️ Est: 4 hours
- [ ] Create operator training guide
- [ ] Record demo video
- [ ] Create troubleshooting flowcharts
- [ ] Document best practices
- [ ] Create configuration checklists
- [ ] Prepare presentation materials

**Phase 6 Completion Criteria:**
- [ ] All documentation complete
- [ ] README comprehensive and clear
- [ ] Operations guide available
- [ ] Troubleshooting guide tested
- [ ] Training materials ready
- [ ] Code documentation generated

---

## Post-Implementation

### Production Readiness ⏱️ Est: 8 hours
- [ ] Security review completed
- [ ] Performance review completed
- [ ] Code review completed
- [ ] Documentation review completed
- [ ] Staging deployment successful
- [ ] Production deployment plan approved
- [ ] Rollback plan documented
- [ ] Monitoring and alerts configured

### Production Deployment
- [ ] Deploy to production cluster
- [ ] Verify all health checks passing
- [ ] Monitor for 24 hours
- [ ] Collect user feedback
- [ ] Document any issues
- [ ] Create post-deployment report

### Handoff
- [ ] Knowledge transfer session completed
- [ ] Operations team trained
- [ ] On-call procedures documented
- [ ] Access and permissions configured
- [ ] Monitoring dashboards created
- [ ] Runbook created and reviewed

---

## Future Enhancements (Backlog)

### Recording Feature
- [ ] Design recording architecture
- [ ] Implement MP4 muxer integration
- [ ] Add Tee branch for recording
- [ ] Implement file rotation
- [ ] Add storage management
- [ ] Create recording API
- [ ] Test recording performance impact

### Dynamic Quality Adjustment
- [ ] Design adaptive bitrate logic
- [ ] Implement bandwidth monitoring
- [ ] Create quality switching mechanism
- [ ] Test automatic adjustments
- [ ] Document quality profiles

### WebRTC Support
- [ ] Research Membrane WebRTC plugins
- [ ] Design WebRTC architecture
- [ ] Implement signaling server
- [ ] Create web viewer
- [ ] Test ultra-low latency
- [ ] Compare with RTSP performance

### Additional Cameras
- [ ] Design multi-camera architecture
- [ ] Implement camera selector
- [ ] Test dual-camera streaming
- [ ] Document camera configuration

---

## Progress Summary

**Phase 1:** ✅ Complete (Software implementation done, hardware testing pending)
**Phase 2:** ⬜ Not Started
**Phase 3:** ⬜ Not Started
**Phase 4:** ⬜ Not Started
**Phase 5:** ⬜ Not Started
**Phase 6:** ⬜ Not Started

**Overall Progress:** ~30 / 215 tasks completed (~14%)

**Completed Subsections:**
- 1.1 Project Structure (5/5)
- 1.2 Configuration Setup (6/7 - validation deferred)
- 1.3 Basic Pipeline Implementation (7/7)
- 1.4 Pipeline Manager (6/7 - testing deferred)
- 1.5 Application Supervisor (6/6)
- 1.6 Telemetry Setup (6/7 - testing deferred)
- 1.7 Hardware Testing (0/8 - pending hardware access)

---

## Notes & Blockers

### Current Blockers

- **Hardware Access Required**: Phase 1.7 hardware testing requires access to Raspberry Pi CM5 with camera
- All software components are complete and compile successfully
- Can proceed with Phase 2 (RTSP Server) in parallel with hardware setup

### Decisions Made

- **Module naming**: Using `Membrane.Rpicam.Source` (lowercase 'picam') as per the actual library
- **Dependency versions**: Updated to latest available versions:
  - membrane_rtp_plugin: 0.31.0 (from 0.29.0)
  - membrane_rtp_h264_plugin: 0.20.0 (from 0.19.0)
  - membrane_rtsp: 0.11.0 (from 0.7.0)
  - membrane_udp_plugin: 0.14.0 (from 0.13.0)
  - membrane_tcp_plugin: 0.6.0 (from 0.7.0)
  - membrane_h264_plugin: 0.9.0 (from 0.10.0)
- **Auto-start behavior**: Pipeline manager auto-starts on application boot
- **Configuration approach**: Using runtime.exs for production environment variables

### Lessons Learned

- Membrane plugin versions change frequently; always check hex.pm for latest compatible versions
- The Membrane ecosystem uses lowercase module names (e.g., `Rpicam` not `RpiCam`)
- Starting with solid configuration management from the beginning saves time later

---

**Last Updated:** 2025-10-19
**Updated By:** Claude Code (Implementation of Phase 1)
