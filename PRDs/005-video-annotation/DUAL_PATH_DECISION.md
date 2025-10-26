# Dual-Path Pipeline Decision

**Date**: October 26, 2025
**Status**: ✅ Approved - Postponed until after ACL integration
**Priority**: Phase 1.5 (after Phase 1 ACL completion)

---

## Decision Summary

**Implement dual-path pipeline with server-side overlay for RTSP streaming**

**Timeline**: After ACL integration (Phase 1.5)

**Architecture**: Server-side rendering (not client-side JavaScript)

**Rationale**: Support QGroundControl (QGC) with dual RTSP streams

---

## User Requirements

### Critical Requirements

1. ✅ **Smooth 30 FPS video for pilot** - Essential for drone navigation
2. ✅ **Annotations visible** - Detection boxes overlaid on video stream
3. ✅ **QGroundControl compatible** - Must work with standard RTSP streams
4. ✅ **No JavaScript client needed** - QGC uses native RTSP, not web browser

### Future Requirements

🔮 **Separate detection output for autonomous navigation** - Processed frames may have independent output in the future for onboard autopilot decision-making

---

## Architecture: Server-Side Dual-Path with RTSP

### High-Level Design

```
┌────────────────────────────────────────────────────────────┐
│                   Raspberry Pi Camera                       │
│                      (30 FPS NV12)                          │
└──────────────────────┬─────────────────────────────────────┘
                       │
                       │ Membrane.Tee (split stream)
                       │
        ┌──────────────┴──────────────┐
        │                              │
        ▼                              ▼
┌───────────────────┐        ┌─────────────────────┐
│  Original Path    │        │   Detection Path    │
│    (30 FPS)       │        │     (2-4 FPS)       │
├───────────────────┤        ├─────────────────────┤
│ • H.264 encode    │        │ • Toilet (drop old) │
│ • No processing   │        │ • YOLO detection    │
│ • Direct to RTP   │        │ • Generate boxes    │
└────────┬──────────┘        └──────────┬──────────┘
         │                              │
         │                              ▼
         │                    ┌──────────────────┐
         │                    │ Annotation Path  │
         │                    │   (2-4 FPS)      │
         │                    ├──────────────────┤
         │                    │ • Decode H.264   │
         │                    │ • Draw boxes     │
         │                    │ • Re-encode H.264│
         │                    └────────┬─────────┘
         │                             │
         └─────────────────┬───────────┘
                           ▼
                  ┌─────────────────┐
                  │  RTSP Server    │
                  │  (Two streams)  │
                  ├─────────────────┤
                  │ • /video (30 FPS, original)
                  │ • /video_annotated (2-4 FPS, boxes)
                  └─────────────────┘
                           │
                           ▼
                  ┌─────────────────┐
                  │  QGroundControl │
                  │  (Two widgets)  │
                  ├─────────────────┤
                  │ Widget 1: Original (smooth piloting)
                  │ Widget 2: Annotated (object detection)
                  └─────────────────┘
```

### Key Design Decisions

#### 1. Server-Side Rendering (Not Client-Side)

**Decision**: Render annotations on the drone/server, not in QGC

**Rationale**:
- ✅ **QGC compatibility** - Works with standard RTSP streams
- ✅ **No custom client** - QGC doesn't need modifications
- ✅ **Network efficiency** - Send compressed H.264, not raw frames + JSON
- ✅ **Consistent rendering** - Same appearance on all clients

**Trade-off**:
- ⚠️  More complex Membrane pipeline (decode → draw → re-encode)
- ⚠️  Additional CPU cost for re-encoding (acceptable with ACL)

#### 2. Dual RTSP Streams (Not Single Stream with Overlay)

**Decision**: Provide two separate RTSP streams

**Rationale**:
- ✅ **Pilot choice** - Can view original OR annotated OR both
- ✅ **Bandwidth flexibility** - Can disable annotated stream to save bandwidth
- ✅ **Original quality** - No performance degradation on main navigation stream
- ✅ **Independent frame rates** - 30 FPS original, 2-4 FPS annotated

**Trade-off**:
- ⚠️  Slightly higher bandwidth if both streams used simultaneously
- ⚠️  Need dual video widgets in QGC

#### 3. Postpone Until After ACL

**Decision**: Implement in Phase 1.5, after ACL integration complete

**Rationale**:
- ✅ **ACL is foundation** - Need hardware acceleration working first
- ✅ **Validate performance** - Ensure 2-4 FPS is achievable on RPi
- ✅ **Incremental complexity** - Don't tackle two big changes at once
- ✅ **Clear testing** - Test ACL, then add dual-path

**Timeline**:
- Phase 1 (Weeks 1-3): ACL integration → 2-4 FPS on RPi
- Phase 1.5 (Week 4): Dual-path → 30 FPS original + 2-4 FPS annotated
- Phase 2 (Weeks 5-6): Continue with features

---

## Implementation Plan (Phase 1.5)

### Task 1.5.1: Extend Pipeline with Tee

**File**: `apps/video_streamer/lib/video_streamer/pipeline.ex`

```elixir
defmodule VideoStreamer.Pipeline do
  use Membrane.Pipeline

  @impl true
  def handle_init(_ctx, opts) do
    spec = [
      # Camera source
      child(:camera, %Membrane.Rpicam.Source{
        width: 1552,
        height: 1552,
        framerate: 30
      })
      |> child(:h264_parser, %Membrane.H264.Parser{
        output_alignment: :nalu,
        generate_best_effort_timestamps: %{framerate: {30, 1}},
        repeat_parameter_sets: true
      })
      |> child(:tee, Membrane.Tee.Parallel)
    ]

    # Original path (30 FPS) - Direct to RTSP
    spec = spec ++ [
      get_child(:tee)
      |> via_out(Pad.ref(:output, 0))
      # No processing, direct to RTP packaging
      |> child(:rtp_original, %Membrane.RTP.StreamSendBin{
        payloader: %Membrane.RTP.H264.Payloader{max_payload_size: 1200},
        payload_type: 96
      })
      # ... RTSP sink for /video
    ]

    # Annotation path (2-4 FPS) - Process and re-encode
    spec = spec ++ [
      get_child(:tee)
      |> via_out(Pad.ref(:output, 1))
      # Decode for annotation
      |> child(:decoder, %Membrane.H264.FFmpeg.Decoder{
        framerate: {30, 1}
      })
      # Drop old frames (2-4 FPS processing)
      |> via_in(:input, toilet_capacity: 1)
      # Annotate with YOLO
      |> child(:annotator, %VideoStreamer.AnnotationFilter{
        model_path: opts[:model_path],
        classes_path: opts[:classes_path],
        eps: [:acl, :cpu]  # Use ACL acceleration
      })
      # Re-encode for RTSP
      |> child(:encoder, %Membrane.H264.FFmpeg.Encoder{
        preset: :fast,
        profile: :baseline
      })
      |> child(:rtp_annotated, %Membrane.RTP.StreamSendBin{
        payloader: %Membrane.RTP.H264.Payloader{max_payload_size: 1200},
        payload_type: 96
      })
      # ... RTSP sink for /video_annotated
    ]

    {[spec: spec], %{}}
  end
end
```

### Task 1.5.2: Update AnnotationFilter for Server-Side Rendering

**File**: `apps/video_streamer/lib/video_streamer/annotation_filter.ex`

Based on Phase 0 proven architecture:
- Auto flow control (not manual)
- Time-based adaptive frame skipping
- Server-side annotation drawing with Evision
- Output annotated raw frames (not metadata)

See [Phase 0 implementation](../../apps/video_annotator/lib/video_annotator/yolo_detector.ex) for reference.

### Task 1.5.3: RTSP Server Dual-Path Support

Already planned in Phase 3 - no additional work needed!

**File**: `apps/video_streamer/lib/video_streamer/rtsp/protocol.ex`

```elixir
def handle_request("DESCRIBE", %{path: path}, state) do
  case path do
    "/video" ->
      # SDP for original stream (30 FPS)
      sdp = generate_sdp(stream_type: :original)
      {:reply, describe_response(sdp), state}

    "/video_annotated" ->
      # SDP for annotated stream (2-4 FPS)
      sdp = generate_sdp(stream_type: :annotated)
      {:reply, describe_response(sdp), state}

    _ ->
      {:reply, not_found_response(), state}
  end
end
```

---

## Performance Impact

### CPU/GPU Usage

**Original path** (30 FPS):
- Camera capture: Minimal
- H.264 encode: Hardware accelerated (Raspberry Pi encoder)
- Total CPU: ~5-10%

**Annotation path** (2-4 FPS with ACL):
- Decode: ~5% CPU
- YOLO detection: ~15-20% CPU (with ACL acceleration)
- Annotation drawing: ~5% CPU
- Re-encode: ~10% CPU
- Total CPU: ~35-40%

**Combined**: ~45-50% CPU (acceptable on RPi 4/5)

### Network Bandwidth

**Original stream** (30 FPS):
- Resolution: 1552x1552
- Bitrate: ~4-6 Mbps
- Bandwidth: 6 Mbps

**Annotated stream** (2-4 FPS):
- Resolution: 1552x1552 (or 640x640 for lower bandwidth)
- Bitrate: ~1-2 Mbps
- Bandwidth: 2 Mbps

**Total**: ~8 Mbps (acceptable on WiFi)

**Optimization**: Can reduce annotated stream to 640x640 to save bandwidth (boxes still visible)

---

## QGroundControl Integration

### Video Widget Configuration

**QGC supports dual video widgets** - Pilot can view both streams simultaneously:

**Widget 1**: Original stream (primary, for piloting)
- URL: `rtsp://10.5.0.26:8554/video`
- Purpose: Smooth 30 FPS navigation
- Position: Main/full screen

**Widget 2**: Annotated stream (secondary, for awareness)
- URL: `rtsp://10.5.0.26:8554/video_annotated`
- Purpose: Object detection overlay
- Position: Picture-in-picture or side panel

### User Experience

**During flight**:
1. Pilot navigates using smooth 30 FPS original stream
2. Annotated stream shows detected objects (trees, buildings, people)
3. Annotations slightly delayed (250-500ms) but still useful for situational awareness

**Bandwidth management**:
- Disable annotated stream if bandwidth limited
- Original stream always available at full quality

---

## Future: Autonomous Navigation Output

### Planned Enhancement (Future PRD)

**Detection data output for autopilot**:

```
Detection Path
    ↓
YOLO Detector
    ├──→ Annotated video (for pilot)
    └──→ Detection metadata (for autopilot)
         ├─→ Object positions (x, y, z)
         ├─→ Object classifications
         ├─→ Confidence scores
         └─→ Collision risk assessment
              ↓
         Autopilot system
         (obstacle avoidance, path planning)
```

**Considerations for future**:
- Separate output sink for detection metadata (JSON/Protobuf)
- Low-latency data path (< 100ms)
- Integration with MAVLink for autopilot commands
- Higher detection rate for autonomous mode (10-15 FPS target)

**Not in scope for current PRD** - focus on pilot-visible annotations first

---

## Testing Strategy

### Phase 1.5 Testing Checklist

**Functional Testing**:
- [ ] Both RTSP streams accessible simultaneously
- [ ] Original stream maintains 30 FPS
- [ ] Annotated stream shows 2-4 FPS with boxes
- [ ] Annotations drawn correctly with Evision
- [ ] QGC can display both streams in dual widgets

**Performance Testing**:
- [ ] CPU usage < 50% with both streams active
- [ ] Network bandwidth < 10 Mbps total
- [ ] No frame drops on original stream
- [ ] Annotations appear within 500ms of detection

**Integration Testing**:
- [ ] Works with existing Phase 0 YoloDetector code
- [ ] ACL acceleration applies to annotation path
- [ ] Toilet drops frames correctly on annotation path
- [ ] No interference between paths (original stays smooth)

**QGC Testing**:
- [ ] Original stream viewable in QGC
- [ ] Annotated stream viewable in QGC
- [ ] Dual widgets displayable simultaneously
- [ ] Can switch between streams during flight

---

## Success Criteria

### Minimum Viable (Must Achieve)

- [ ] Original stream: **30 FPS** smooth video
- [ ] Annotated stream: **2-4 FPS** with visible detection boxes
- [ ] Both streams accessible via RTSP
- [ ] QGC compatibility verified
- [ ] CPU usage < 50%

### Stretch Goals

- [ ] Annotated stream: **4-6 FPS** (with optimizations)
- [ ] Total bandwidth < 8 Mbps (compress annotated stream)
- [ ] CPU usage < 40%
- [ ] Annotation latency < 300ms

---

## Estimated Effort

### Implementation Timeline

**Week 4 (Phase 1.5)**: ~5-6 days

| Task | Effort | Notes |
|------|--------|-------|
| Pipeline Tee integration | 1 day | Add Membrane.Tee.Parallel |
| AnnotationFilter adaptation | 2 days | Server-side rendering with Evision |
| Testing & debugging | 1-2 days | Dual stream testing, QGC validation |
| Documentation | 1 day | Update deployment guides |

**Total**: 5-6 days after ACL completion

---

## Risk Assessment

### Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Re-encode CPU overhead | Medium | Medium | Use hardware encoder if available |
| Annotation path affects original | Low | High | Separate pipelines with Tee isolation |
| Bandwidth too high | Low | Medium | Compress annotated stream to 640x640 |
| QGC compatibility issues | Low | High | Test early with actual QGC |

### Rollback Strategy

If dual-path doesn't work:
1. **Immediate**: Disable annotated stream, keep original only
2. **Short-term**: Provide annotated as optional feature flag
3. **Long-term**: Consider alternative rendering approaches

---

## Dependencies

### Prerequisite: Phase 1 (ACL Integration)

**Must complete first**:
- ✅ ACL Docker build working
- ✅ Achieving 2-4 FPS on Raspberry Pi
- ✅ YOLO detection proven on RPi hardware
- ✅ Evision annotation drawing working

**Why**: Dual-path adds complexity - need solid foundation first

### Integration Points

**Membrane components**:
- `Membrane.Tee.Parallel` - Built-in (no new dep)
- `Membrane.H264.FFmpeg.Decoder` - Already in use
- `Membrane.H264.FFmpeg.Encoder` - Already in use

**Application components**:
- Phase 0 YoloDetector - Reuse for AnnotationFilter
- RTSP server - Already planned for dual paths (Phase 3)

---

## Documentation Updates

### After Implementation

**Update these documents**:
1. [implementation_plan.md](implementation_plan.md) - Add Phase 1.5 details
2. [PIPELINE_ARCHITECTURE.md](../../apps/video_annotator/PIPELINE_ARCHITECTURE.md) - Dual-path diagram
3. Deployment guide - QGC configuration instructions
4. Performance benchmarks - Dual-path metrics

**Create new**:
5. QGC_DUAL_STREAM_GUIDE.md - Step-by-step QGC setup

---

## Comparison: Web Preview vs QGC RTSP

| Feature | Web Preview (Phase 0) | QGC RTSP (Phase 1.5) |
|---------|----------------------|----------------------|
| **Client** | Web browser (dev only) | QGroundControl (production) |
| **Protocol** | MJPEG + WebSocket | Dual RTSP |
| **Rendering** | Client-side Canvas | Server-side Evision |
| **Use case** | Development/debugging | Drone piloting |
| **Complexity** | Medium | Medium |
| **Performance** | 30 FPS preview possible | 30 FPS original guaranteed |

Both approaches valid for different contexts!

---

## Related Documents

**Analysis**:
- [DUAL_PATH_PIPELINE_ANALYSIS.md](DUAL_PATH_PIPELINE_ANALYSIS.md) - Complete analysis of options

**Implementation**:
- [implementation_plan.md](implementation_plan.md) - Main plan (will update)
- [ACL_IMPLEMENTATION_PLAN.md](ACL_IMPLEMENTATION_PLAN.md) - Prerequisite

**Reference**:
- [Phase 0 YoloDetector](../../apps/video_annotator/lib/video_annotator/yolo_detector.ex) - Reuse for AnnotationFilter
- [PIPELINE_ARCHITECTURE.md](../../apps/video_annotator/PIPELINE_ARCHITECTURE.md) - Phase 0 architecture

---

## Conclusion

✅ **Dual-path pipeline approved for Phase 1.5**

**Key decisions**:
1. **Server-side rendering** - QGC compatibility over client-side overlay
2. **Dual RTSP streams** - Pilot choice between original and annotated
3. **Postpone until after ACL** - Solid foundation first
4. **Future autonomous output** - Detection metadata for autopilot (future PRD)

**Timeline**: Implement in Week 4, after ACL proven (5-6 days)

**Expected result**:
- Original: 30 FPS smooth video for piloting ✅
- Annotated: 2-4 FPS with detection boxes ✅
- QGC compatible: Standard RTSP, no mods needed ✅

**Next action**: Complete Phase 1 (ACL), then return to this for Phase 1.5 🚀

---

**Status**: 📋 **DOCUMENTED - Ready for Phase 1.5 implementation**
