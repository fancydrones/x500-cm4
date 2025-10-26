# Phase 0 Learnings - Implementation Plan Updates

**Date**: 2025-10-26
**Status**: Phase 0 Complete - Updates Required for Implementation Plan

## Executive Summary

Phase 0 (macOS development and testing) is complete and revealed critical architectural decisions that differ from the original implementation plan. This document outlines the necessary updates to the implementation plan based on these learnings.

## Critical Architecture Changes

### 1. Flow Control Strategy ❌ CHANGE REQUIRED

**Original Plan**: Use manual flow control for pull-based frame processing

**Phase 0 Reality**:
- ❌ **Manual flow control doesn't work** with Camera components (toilet overflow errors)
- ✅ **Auto flow control with time-based skipping** is the correct approach
- ✅ Simpler, more compatible, same adaptive behavior

**Update Required**:
- Remove all references to manual flow control in Phase 2
- Document auto flow control + time-based adaptive skipping pattern
- Update `AnnotationFilter` to use auto flow control with time checking

### 2. Frame Dropping Strategy ❌ CRITICAL UPDATE

**Original Plan**: Single-level frame dropping via `skip_frames` parameter

**Phase 0 Reality**:
- ✅ **Two-level frame dropping is ESSENTIAL**:
  1. `toilet_capacity: 1` - drops old frames before processor
  2. Time-based skipping - ensures minimum processing interval
- ❌ Single-level approach causes preview lag (old buffered frames processed)

**Update Required**:
- Add `toilet_capacity: 1` to pipeline specification in Phase 2
- Implement time-based skipping in `AnnotationFilter` (not just frame counting)
- Document why both levels are needed

### 3. Performance Expectations ⚠️ ADJUST TARGETS

**Original Plan**: "≥8 FPS annotated stream on Raspberry Pi 5"

**Phase 0 Reality**:
- macOS (faster than RPi): 6-7 FPS with YOLOX-Nano
- Raspberry Pi 4/5: Realistically 2-4 FPS with adaptive skipping

**Update Required**:
- Adjust performance targets to 2-4 FPS for RPi
- Document `target_interval_ms` parameter (270ms macOS → 500-600ms RPi)
- Set realistic expectations in success criteria

### 4. Model Choice 🔄 RECONSIDER

**Original Plan**: YOLOv11n

**Phase 0 Reality**:
- YOLOX-Nano (3.5MB) works excellently
- Proven compatibility with Elixir ecosystem
- Good performance characteristics

**Update Required**:
- Consider starting with YOLOX-Nano instead of YOLOv11n
- Document model size vs performance trade-offs
- YOLOv11 can be future enhancement (pluggable architecture supports it)

### 5. Preview/Monitoring 📊 ADD REQUIREMENT

**Original Plan**: No mention of development preview

**Phase 0 Reality**:
- Web preview server was ESSENTIAL for development and debugging
- MJPEG streaming with live stats crucial for tuning
- Frame-ID tracking prevents repeated frame lag

**Update Required**:
- Add web preview server to Phase 1 deliverables
- Include in development/debugging tools
- Document as optional but recommended for development

## Detailed Section Updates

### Phase 1: ONNX Model Setup & Integration

#### Changes Needed:

1. **Dependency Updates**:
```elixir
defp deps do
  [
    # Neural network inference
    {:yolo, ">= 0.2.0"},  # Use yolo (supports YOLOX) instead of yolo_elixir
    {:ortex, "~> 0.1"},
    {:nx, "~> 0.7"},
    {:exla, "~> 0.9"},  # CPU backend

    # Image processing
    {:evision, "~> 0.2"},  # Use Evision instead of Vix for better performance

    # Web preview (development only)
    {:plug, "~> 1.15", only: :dev},
    {:bandit, "~> 1.0", only: :dev},

    # Configuration & telemetry
    {:telemetry, "~> 1.2"},
    {:telemetry_metrics, "~> 1.0"}
  ]
end
```

2. **Success Criteria Updates**:
- ❌ Remove: "Inference latency <100ms per frame"
- ✅ Add: "Inference latency 130-180ms per frame on macOS (300-500ms expected on RPi)"
- ✅ Add: "Web preview server working with live FPS display"

### Phase 2: Membrane Pipeline Integration

#### Major Changes Required:

1. **AnnotationFilter Implementation** - Complete Rewrite Needed

**Replace Original Design** (lines 521-630) with:

```elixir
defmodule VideoStreamer.AnnotationFilter do
  @moduledoc """
  Custom Membrane filter for video annotation with adaptive processing.

  Key Features:
  - Auto flow control (not manual)
  - Time-based adaptive frame skipping
  - Direct YOLO integration (no separate serving needed)
  - Low-latency processing
  """

  use Membrane.Filter

  def_input_pad :input,
    accepted_format: Membrane.RawVideo,
    flow_control: :auto  # IMPORTANT: Use auto, not manual

  def_output_pad :output,
    accepted_format: Membrane.RawVideo,
    flow_control: :auto

  def_options model_path: [
    spec: String.t(),
    description: "Path to ONNX model file"
  ],
  classes_path: [
    spec: String.t(),
    description: "Path to class labels JSON"
  ],
  target_interval_ms: [
    spec: pos_integer(),
    default: 500,  # 500ms for RPi (~2 FPS)
    description: "Minimum time between frame processing (adaptive threshold)"
  ]

  @impl true
  def handle_init(_ctx, opts) do
    state = %{
      model_path: opts.model_path,
      classes_path: opts.classes_path,
      target_interval_ms: opts.target_interval_ms,
      model: nil,
      classes: nil,
      frame_count: 0,
      last_process_time: 0,
      total_inference_time: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_playing(_ctx, state) do
    # Load YOLO model
    Logger.info("Loading YOLO model from: #{state.model_path}")

    model = YOLO.load(
      model_path: state.model_path,
      classes_path: state.classes_path,
      model_impl: YOLO.Models.YOLOX
    )

    {:ok, classes_json} = File.read(state.classes_path)
    classes = Jason.decode!(classes_json)

    Logger.info("YOLO model loaded successfully")

    {[], %{state | model: model, classes: classes}}
  end

  @impl true
  def handle_buffer(:input, buffer, ctx, state) do
    current_time = System.monotonic_time(:millisecond)
    time_since_last = current_time - state.last_process_time

    # TIME-BASED ADAPTIVE SKIPPING - Critical for low latency!
    if time_since_last < state.target_interval_ms && state.frame_count > 0 do
      # Skip this frame - too soon since last processing
      {[buffer: {:output, buffer}], state}
    else
      # Process this frame
      start_time = current_time

      # Run YOLO detection (handles preprocessing internally)
      detections = YOLO.detect(state.model, buffer.payload)

      inference_time = System.monotonic_time(:millisecond) - start_time

      # Draw annotations
      annotated_buffer = draw_detections(buffer, detections, state.classes)

      # Update stats
      frame_count = state.frame_count + 1
      total_time = state.total_inference_time + inference_time

      if rem(frame_count, 30) == 0 do
        avg_time = total_time / frame_count
        fps = 1000.0 / avg_time
        Logger.info("Frame #{frame_count}: #{length(detections)} detections, " <>
                    "#{inference_time}ms, avg #{Float.round(avg_time, 1)}ms (#{Float.round(fps, 1)} FPS)")
      end

      new_state = %{
        state
        | frame_count: frame_count,
          total_inference_time: total_time,
          last_process_time: current_time
      }

      {[buffer: {:output, annotated_buffer}], new_state}
    end
  end

  defp draw_detections(buffer, detections, classes) do
    # Use Evision to draw bounding boxes
    # Implementation similar to Phase 0
    buffer
  end
end
```

2. **Pipeline Configuration Updates**:

```elixir
# Critical: Add toilet_capacity to prevent buffering
spec = [
  child(:camera_source, %Membrane.Rpicam.Source{...})
  |> child(:h264_parser, %Membrane.H264.Parser{...})
  |> child(:tee, Membrane.Tee.Parallel)
]

# Annotation branch
annotation_branch = [
  get_child(:tee)
  |> via_in(:input, toilet_capacity: 1)  # CRITICAL: Drop old frames
  |> child(:decoder, %Membrane.H264.FFmpeg.Decoder{...})
  |> child(:annotator, VideoStreamer.AnnotationFilter)
  |> child(:encoder, %Membrane.H264.FFmpeg.Encoder{...})
  # ... rest of pipeline
]
```

3. **Success Criteria Updates**:
- ❌ Remove: "End-to-end latency <300ms"
- ✅ Add: "End-to-end latency <600ms on RPi (adaptive)"
- ✅ Add: "No 'Toilet overflow' errors in logs"
- ✅ Add: "Preview shows current frames with <200ms lag when moving camera"

### Phase 3: Dual RTSP Streams

#### Minor Updates:

1. **Performance Expectations**:
- Original stream: Unchanged (still ≥25 FPS)
- Annotated stream: 2-4 FPS (adaptive, not fixed)

2. **QGC Testing Guide Updates**:
```markdown
### Expected Performance

| Stream | Frame Rate | Latency |
|--------|-----------|---------|
| Original | 25-30 FPS | <100ms |
| Annotated | 2-4 FPS (adaptive) | <600ms |

**Note**: Annotated stream FPS will vary based on CPU load and scene complexity.
This is expected behavior due to adaptive processing.
```

## New Section: Phase 0 Architecture

**ADD** new section after "Project Context":

### Phase 0: Development Pipeline Architecture (Completed)

Phase 0 established the core annotation pipeline on macOS for development and testing.

#### Key Components Developed:
- ✅ `YoloDetector` - Filter with time-based adaptive frame skipping
- ✅ `WebPreview` - Bandit MJPEG server for development monitoring
- ✅ `Pipeline` - Camera → Toilet → YoloDetector → Sink
- ✅ `test_web_preview.exs` - Development start script

#### Proven Architecture Patterns:
1. **Auto flow control** with `toilet_capacity: 1`
2. **Time-based frame skipping** (270ms target on macOS)
3. **Two-level frame dropping** (toilet + time-based)
4. **Frame-ID tracking** for low-latency preview
5. **Evision** for image processing (better than Vix for video)

#### Performance Achieved:
- macOS: 6-7 FPS adaptive processing
- Inference: 130-180ms per frame
- Preview latency: <100ms
- Memory: Stable, no leaks

**Reference Implementation**: `apps/video_annotator/` (Phase 0 code)

**Documentation**:
- [PIPELINE_ARCHITECTURE.md](../apps/video_annotator/PIPELINE_ARCHITECTURE.md)
- [README_PIPELINE.md](../apps/video_annotator/README_PIPELINE.md)
- [PHASE_0_COMPLETE.md](../apps/video_annotator/PHASE_0_COMPLETE.md)

## Timeline Updates

**Recommended Adjustment**:

| Week | Phase | Key Deliverables | **Notes** |
|------|-------|------------------|-----------|
| 0 (Done) | 0 | macOS development pipeline, web preview | ✅ COMPLETE |
| 1-2  | 1 | RPi model setup, adapt Phase 0 code | Use Phase 0 as starting point |
| 3-4  | 2 | Integrate with video-streamer pipeline | Apply Phase 0 patterns |
| 5-6  | 3 | Dual RTSP streams functional | - |
| 7-8  | 4 | Pluggable architecture implemented | - |
| 9-10 | 5 | Performance optimizations complete | - |
| 11-12 | 6 | Testing, documentation, deployment | - |

**Time Saved**: ~2 weeks due to Phase 0 proving the core architecture

## Implementation Strategy Update

### Recommended Approach for Phase 1:

**Instead of starting from scratch, adapt Phase 0 code**:

1. **Copy Phase 0 Components** to video-streamer:
   ```bash
   # Copy proven implementations
   cp apps/video_annotator/lib/video_annotator/yolo_detector.ex \
      apps/video_streamer/lib/video_streamer/annotation_filter.ex
   ```

2. **Adjust Parameters for RPi**:
   - `target_interval_ms`: 270 → 500-600
   - Consider lower resolution input
   - Test with RPi camera format (likely I420, not NV12)

3. **Integration with Video-Streamer**:
   - Replace `Membrane.CameraCapture` with RPi camera source from existing pipeline
   - Use proven toilet + time-based skipping pattern
   - Keep auto flow control throughout

4. **Keep Web Preview** (Optional but Recommended):
   - Useful for RPi development and debugging
   - Can be disabled in production via config
   - Minimal overhead when no clients connected

## Risk Mitigation Updates

### Original Risks - Status Update:

1. **"ONNX Runtime performance on ARM"**
   - ✅ **Mitigated**: Phase 0 proved ONNX works well with Ortex
   - ✅ Performance is acceptable (130-180ms on macOS)
   - ⚠️ RPi will be slower but adaptive skipping handles it

2. **"Membrane pipeline complexity"**
   - ✅ **Mitigated**: Phase 0 proved simple architecture works
   - ✅ Auto flow control + toilet + time-based skipping is sufficient
   - ❌ **Avoid**: Manual flow control (causes issues)

3. **"Frame processing latency"**
   - ✅ **Solved**: Two-level frame dropping prevents lag
   - ✅ Time-based skipping ensures low latency
   - ✅ Adaptive processing handles variable CPU load

### New Risks Identified:

4. **RPi Camera Format Compatibility**
   - **Risk**: RPi camera may use different pixel format than macOS
   - **Mitigation**: Evision supports I420, NV12, RGB - test all formats
   - **Action**: Add format detection in Phase 1

5. **RTSP Integration Complexity**
   - **Risk**: Integrating annotation filter into existing RTSP pipeline
   - **Mitigation**: Use Phase 0 as independent proof-of-concept
   - **Action**: Careful testing during Phase 2 integration

## Summary of Required Changes

### High Priority (Architectural):
1. ✅ Replace manual flow control with auto flow control throughout
2. ✅ Add toilet_capacity: 1 to all frame processing pipelines
3. ✅ Implement time-based skipping instead of frame-count skipping
4. ✅ Update performance targets to realistic 2-4 FPS for RPi
5. ✅ Add Phase 0 architecture section with reference implementation

### Medium Priority (Documentation):
6. ✅ Update success criteria with realistic expectations
7. ✅ Add web preview server to development tools
8. ✅ Document two-level frame dropping strategy
9. ✅ Add troubleshooting section with common issues

### Low Priority (Nice to Have):
10. Consider starting with YOLOX-Nano instead of YOLOv11n
11. Add performance monitoring guidelines
12. Document parameter tuning process

## Next Steps

1. **Review this update document** with team
2. **Update implementation_plan.md** with these changes
3. **Begin Phase 1** using Phase 0 code as foundation
4. **Test on RPi** and adjust `target_interval_ms` as needed
5. **Iterate** based on actual RPi performance

---

**Status**: Ready for implementation plan updates
**Phase 0**: ✅ COMPLETE
**Phase 1**: Ready to start with proven architecture
