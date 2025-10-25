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
3. **Pure Elixir Stack:** Use yolo_elixir + Ortex + Nx for neural network inference (no custom C++ NIFs)
4. **Fast Development Loop:** Support local macOS development with webcam for rapid iteration
5. **Pluggable Architecture:** Support multiple neural network backends and models
6. **Operator Assistance:** Provide visual object detection overlays in QGroundControl
7. **Future-Ready:** Foundation for AI-driven autonomous navigation (separate PRD)

### Success Metrics
- **Performance (Production - Raspberry Pi 5):**
  - Annotated stream FPS: ≥8 FPS (YOLOv11n-ONNX on Raspberry Pi 5)
  - Additional latency: <300ms overhead vs original stream
  - CPU usage: <60% on 4-core ARM
  - Memory overhead: <400MB (model + buffers)
- **Performance (Development - macOS):**
  - Annotated stream FPS: ≥15 FPS with CoreML acceleration
  - Webcam capture working smoothly
  - Fast iteration cycle: <30s from code change to live result
- **Functionality:**
  - Both streams accessible simultaneously (QGC for production, browser/VLC for dev)
  - Model swap time: <5 seconds
  - Detection accuracy: >0.5 mAP on COCO dataset (YOLOv11n baseline)
  - Works on both Raspberry Pi and macOS without code changes
- **Reliability:**
  - Zero dropped frames on original stream
  - Graceful degradation if inference fails
  - Automatic recovery from model errors

## Future Enhancements

### RF-DETR Integration (Post Phase 3)
Consider migrating from YOLOX to [RF-DETR](https://github.com/roboflow/rf-detr) for improved accuracy:
- **Better Accuracy:** RF-DETR-Nano achieves 48.4 AP vs YOLOX-Nano's 25.8 mAP (~2x improvement)
- **Modern Architecture:** Transformer-based real-time detection (2025, Apache 2.0 license)
- **ONNX Support:** Pre-converted models available on [Hugging Face](https://huggingface.co/PierreMarieCurie/rf-detr-onnx)
- **Implementation:** Would require custom pre/postprocessing with Ortex+Nx (no dedicated Elixir library yet)
- **Potential:** Could be extracted into `rf_detr_elixir` library for community benefit

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
| **Phase 0** | Week 1 | **Local dev setup**: macOS webcam + yolo_elixir proof-of-concept |
| **Phase 1** | Week 2-3 | ONNX model setup, yolo_elixir integration, basic inference |
| **Phase 2** | Week 4-5 | Membrane pipeline integration, frame processing (macOS + Pi) |
| **Phase 3** | Week 6-7 | Dual RTSP streams, multi-client support |
| **Phase 4** | Week 8-9 | Pluggable architecture, model registry |
| **Phase 5** | Week 10-11 | Performance optimization, frame skipping |
| **Phase 6** | Week 12-13 | Testing, containerization, documentation |
| **Phase 7** | Post-MVP | Future enhancements (AI navigation foundation) |

**Total Timeline:** 13 weeks (includes Phase 0 for fast iteration setup)

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
- **yolo_elixir ~> 0.3** (YOLO model integration - primary interface)
- Ortex ~> 0.1 (ONNX Runtime bindings - via yolo_elixir)
- Nx ~> 0.7 (numerical computing)
- EXLA ~> 0.7 (Nx backend, optional but recommended)

**Neural Networks:**
- **YOLOv11n** (primary - latest YOLO architecture)
- YOLOX models (alternative - pre-converted available)
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

**Platform-Specific:**
- **macOS:** membrane_camera_capture_plugin (FFmpeg-based webcam)
- **macOS:** CoreML acceleration (via Ortex features: [:coreml])
- **Raspberry Pi:** Membrane.Rpicam.Source (hardware camera)
- **Raspberry Pi:** ARM Compute Library (via ONNX Runtime)

## Key Design Decisions

### Why yolo_elixir Library?

**Benefits:**
1. **Simplicity:** High-level API abstracts ONNX/Ortex complexity
2. **Battle-Tested:** Production-ready library maintained by @poeticoding
3. **YOLO-Specific:** Handles YOLO preprocessing/postprocessing (NMS, bbox conversion)
4. **Hardware Acceleration:** Automatic CoreML (macOS), CUDA, TensorRT support
5. **Multiple Models:** Supports YOLOX and Ultralytics YOLO models
6. **Pure Elixir:** Built on Nx/Ortex, no custom NIFs

**Simple API Example:**
```elixir
# Load model
model = YOLO.load(
  model_impl: YOLO.Models.Ultralytics,
  model_path: "yolo11n.onnx",
  classes_path: "coco_classes.json"
)

# Run detection
detections = model
  |> YOLO.detect(image_tensor)
  |> YOLO.to_detected_objects(model.classes)
```

**Trade-offs:**
- Still uses ONNX (not NCNN), ~20-30% slower than pure NCNN
- Higher-level API means less control over inference details
- Acceptable for rapid development and maintainability

### Why Not Direct Ortex or Bumblebee?

- **Direct Ortex:** Too low-level, need to implement YOLO preprocessing/postprocessing
- **Bumblebee:** Doesn't support YOLO architectures as of 2025
- **AxonONNX:** Only supports subset of ONNX specification
- **yolo_elixir:** Perfect balance of simplicity and control

### Local Development Environment (Phase 0)

**Motivation:**
Fast iteration is crucial for ML development. Testing on Raspberry Pi hardware has a long feedback loop (build → deploy → test). Local macOS development with webcam enables:

**Benefits:**
1. **Fast Iteration:** <30s from code change to seeing results
2. **Easy Debugging:** Full IDE support, no SSH/container debugging
3. **CoreML Acceleration:** Better FPS than Pi during development (~15-20 FPS)
4. **Same Codebase:** Works on both macOS and Pi without changes

**Implementation:**
```elixir
# Platform-agnostic camera source
camera_source = case :os.type() do
  {:unix, :darwin} ->
    # macOS: Use FFmpeg-based webcam capture
    Membrane.CameraCapture.Source
  {:unix, :linux} ->
    # Raspberry Pi: Use hardware-accelerated Rpicam
    Membrane.Rpicam.Source
end

child(:camera, camera_source)
```

**Development Workflow:**
1. Write code on macOS with webcam
2. Test detection on local video feed
3. Iterate quickly with instant feedback
4. Deploy to Pi for production testing

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
- **Production (Raspberry Pi):** Membrane.Rpicam.Source (hardware camera)
- **Development (macOS):** Membrane.CameraCapture.Source (webcam via FFmpeg)
- **Existing VideoStreamer:** Extend current pipeline

### Downstream (Output Destinations)
- **Production:** QGroundControl RTSP client for both streams
- **Development:** VLC, ffplay, or browser-based player
- **Original stream:** `/video` (unchanged behavior)
- **Annotated stream:** `/video_annotated` (new endpoint)

### Configuration
- **Production:** video-streamer ConfigMap (K8s)
- **Development:** config/dev.exs (local Elixir config)
- **Model artifacts:**
  - Production: Stored in container or ConfigMap
  - Development: Local `priv/models/` directory

## Comparison: Current vs Video Annotation

| Aspect | Current VideoStreamer | With Video Annotation (Production) | Development (macOS) |
|--------|---------------------|---------------------|---------------------|
| **Streams** | Single (`/video`) | Dual (`/video`, `/video_annotated`) | Dual (local RTSP) |
| **Processing** | Camera → H.264 → RTSP | Camera → H.264 → (Branch) → RTSP | Webcam → H.264 → (Branch) → RTSP |
| **Latency** | ~50-100ms | Original: ~50-100ms, Annotated: ~300-400ms | Annotated: ~100-150ms (CoreML) |
| **FPS** | 30 FPS | Original: 30 FPS, Annotated: ≥8 FPS | Annotated: ≥15 FPS |
| **CPU Usage** | ~15-20% | Original: ~15-20%, Annotated: ~55-60% | ~30-40% (CoreML optimized) |
| **Memory** | ~100-150MB | ~500-550MB (includes model) | ~300-400MB |
| **Use Case** | Raw video feed | Raw + AI-assisted object detection | Fast development iteration |

## Dependencies

### Hardware
- **Production:**
  - Raspberry Pi CM4/CM5 (Cortex-A72/A76)
  - Camera module (IMX219 or compatible)
  - Network connectivity
- **Development:**
  - macOS (Apple Silicon or Intel)
  - Built-in webcam or USB camera
  - Network connectivity (optional, for RTSP streaming)

### Software
- **Common (Both Platforms):**
  - Elixir 1.18+
  - Existing video-streamer application
  - ONNX Runtime libraries
  - Membrane Framework plugins
  - FFmpeg (for camera capture and encoding)
- **Production Only:**
  - K3s cluster
  - Alpine Linux container
- **Development Only:**
  - macOS (Ventura 13+ recommended for CoreML)
  - Homebrew (for FFmpeg installation)

### External Services
- **Model Export:** Python + Ultralytics (one-time, not runtime)
- **ONNX Runtime:** Bundled in container (production) or via Ortex (development)

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

### Phase 0: Local Development Setup (Week 1)

**Goal:** Establish fast iteration loop with macOS webcam + yolo_elixir

**Prerequisites:**
1. macOS (Ventura 13+ recommended)
2. Elixir 1.18+ installed (`brew install elixir`)
3. FFmpeg installed (`brew install ffmpeg`)
4. Python 3.10+ for model export (one-time)

**Quick Start Steps:**

1. **Export YOLOv11n model:**
   ```bash
   # Install Ultralytics
   pip install ultralytics

   # Export to ONNX
   yolo export model=yolo11n.pt format=onnx imgsz=640 simplify=True

   # Or use the export script from model-export-guide.md
   python scripts/export_yolo11.py
   ```

2. **Create proof-of-concept app:**
   ```bash
   cd apps
   mix new video_annotator --sup
   ```

3. **Add dependencies (mix.exs):**
   ```elixir
   {:yolo_elixir, "~> 0.3"},
   {:membrane_camera_capture_plugin, "~> 0.7"},
   {:membrane_h264_ffmpeg_plugin, "~> 0.32"},
   {:vix, "~> 0.26"}  # For overlay rendering
   ```

4. **Test inference with YOLOv11:**
   ```bash
   export ORTEX_FEATURES=coreml  # Enable CoreML on macOS
   mix deps.get
   iex -S mix
   ```

   ```elixir
   # In IEx
   model = YOLO.load(
     model_impl: YOLO.Models.Ultralytics,
     model_path: "priv/models/yolo11n.onnx",
     classes_path: "priv/models/coco_classes.json"
   )
   ```

**Expected Outcome:**
- YOLOv11n model loaded successfully
- Inference working on test images
- Ready to integrate with webcam
- ⏱️ **Total time: ~1 hour** (includes model export)

**Next:** Follow [phase0-quickstart.md](phase0-quickstart.md) for complete webcam integration

### Full Implementation Steps (Phases 1-6)

1. Review [Implementation Plan](implementation_plan.md)
2. Follow [Implementation Checklist](implementation_checklist.md)
3. Complete Phase 0 for local development
4. Extend to Raspberry Pi in Phases 1-2
5. Add dual RTSP streams in Phase 3
6. Document progress in phase completion notes

### Development Workflow
1. **Develop locally:** Test on macOS with webcam (fast iteration)
2. **Test on Pi:** Deploy to Raspberry Pi for production validation
3. **Write tests:** Maintain >80% coverage
4. **Update docs:** Keep documentation current
5. **Create PR:** Include phase completion notes
6. **Review and merge:** Team review and approval

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
- [ ] **Phase 0 Complete:** Local macOS dev environment with webcam + yolo_elixir
- [ ] **Phase 1 Complete:** yolo_elixir integration working on both macOS and Pi
- [ ] **Phase 2 Complete:** Membrane pipeline integration with platform-agnostic camera
- [ ] **Phase 3 Complete:** Dual RTSP streams working (test locally first)
- [ ] **Phase 4 Complete:** Pluggable architecture with model registry
- [ ] **Phase 5 Complete:** Performance optimized (≥8 FPS on Pi, ≥15 FPS on macOS)
- [ ] **Phase 6 Complete:** Documentation, containerization, CI/CD
- [ ] **Production deployment:** Deployed to Raspberry Pi k3s cluster
- [ ] **Validation:** Tested with QGroundControl in field

---

**PRD Owner:** TBD
**Technical Lead:** TBD
**Target Users:** x500-cm4 UAV platform operators and developers

**Last Updated:** 2025-10-25
