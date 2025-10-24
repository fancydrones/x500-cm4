# PRD-005: Video Annotation with Neural Networks

**Status:** 📋 **PLANNED - NOT STARTED**
**Created:** 2025-10-25
**Target Start:** TBD
**Target Completion:** TBD (12 weeks from start)

---

## Overview

Video Annotation extends the existing video-streamer application to provide real-time neural network inference on the camera stream. The system will intercept the H.264 video stream in memory, run object detection using YOLOv11, overlay annotations (bounding boxes, labels, confidence scores), and expose the annotated stream as a separate RTSP endpoint for QGroundControl.

This project establishes a **pluggable neural network architecture** that enables easy model swapping and supports future AI-driven navigation capabilities (out of scope for this PRD).

## Goals

### Primary Objectives
1. **Dual RTSP Streams:** Expose both original and annotated video streams on same port, different paths
2. **Real-time Inference:** Run YOLOv11 object detection at ≥8 FPS on Raspberry Pi 5/CM5
3. **Pure Elixir Stack:** Use Ortex + Nx for neural network inference (no custom C++ NIFs)
4. **Pluggable Architecture:** Support multiple neural network backends and models
5. **Operator Assistance:** Provide visual object detection overlays in QGroundControl
6. **Future-Ready:** Foundation for AI-driven autonomous navigation (separate PRD)

### Success Metrics
- **Performance:**
  - Annotated stream FPS: ≥8 FPS (YOLOv11n-ONNX on Raspberry Pi 5)
  - Additional latency: <300ms overhead vs original stream
  - CPU usage: <60% on 4-core ARM
  - Memory overhead: <400MB (model + buffers)
- **Functionality:**
  - Both streams accessible simultaneously in QGroundControl
  - Model swap time: <5 seconds
  - Detection accuracy: >0.5 mAP on COCO dataset (YOLOv11n baseline)
- **Reliability:**
  - Zero dropped frames on original stream
  - Graceful degradation if inference fails
  - Automatic recovery from model errors

## Architecture Highlights

```
┌─────────────────────────────────────────────────────────────────┐
│                    VideoStreamer Application                     │
│                                                                   │
│  ┌─────────────┐    ┌──────────────┐    ┌──────────────┐       │
│  │   Camera    │───▶│  H.264       │───▶│     Tee      │       │
│  │   Source    │    │  Parser      │    │              │       │
│  └─────────────┘    └──────────────┘    └──────┬───────┘       │
│                                                 │               │
│                                    ┌────────────┴────────────┐  │
│                                    │                         │  │
│                            ┌───────▼─────────┐   ┌───────────▼─────────┐
│                            │ Original Stream │   │  Annotation Branch  │
│                            │ (RTP/RTSP)      │   │                     │
│                            └─────────────────┘   │  ┌──────────────┐   │
│                                                   │  │ H.264 Decode │   │
│                                                   │  └──────┬───────┘   │
│                                                   │         │           │
│  ┌──────────────────────────────────────┐        │  ┌──────▼───────┐   │
│  │    VideoAnnotator Application        │◀───────┼──│   Inference  │   │
│  │                                      │        │  │   (Ortex)    │   │
│  │  ┌────────────────────────────────┐ │        │  └──────┬───────┘   │
│  │  │      Nx.Serving (YOLO)         │ │        │         │           │
│  │  │   - YOLOv11n ONNX Model        │ │        │  ┌──────▼───────┐   │
│  │  │   - Ortex ONNX Runtime         │ │        │  │   Overlay    │   │
│  │  │   - Concurrent batching        │ │        │  │   Renderer   │   │
│  │  └────────────────────────────────┘ │        │  └──────┬───────┘   │
│  │                                      │        │         │           │
│  │  ┌────────────────────────────────┐ │        │  ┌──────▼───────┐   │
│  │  │   InferenceEngine Behaviour    │ │        │  │ H.264 Encode │   │
│  │  │   - Pluggable backends         │ │        │  └──────┬───────┘   │
│  │  │   - Model registry             │ │        │         │           │
│  │  └────────────────────────────────┘ │        │  ┌──────▼───────┐   │
│  └──────────────────────────────────────┘        │  │ RTP/RTSP Out │   │
│                                                   │  └──────────────┘   │
│                                                   └─────────────────────┘
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────┐     │
│  │              RTSP Server (Port 8554)                           │     │
│  │   - /video          → Original stream                          │     │
│  │   - /video_annotated → Annotated stream                        │     │
│  └───────────────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────────────────┘
                           ↓
                  ┌─────────────────┐
                  │  QGroundControl │
                  │  - Video Widget │
                  │  - Dual Streams │
                  └─────────────────┘
```

**Key Features:**
- ONNX model inference via Ortex (ONNX Runtime)
- YOLOv11 object detection (starting model)
- Dual RTSP streams on same port, different paths
- Pluggable inference engine architecture
- Membrane Framework video processing pipeline
- Hot-swappable neural network models

## Implementation Phases

| Phase | Duration | Focus |
|-------|----------|-------|
| **Phase 1** | Week 1-2 | ONNX model setup, Ortex integration, basic inference |
| **Phase 2** | Week 3-4 | Membrane pipeline integration, frame processing |
| **Phase 3** | Week 5-6 | Dual RTSP streams, multi-client support |
| **Phase 4** | Week 7-8 | Pluggable architecture, model registry |
| **Phase 5** | Week 9-10 | Performance optimization, frame skipping |
| **Phase 6** | Week 11-12 | Testing, containerization, documentation |
| **Phase 7** | Post-MVP | Future enhancements (AI navigation foundation) |

**Total Timeline:** 12 weeks

## Documents

### Planning Documents
- **[Implementation Plan](implementation_plan.md)** - Complete technical specification and implementation guide
- **[Implementation Checklist](implementation_checklist.md)** - Detailed task breakdown (~200 tasks)
- **[Architecture](architecture.md)** - System architecture and component diagrams
- **[Model Export Guide](model-export-guide.md)** - YOLOv11 → ONNX conversion workflow

### Phase Completion Notes (To be created during implementation)
- Phase 1: ONNX integration and basic inference
- Phase 2: Membrane pipeline integration
- Phase 3: Dual RTSP streams
- Phase 4: Pluggable architecture
- Phase 5: Performance optimization
- Phase 6: Testing and documentation

### Deliverables (To be created)
- VideoAnnotator application (`apps/video_annotator/`)
- Extended VideoStreamer with annotation pipeline
- ONNX model artifacts (YOLOv11n exported)
- Docker container with ONNX Runtime
- Kubernetes deployment manifests
- CI/CD pipeline updates
- Comprehensive documentation

## Technology Stack

**Core:**
- Elixir 1.18+
- Membrane Framework ~> 1.0 (video processing)
- Ortex ~> 0.1 (ONNX Runtime bindings)
- Nx ~> 0.7 (numerical computing)
- yolo_elixir (YOLO model integration)

**Neural Networks:**
- YOLOv11n (starting model)
- ONNX format (primary)
- ONNX Runtime (inference engine)

**Infrastructure:**
- Alpine Linux (container base)
- Kubernetes (k3s)
- GitHub Actions (CI/CD)

**Development:**
- ExUnit (testing)
- ExDoc (documentation)
- Telemetry (observability)

## Key Design Decisions

### Why ONNX + Ortex?

**Benefits:**
1. **Pure Elixir Stack:** No custom C++ NIFs to maintain (Ortex handles ONNX Runtime)
2. **Mature Ecosystem:** Ortex maintained by elixir-nx team, well-tested
3. **Model Compatibility:** ONNX is industry standard, broad model support
4. **yolo_elixir Library:** Ready-to-use YOLO integration
5. **Nx.Serving:** Built-in concurrency and distributed inference
6. **ARM Optimization:** ONNX Runtime supports ARM Compute Library backend

**Trade-offs:**
- ONNX Runtime ~20-30% slower than NCNN on embedded devices
- Higher memory usage (~400MB vs ~200MB for pure NCNN)
- Acceptable for developer experience and maintainability

### Why Not Bumblebee/Axon?

- Bumblebee doesn't support YOLO architectures as of 2025
- AxonONNX only supports subset of ONNX specification
- Ortex provides full ONNX Runtime compatibility
- yolo_elixir is production-ready for YOLO models

### Dual Stream Architecture

**Benefits:**
1. **Backward Compatibility:** Original stream unchanged
2. **Flexible Usage:** Operators choose which stream to view
3. **Performance:** No inference overhead if annotated stream not requested
4. **Testing:** Easy A/B comparison

**Implementation:**
- Branch pipeline after H.264 parser
- Original path: Direct to RTP/RTSP
- Annotated path: Decode → Inference → Overlay → Encode → RTP/RTSP

## Integration Points

### Upstream (Input Sources)
- **Raspberry Pi Camera:** Via Membrane.Rpicam.Source
- **Existing VideoStreamer:** Extend current pipeline

### Downstream (Output Destinations)
- **QGroundControl:** RTSP client for both streams
- **Original stream:** `/video` (unchanged behavior)
- **Annotated stream:** `/video_annotated` (new endpoint)

### Configuration
- **video-streamer ConfigMap:** Add neural network configuration
- **Model artifacts:** Stored in container or ConfigMap

## Comparison: Current vs Video Annotation

| Aspect | Current VideoStreamer | With Video Annotation |
|--------|---------------------|---------------------|
| **Streams** | Single stream (`/video`) | Dual streams (`/video`, `/video_annotated`) |
| **Processing** | Camera → H.264 → RTSP | Camera → H.264 → (Branch) → RTSP |
| **Latency** | ~50-100ms | Original: ~50-100ms, Annotated: ~300-400ms |
| **CPU Usage** | ~15-20% | Original: ~15-20%, Annotated: ~55-60% |
| **Memory** | ~100-150MB | ~500-550MB (includes model) |
| **Use Case** | Raw video feed | Raw + AI-assisted object detection |

## Dependencies

### Hardware
- Raspberry Pi CM4/CM5 (Cortex-A72/A76)
- Camera module (IMX219 or compatible)
- Network connectivity

### Software
- Existing video-streamer application
- Elixir 1.18+
- ONNX Runtime libraries
- Membrane Framework plugins
- K3s cluster

### External Services
- **Model Export:** Python + Ultralytics (one-time, not runtime)
- **ONNX Runtime:** Bundled in container

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| ONNX performance insufficient | Medium | High | Profile early, use frame skipping, optimize ARM backend |
| yolo_elixir YOLOv11 compatibility | Medium | Medium | Test with YOLOv8 first, contribute upstream fixes |
| Frame conversion overhead | Medium | High | Optimize Membrane pipeline, consider hardware acceleration |
| Memory constraints on Pi | Low | Medium | Use quantized INT8 models, limit frame buffers |
| Dual stream synchronization | Low | Low | Independent pipelines, separate timing |
| Model size and loading time | Low | Medium | Pre-load models, use smaller YOLOv11n variant |

## Future Enhancements

### Post-MVP Features
1. **Additional Models:** Segmentation, pose estimation, depth estimation
2. **Multi-Model Pipelines:** Detection + classification + tracking
3. **On-Device Training:** Fine-tuning on drone-specific data
4. **Detection Events:** Publish detections to MAVLink for telemetry
5. **Advanced Overlay:** Heatmaps, trajectories, custom annotations
6. **Model Quantization:** INT8, FP16 for better performance

### Long-term Vision (Separate PRDs)
- **AI-Driven Navigation:** Use detections for autonomous flight
- **Object Tracking:** Persistent object IDs across frames
- **Geospatial Mapping:** Map detected objects to GPS coordinates
- **Multi-Drone Coordination:** Share detection data across drone fleet

## Getting Started (When Implementation Begins)

### Prerequisites
1. Elixir 1.18+ installed
2. Access to Raspberry Pi 5/CM5 hardware
3. Familiarity with existing video-streamer
4. Python environment for model export (one-time)

### Implementation Steps
1. Review [Implementation Plan](implementation_plan.md)
2. Follow [Implementation Checklist](implementation_checklist.md)
3. Export YOLOv11n to ONNX using [Model Export Guide](model-export-guide.md)
4. Complete Phase 1 tasks
5. Document progress in phase completion notes
6. Continue through phases 2-6

### Development Workflow
1. Create feature branch
2. Implement tasks from checklist
3. Write tests (maintain >80% coverage)
4. Update documentation
5. Create PR with phase completion notes
6. Review and merge

## References

### Internal Documents
- [Implementation Plan](implementation_plan.md) - Complete technical specification
- [Implementation Checklist](implementation_checklist.md) - Task breakdown
- [Architecture](architecture.md) - System architecture diagrams
- [Model Export Guide](model-export-guide.md) - ONNX export workflow
- [PRD-004 Router-Ex](../004-router-ex/implementation_plan.md) - Reference implementation pattern

### External Resources
- [Ortex Documentation](https://hexdocs.pm/ortex)
- [yolo_elixir GitHub](https://github.com/poeticoding/yolo_elixir)
- [Membrane Framework](https://membrane.stream/)
- [ONNX Runtime](https://onnxruntime.ai/)
- [Ultralytics YOLOv11](https://docs.ultralytics.com/)
- [Nx Documentation](https://hexdocs.pm/nx)

## Questions & Discussions

For questions or discussions about Video Annotation:
1. Review the Implementation Plan
2. Check the Implementation Checklist
3. Create an issue in the repository
4. Discuss in team meetings

## Status Updates

### Current Status: NOT STARTED
- 📋 Planning complete
- 🎯 Ready for implementation
- ⏸️ Awaiting start date decision

### Milestones (To be updated during implementation)
- [ ] Phase 1 Complete: ONNX model integration
- [ ] Phase 2 Complete: Membrane pipeline integration
- [ ] Phase 3 Complete: Dual RTSP streams working
- [ ] Phase 4 Complete: Pluggable architecture
- [ ] Phase 5 Complete: Performance optimized
- [ ] Phase 6 Complete: Documentation finished
- [ ] Production deployment
- [ ] Validation with QGroundControl

---

**PRD Owner:** TBD
**Technical Lead:** TBD
**Target Users:** x500-cm4 UAV platform operators and developers

**Last Updated:** 2025-10-25
