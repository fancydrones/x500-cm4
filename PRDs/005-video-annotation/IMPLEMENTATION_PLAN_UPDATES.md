# Implementation Plan Updates - Phase 0 Integration

**Date**: 2025-10-26
**Status**: Implementation plan updated with Phase 0 learnings

## Summary of Changes

The [implementation_plan.md](implementation_plan.md) has been updated to incorporate all critical learnings from Phase 0 (macOS development and testing).

## Key Changes Made

### 1. Added Phase 0 Section

Added complete Phase 0 section documenting:
- ✅ Completed components (YoloDetector, WebPreview, Pipeline)
- ✅ Proven architecture patterns (auto flow control, time-based skipping, toilet_capacity: 1)
- ✅ Performance achieved (6-7 FPS on macOS, <100ms latency)
- ✅ Reference implementation location

**Location**: Lines 18-49 in implementation_plan.md

### 2. Updated Model Choice

**Changed from**: YOLOv11n (untested)
**Changed to**: YOLOX-Nano (proven in Phase 0) with YOLOv11 as future option

**Rationale**: YOLOX-Nano (3.5MB) proven to work excellently in Phase 0

**Location**: Line 16, Lines 268-302

### 3. Updated Dependencies

**Key changes**:
- ✅ `{:yolo, ">= 0.2.0"}` (not yolo_elixir)
- ✅ `{:evision, "~> 0.2"}` (not Vix - better for video)
- ✅ `{:exla, "~> 0.9"}` (CPU backend)
- ✅ Added Bandit + Plug for web preview (development)

**Location**: Lines 242-266

### 4. Updated Performance Targets

**Changed from**: ≥8 FPS on Raspberry Pi 5
**Changed to**: 2-4 FPS adaptive on Raspberry Pi 4/5

**Rationale**: Phase 0 showed 6-7 FPS on macOS (faster than RPi), realistic RPi expectation is 2-4 FPS

**Locations**:
- Line 70 (compatibility goals)
- Line 551 (Phase 1 success criteria)
- Line 901 (Phase 2 success criteria)
- Lines 1148-1160 (QGC testing guide)

### 5. Rewrote AnnotationFilter Implementation

**Critical changes**:
- ❌ **Removed**: Manual flow control (doesn't work with Camera)
- ✅ **Added**: Auto flow control with `flow_control: :auto`
- ✅ **Added**: Time-based adaptive frame skipping (`target_interval_ms: 500`)
- ✅ **Added**: Direct YOLO integration (no Nx.Serving)
- ✅ **Added**: State tracking for adaptive processing

**Location**: Lines 572-697

**Key code patterns from Phase 0**:
```elixir
# Time-based skipping (CRITICAL)
if time_since_last < state.target_interval_ms && state.frame_count > 0 do
  {[buffer: {:output, buffer}], state}  # Skip frame
else
  # Process frame with YOLO.detect()
  # Update last_process_time AFTER processing
end
```

### 6. Added toilet_capacity to Pipeline

**Added**: `|> via_in(:input, toilet_capacity: 1)` before annotation filter

**Rationale**: Essential for two-level frame dropping (proven in Phase 0)

**Location**: Lines 740-742

### 7. Updated Overlay Renderer to Use Evision

**Changed from**: Vix (libvips)
**Changed to**: Evision (OpenCV)

**Rationale**: Evision proven better for video processing in Phase 0

**Location**: Lines 760-823

### 8. Updated Phase 2 Success Criteria

**Added**:
- ✅ End-to-end latency <600ms on RPi (was <300ms)
- ✅ No "Toilet overflow" errors (verify auto flow control)
- ✅ Preview shows current frames with <200ms lag
- ✅ Time-based adaptive skipping verified in logs

**Location**: Lines 896-905

### 9. Updated QGC Testing Guide

**Added**:
- ✅ Expected performance table (2-4 FPS adaptive)
- ✅ TC3: Adaptive Performance test case
- ✅ Notes about FPS variation being expected

**Location**: Lines 1136-1191

### 10. Updated Timeline

**Added**:
- ✅ Week 0 (Done): Phase 0 complete
- ✅ Notes: "Use Phase 0 as starting point"
- ✅ Time saved: ~2 weeks

**Location**: Lines 1211-1221

### 11. Updated Next Steps

**Changed to**:
- ✅ Phase 0 complete (checkbox)
- ✅ Begin Phase 1 using Phase 0 code as foundation
- ✅ Copy proven components from `apps/video_annotator/`
- ✅ Adjust `target_interval_ms` for RPi
- ✅ Apply Phase 0 architecture patterns

**Location**: Lines 1223-1236

## Critical Architecture Decisions

### ✅ DO (Proven in Phase 0)

1. **Use auto flow control** (not manual) - simpler, no compatibility issues
2. **Implement time-based skipping** - essential for low latency
3. **Use toilet_capacity: 1** - prevents old frame processing
4. **Update last_process_time AFTER processing** - not before
5. **Use Evision for video** - better than Vix
6. **Calculate FPS before sending to preview** - ensures accurate stats
7. **Keep web preview for development** - invaluable debugging tool

### ❌ DON'T (Failed in Phase 0)

1. **Don't use manual flow control** - causes toilet overflow with Camera
2. **Don't rely only on toilet** - still processes buffered frames
3. **Don't use frame-count skipping alone** - need time-based for low latency
4. **Don't use Vix for video** - Evision is better
5. **Don't skip web preview** - critical for development/debugging

## Reference Documents

All Phase 0 documentation integrated:
- [PIPELINE_ARCHITECTURE.md](../../apps/video_annotator/PIPELINE_ARCHITECTURE.md)
- [README_PIPELINE.md](../../apps/video_annotator/README_PIPELINE.md)
- [PHASE_0_COMPLETE.md](../../apps/video_annotator/PHASE_0_COMPLETE.md)
- [phase_0_learnings_update.md](phase_0_learnings_update.md)

## Implementation Strategy

**Recommended approach for Phase 1**:

1. **Copy Phase 0 components** to video-streamer:
   ```bash
   cp apps/video_annotator/lib/video_annotator/yolo_detector.ex \
      apps/video_streamer/lib/video_streamer/annotation_filter.ex
   ```

2. **Adjust parameters for RPi**:
   - `target_interval_ms`: 270 → 500-600
   - Test with RPi camera format (I420, not NV12)

3. **Integration with video-streamer**:
   - Replace `Membrane.CameraCapture` with RPi camera source
   - Use proven toilet + time-based skipping pattern
   - Keep auto flow control throughout

4. **Keep web preview** (optional but recommended):
   - Useful for RPi development and debugging
   - Can be disabled in production via config

## Validation

All changes validated against:
- ✅ Phase 0 working implementation
- ✅ Performance measurements (6-7 FPS macOS)
- ✅ Architecture patterns (auto flow + time-based)
- ✅ Troubleshooting learnings (what NOT to do)

## Status

- ✅ Implementation plan fully updated
- ✅ All Phase 0 learnings incorporated
- ✅ Reference documentation linked
- ✅ Ready for Phase 1 implementation

---

**Next Action**: Begin Phase 1 using Phase 0 code as foundation
