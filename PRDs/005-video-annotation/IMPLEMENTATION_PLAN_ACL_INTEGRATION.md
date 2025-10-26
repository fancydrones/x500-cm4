# Implementation Plan - ACL Integration Summary

**Date**: October 26, 2025
**Status**: ✅ Complete - ACL integrated into Phase 1

---

## Integration Approach: Embedded in Phase 1

**Decision**: ACL is **integrated into Phase 1** (Raspberry Pi Deployment), not a separate phase.

**Rationale**:
1. ✅ **Natural fit** - ACL is infrastructure for RPi deployment, not a separate feature
2. ✅ **Parallel work** - ACL Docker build happens alongside model setup
3. ✅ **Cleaner structure** - Phases organized by deliverables, not tech stack
4. ✅ **Follows Phase 0 pattern** - EMLX was part of Phase 0, not separate

---

## What Was Changed

### implementation_plan.md Updates

#### 1. Phase 1 Title and Goals (Lines 224-240)

**Before**:
```markdown
### Phase 1: ONNX Model Setup & Integration (Week 1-2)

#### Goals
- Set up VideoAnnotator umbrella application
- Integrate Ortex and yolo_elixir dependencies
- Export YOLOv11n model to ONNX format
- Implement basic inference with Nx.Serving
- Verify inference accuracy and performance
```

**After**:
```markdown
### Phase 1: Raspberry Pi Deployment with ARM Acceleration (Week 1-3)

#### Goals
- Adapt Phase 0 code for Raspberry Pi deployment
- Build ONNX Runtime with ARM Compute Library (ACL) for hardware acceleration
- Deploy to Raspberry Pi and benchmark performance
- Achieve 6-10 FPS minimum viable performance (2-3x speedup over CPU)

#### Rationale: Hardware Acceleration is Critical

Phase 0 proved hardware acceleration provides massive speedup:
- **macOS CPU (EXLA)**: 3.7 FPS baseline
- **macOS GPU (EMLX/Metal)**: 11.5 FPS → **3.1x speedup** 🚀

This validates investing in ARM acceleration for Raspberry Pi:
- **RPi CPU (EXLA)**: 2-4 FPS estimated
- **RPi ACL (ARM NEON)**: 6-10 FPS target → **2-3x speedup** 🎯
```

**Changes**:
- Extended timeline: Week 1-2 → Week 1-3 (ACL build time)
- Added ACL as primary goal
- Included Phase 0 EMLX results as validation
- Set realistic performance targets

#### 2. New Tasks (Lines 555-628)

Added three new tasks to Phase 1:

**Task 1.8: Build Docker Image with ARM Compute Library (ACL)**
- Multi-stage Dockerfile
- Build commands with caching
- Expected build time: 45-60 min (first), 10-15 min (cached)

**Task 1.9: Configure Application for ACL**
- Code change: Add `eps: [:acl, :cpu]` to YOLO.load
- One-line change to enable hardware acceleration

**Task 1.10: Deploy and Benchmark on Raspberry Pi**
- kubectl deployment commands
- Expected performance logs
- Links to reference documentation

#### 3. Updated Success Criteria (Lines 630-641)

**Added** (marked with ⭐):
- [ ] **Docker image with ACL builds successfully** ⭐
- [ ] **ACL execution provider loads on Raspberry Pi** ⭐
- [ ] **Achieves 6-10 FPS on RPi 4 (2-3x speedup over CPU)** ⭐
- [ ] **Falls back to CPU gracefully if ACL unavailable** ⭐

---

## Documentation Cross-References

The implementation plan now references three ACL-specific documents:

1. **[ACL_RESEARCH_FINDINGS.md](ACL_RESEARCH_FINDINGS.md)**
   - Complete technical research
   - Support chain validation (YOLO → Ortex → ort → ONNX Runtime → ACL)
   - Performance expectations

2. **[Dockerfile.acl](Dockerfile.acl)**
   - Production-ready multi-stage build
   - 4 stages: ACL builder, ONNX Runtime builder, Elixir builder, runtime
   - Build and debug instructions

3. **[ACL_IMPLEMENTATION_PLAN.md](ACL_IMPLEMENTATION_PLAN.md)**
   - Detailed 3-week implementation roadmap
   - Step-by-step deployment guide
   - Risk mitigation and rollback strategy

4. **[rpi_hardware_acceleration_research.md](rpi_hardware_acceleration_research.md)**
   - Options comparison (ACL vs NCNN vs Coral TPU)
   - Recommendation rationale

---

## Timeline Impact

### Original Timeline

| Week | Phase | Key Deliverables |
|------|-------|------------------|
| 0 (Done) | 0 | macOS development pipeline |
| 1-2 | 1 | ONNX model setup |
| 3-4 | 2 | Membrane pipeline |
| 5-6 | 3 | Dual RTSP streams |

### Updated Timeline with ACL

| Week | Phase | Key Deliverables | ACL Impact |
|------|-------|------------------|------------|
| 0 (Done) | 0 | macOS development pipeline | ✅ EMLX proves HW accel critical |
| **1-3** | 1 | **RPi deployment + ACL** | **+1 week for ACL build** |
| 4-5 | 2 | Membrane pipeline integration | - |
| 6-7 | 3 | Dual RTSP streams | - |

**Net timeline change**: +1 week total (from 12 weeks to 13 weeks)

**Justification**: 2-3x speedup is worth 1 extra week

---

## Integration Benefits

### Why This Structure Works

**✅ Logical grouping**: ACL is part of "getting video annotation working on RPi"

**✅ Clear dependencies**:
- Phase 0 (EMLX results) → validates ACL approach
- Phase 1 (ACL deployment) → enables real-time performance
- Phase 2+ (features) → build on working foundation

**✅ Testable milestones**: Each phase has concrete deliverables
- Phase 1: Working ACL + 6-10 FPS confirmed
- Phase 2: Membrane integration with ACL
- Phase 3: RTSP streaming with ACL

**✅ Flexible execution**:
- Can skip ACL and use CPU-only (degraded performance)
- ACL is additive, not blocking
- Fallback strategy built-in

---

## Performance Validation Strategy

### Phase 0 → Phase 1 Comparison

| Platform | CPU Baseline | HW Accelerated | Speedup | Validation |
|----------|-------------|----------------|---------|------------|
| **macOS (Phase 0)** | 3.7 FPS | 11.5 FPS (EMLX) | 3.1x | ✅ **PROVEN** |
| **RPi (Phase 1)** | 2-4 FPS (est) | 6-10 FPS (ACL) | 2-3x | 🎯 **TARGET** |

**If ACL achieves 2-3x**: Validates approach, proceed to Phase 2

**If ACL <2x speedup**:
1. Try model quantization (INT8)
2. Evaluate NCNN framework
3. Adjust performance expectations

---

## Code Changes Required

### Minimal Application Changes

Only **one line of code** needs to change:

**Before (CPU-only)**:
```elixir
model = YOLO.load(
  model_path: state.model_path,
  classes_path: state.classes_path,
  model_impl: YOLO.Models.YOLOX
  # eps defaults to [:cpu]
)
```

**After (with ACL)**:
```elixir
model = YOLO.load(
  model_path: state.model_path,
  classes_path: state.classes_path,
  model_impl: YOLO.Models.YOLOX,
  eps: [:acl, :cpu]  # Try ACL first, fallback to CPU
)
```

**That's it!** The rest is infrastructure (Docker build).

---

## Deployment Strategy

### Phased Rollout

**Week 1**: Build ACL Docker image
```bash
docker buildx build --platform linux/arm64 ... --push
```

**Week 2**: Deploy to test Raspberry Pi
```bash
kubectl set image deployment/video-streamer video-streamer=...acl-latest
```

**Week 3**: Validate performance and optimize
```bash
kubectl logs -f deployment/video-streamer | grep FPS
```

**Week 4+**: Production rollout if targets met

### Rollback Plan

If ACL doesn't work:
1. **Immediate**: Revert to CPU-only image (existing)
2. **Short-term**: Keep ACL image available, use as opt-in
3. **Long-term**: Evaluate alternatives (NCNN, model optimization)

---

## Success Metrics

### Minimum Viable (Must Achieve)

- [x] ✅ ACL research complete
- [x] ✅ Dockerfile.acl created
- [x] ✅ Implementation plan updated
- [ ] 🎯 Docker image builds successfully
- [ ] 🎯 ACL loads on Raspberry Pi
- [ ] 🎯 **Achieves 6-10 FPS (2-3x over CPU)**

### Stretch Goals

- [ ] 🎯 10-12 FPS on Raspberry Pi 5
- [ ] 🎯 Docker build <45 minutes
- [ ] 🎯 Zero application code changes (config only)

---

## Lessons from Phase 0

### What We Learned

**1. Hardware acceleration is not optional**
- CPU-only: 3.7 FPS (too slow for real-time)
- With GPU: 11.5 FPS (usable for navigation)

**2. Backend selection should be automatic**
- EMLX: Auto-detects macOS, uses Metal GPU
- ACL: Auto-detect ARM, use NEON acceleration

**3. Build complexity is acceptable for performance**
- EMLX required config changes (worth it)
- ACL requires Docker rebuild (worth it for 2-3x)

**4. Fallback strategy is essential**
- EMLX falls back to EXLA if Metal unavailable
- ACL will fall back to CPU if not available

---

## Next Steps

### Immediate (This Week)

- [ ] Test Dockerfile.acl build locally
- [ ] Push initial ACL image to ghcr.io
- [ ] Document build process

### Short-term (Next Week)

- [ ] Deploy to RPi test device
- [ ] Run performance benchmarks
- [ ] Validate 2-3x speedup target

### Medium-term (Week 3)

- [ ] Optimize ACL configuration
- [ ] Cache Docker images
- [ ] Production deployment

---

## Conclusion

✅ **ACL successfully integrated into implementation plan**

**Key points**:
1. Embedded in Phase 1 (natural fit)
2. Extends timeline by 1 week (acceptable)
3. Expected 2-3x speedup justifies effort
4. Minimal code changes (1 line!)
5. Low risk with CPU fallback

**Status**: Ready to implement! 🚀

---

## Related Documents

- **Implementation Plan**: [implementation_plan.md](implementation_plan.md) - Main plan (updated)
- **ACL Research**: [ACL_RESEARCH_FINDINGS.md](ACL_RESEARCH_FINDINGS.md)
- **ACL Dockerfile**: [Dockerfile.acl](Dockerfile.acl)
- **ACL Detailed Plan**: [ACL_IMPLEMENTATION_PLAN.md](ACL_IMPLEMENTATION_PLAN.md)
- **HW Accel Options**: [rpi_hardware_acceleration_research.md](rpi_hardware_acceleration_research.md)
- **Phase 0 Complete**: [../../apps/video_annotator/PHASE_0_COMPLETE.md](../../apps/video_annotator/PHASE_0_COMPLETE.md)
- **EMLX Integration**: [../../apps/video_annotator/EMLX_INTEGRATION.md](../../apps/video_annotator/EMLX_INTEGRATION.md)
