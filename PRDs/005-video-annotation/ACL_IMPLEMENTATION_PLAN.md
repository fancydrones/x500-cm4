# ARM Compute Library (ACL) Implementation Plan

**Date**: October 26, 2025
**Status**: Ready to implement
**Prerequisites**: Phase 0 complete, EMLX proves 3.1x speedup possible

---

## Executive Summary

Add ARM Compute Library (ACL) support to achieve **2-3x speedup** on Raspberry Pi, based on learnings from Phase 0 where EMLX provided 3.1x speedup on macOS.

**Timeline**: 6-9 days
**Expected Result**: 2-4 FPS (CPU) → 6-10 FPS (ACL) on Raspberry Pi
**Complexity**: Medium (Docker build changes)
**Risk**: Low (CPU fallback available)

---

## Phase 1: ACL Integration (Week 1-3)

### Revised Goals

Based on Phase 0 success with EMLX:
- ✅ Adapt Phase 0 code for Raspberry Pi
- ✅ Build ONNX Runtime with ACL support
- ✅ Deploy and benchmark on Raspberry Pi
- ✅ Achieve minimum viable 6-10 FPS performance

### Tasks

**1.1 Dockerfile with ACL Support**

**File**: `PRDs/005-video-annotation/Dockerfile.acl` ✅ **COMPLETE**

Multi-stage Docker build:
1. **Stage 1**: Build ARM Compute Library
2. **Stage 2**: Build ONNX Runtime with ACL
3. **Stage 3**: Build Elixir app with custom ONNX Runtime
4. **Stage 4**: Runtime image with rpicam-apps + ACL

**Build command**:
```bash
docker buildx build \
  --platform linux/arm64 \
  --file PRDs/005-video-annotation/Dockerfile.acl \
  --tag ghcr.io/fancydrones/x500-cm4/video-streamer:acl-latest \
  --cache-from type=registry,ref=ghcr.io/fancydrones/x500-cm4/video-streamer:acl-buildcache \
  --cache-to type=registry,ref=ghcr.io/fancydrones/x500-cm4/video-streamer:acl-buildcache,mode=max \
  --push \
  .
```

**Estimated build time**: 45-60 minutes (first build), ~10-15 minutes (cached)

**1.2 Application Configuration**

**File**: `apps/video_annotator/lib/video_annotator/yolo_detector.ex`

Add ACL execution provider:

```elixir
@impl true
def handle_playing(_ctx, state) do
  Logger.info("Loading YOLO model from: #{state.model_path}")
  Logger.info("Using execution providers: [:acl, :cpu]")  # Try ACL first

  model = YOLO.load(
    model_path: state.model_path,
    classes_path: state.classes_path,
    model_impl: YOLO.Models.YOLOX,
    eps: [:acl, :cpu]  # ARM Compute Library with CPU fallback
  )

  # ... rest of initialization
end
```

**1.3 Environment Configuration**

**File**: `config/runtime.exs` or Dockerfile ENV

```elixir
# config/runtime.exs
if config_env() == :prod and System.get_env("USE_ACL") == "true" do
  config :ortex, Ortex.Native,
    onnxruntime_strategy: :system,
    onnxruntime_lib_dir: "/usr/local/lib",
    onnxruntime_include_dir: "/usr/local/include"
end
```

Or in Dockerfile:
```dockerfile
ENV USE_ACL=true
ENV ONNXRUNTIME_STRATEGY=system
ENV ONNXRUNTIME_LIB_DIR=/usr/local/lib
```

**1.4 Testing & Benchmarking**

Create benchmark script for Raspberry Pi:

**File**: `apps/video_annotator/test_rpi_acl_benchmark.exs`

```elixir
# Benchmark ACL vs CPU on Raspberry Pi

IO.puts """
=======================================================================
Raspberry Pi ACL Benchmark
=======================================================================
"""

# Test with ACL
System.put_env("USE_ACL", "true")
acl_fps = run_benchmark(eps: [:acl, :cpu])

# Test with CPU only
System.put_env("USE_ACL", "false")
cpu_fps = run_benchmark(eps: [:cpu])

IO.puts """
=======================================================================
RESULTS
=======================================================================

CPU-only: #{cpu_fps} FPS
ACL:      #{acl_fps} FPS
Speedup:  #{Float.round(acl_fps / cpu_fps, 2)}x

Expected: 2-3x speedup
Status:   #{if acl_fps / cpu_fps >= 2.0, do: "✅ PASS", else: "❌ NEEDS TUNING"}
=======================================================================
"""
```

---

## Implementation Steps

### Step 1: Build Docker Image with ACL (2-3 days)

```bash
# Navigate to project root
cd /Users/royveshovda/src/fancydrones/x500-cm4

# Copy Dockerfile to apps/video_streamer
cp PRDs/005-video-annotation/Dockerfile.acl apps/video_streamer/Dockerfile.acl

# Build for ARM64 (requires Docker Buildx)
docker buildx create --use --name arm-builder

docker buildx build \
  --platform linux/arm64 \
  --file apps/video_streamer/Dockerfile.acl \
  --tag ghcr.io/fancydrones/x500-cm4/video-streamer:acl-test \
  --load \
  apps/video_streamer

# If successful, push to registry
docker buildx build \
  --platform linux/arm64 \
  --file apps/video_streamer/Dockerfile.acl \
  --tag ghcr.io/fancydrones/x500-cm4/video-streamer:acl-$(git rev-parse --short HEAD) \
  --tag ghcr.io/fancydrones/x500-cm4/video-streamer:acl-latest \
  --push \
  apps/video_streamer
```

**Troubleshooting**:
- If build fails: Check ACL version compatibility
- If ONNX Runtime build fails: Increase Docker memory limit
- If link errors: Verify ACL libraries copied correctly

### Step 2: Update Application Code (1 day)

1. Add `:acl` to execution providers list
2. Configure Ortex for system ONNX Runtime
3. Update deployment manifests
4. Test locally (will use CPU without ARM hardware)

### Step 3: Deploy to Raspberry Pi (1 day)

```bash
# Update deployment YAML
kubectl set image deployment/video-streamer \
  video-streamer=ghcr.io/fancydrones/x500-cm4/video-streamer:acl-latest

# Watch rollout
kubectl rollout status deployment/video-streamer

# Check logs
kubectl logs -f deployment/video-streamer | grep -E "(ACL|execution provider)"
```

Expected log output:
```
[info] Using execution providers: [:acl, :cpu]
[info] Loaded model with [:acl] execution providers
```

Or fallback:
```
[warn] ACL execution provider not available, falling back to CPU
[info] Loaded model with [:cpu] execution providers
```

### Step 4: Benchmark Performance (1 day)

Run on actual Raspberry Pi hardware:

```bash
# SSH to Raspberry Pi or exec into pod
kubectl exec -it deployment/video-streamer -- sh

# Run benchmark (if we add benchmark script to image)
/app/bin/video_streamer rpc "VideoAnnotator.Benchmark.run()"
```

Manual testing:
1. Start video stream with ACL
2. Monitor FPS in logs
3. Compare to CPU-only baseline
4. Validate 2-3x speedup

### Step 5: Optimization & Tuning (1-2 days)

If performance is below expectations:

**Option A: ACL Tuning**
- Enable fast math: `eps: [acl: [enable_fast_math: true], :cpu]`
- Adjust thread count
- Profile with `perf` on RPi

**Option B: Model Optimization**
- INT8 quantization (if ACL not sufficient)
- Smaller model (YOLOX-Tiny)
- Lower input resolution (640→416)

---

## Success Criteria

### Minimum Viable (Must Achieve)
- ✅ Docker build completes successfully
- ✅ ACL execution provider loads without errors
- ✅ Achieves **6-10 FPS** on Raspberry Pi 4 (2-3x over CPU)
- ✅ Falls back to CPU gracefully if ACL unavailable

### Stretch Goals
- 🎯 **10-12 FPS** on Raspberry Pi 5
- 🎯 Docker build time <45 minutes
- 🎯 Cached builds <15 minutes
- 🎯 Zero application code changes (just config)

---

## Performance Expectations

### Based on Phase 0 EMLX Results

| Platform | CPU Baseline | With HW Accel | Speedup | Status |
|----------|--------------|---------------|---------|--------|
| **macOS** | 3.7 FPS | 11.5 FPS (EMLX) | 3.1x | ✅ Proven |
| **RPi 4** | 2-4 FPS (est) | 6-10 FPS (ACL) | 2-3x | 🎯 Target |
| **RPi 5** | 3-5 FPS (est) | 10-12 FPS (ACL) | 3x | 🎯 Stretch |

### Comparison to Alternatives

| Option | Speedup | Effort | Cost | Verdict |
|--------|---------|--------|------|---------|
| **ACL** ⭐ | 2-3x | Medium | $0 | **Recommended** |
| NCNN | 2-3x | High | $0 | Fallback |
| Coral TPU | 10-20x | High | $60-75 | Future R&D |
| Model quantization | 2x | Low | $0 | Combine with ACL |

---

## Risk Mitigation

### Technical Risks

| Risk | Mitigation |
|------|------------|
| ACL build fails | Use prebuilt ONNX Runtime binaries (without ACL) |
| Slower than expected | Combine with model quantization (INT8) |
| Compatibility issues | Test on actual RPi hardware early |
| Long build times | Cache built image in registry |

### Rollback Strategy

If ACL doesn't work:
1. **Immediate**: Use CPU-only Docker image (existing)
2. **Short-term**: Try model quantization
3. **Medium-term**: Evaluate NCNN framework
4. **Long-term**: Consider Coral TPU for specific use cases

---

## Timeline

| Week | Tasks | Deliverables |
|------|-------|--------------|
| **Week 1** | Dockerfile creation, build setup | Working ACL Docker build |
| **Week 2** | Deploy to RPi, benchmark | Performance measurements |
| **Week 3** | Optimization, documentation | Production-ready ACL support |

**Total**: 3 weeks to production-ready ACL integration

---

## Deployment Checklist

### Before Deployment
- [ ] Dockerfile.acl tested and building successfully
- [ ] Docker image cached in registry (ghcr.io)
- [ ] Application code updated with `:acl` EP
- [ ] Deployment YAML updated with new image tag
- [ ] Rollback plan documented

### During Deployment
- [ ] Build ARM64 image with ACL
- [ ] Push to registry
- [ ] Update deployment
- [ ] Monitor logs for ACL initialization
- [ ] Verify no errors in pod logs

### After Deployment
- [ ] Benchmark FPS (expect 6-10 FPS)
- [ ] Compare to CPU baseline (expect 2-3x)
- [ ] Monitor memory usage
- [ ] Check for crashes/restarts
- [ ] Document actual performance

---

## Documentation Updates

After successful ACL integration:

1. **Update** [rpi_hardware_acceleration_research.md](rpi_hardware_acceleration_research.md)
   - Add "COMPLETED" status
   - Document actual vs expected performance
   - Include lessons learned

2. **Update** [implementation_plan.md](implementation_plan.md)
   - Mark Phase 1 as complete
   - Update performance targets based on results
   - Add ACL as proven acceleration method

3. **Create** [ACL_DEPLOYMENT_GUIDE.md](ACL_DEPLOYMENT_GUIDE.md)
   - Step-by-step deployment instructions
   - Troubleshooting common issues
   - Performance tuning guide

---

## Next Steps

### Immediate (This Week)
- [x] Research ACL support ✅ **COMPLETE**
- [x] Create Dockerfile.acl ✅ **COMPLETE**
- [ ] Test Docker build locally (on macOS, will use qemu)
- [ ] Push initial image to registry

### Short-term (Next Week)
- [ ] Deploy to Raspberry Pi 4 test device
- [ ] Run performance benchmarks
- [ ] Compare ACL vs CPU performance
- [ ] Document results

### Medium-term (Week 3)
- [ ] Optimize ACL configuration if needed
- [ ] Cache Docker images for faster builds
- [ ] Update deployment manifests
- [ ] Production rollout

---

## References

### Documentation Created
- [ACL_RESEARCH_FINDINGS.md](ACL_RESEARCH_FINDINGS.md) - Comprehensive research
- [Dockerfile.acl](Dockerfile.acl) - Multi-stage ACL Docker build
- [rpi_hardware_acceleration_research.md](rpi_hardware_acceleration_research.md) - Options analysis

### External Resources
- **ONNX Runtime ACL EP**: https://onnxruntime.ai/docs/execution-providers/community-maintained/ACL-ExecutionProvider.html
- **ARM Compute Library**: https://github.com/ARM-software/ComputeLibrary
- **ort (Rust)**: https://docs.rs/ort
- **Phase 0 Complete**: [../../apps/video_annotator/PHASE_0_COMPLETE.md](../../apps/video_annotator/PHASE_0_COMPLETE.md)

---

## Conclusion

✅ **ACL integration plan is complete and ready to execute**

**Key Points**:
1. Phase 0 proved hardware acceleration provides 3.1x speedup
2. ACL is the best option for Raspberry Pi (low effort, good ROI)
3. Docker build is complex but well-documented
4. Expected 2-3x speedup will enable real-time navigation
5. Low risk with CPU fallback strategy

**Next Action**: Build and test Dockerfile.acl on ARM64 hardware

**Timeline**: 3 weeks to production-ready ARM acceleration 🚀
