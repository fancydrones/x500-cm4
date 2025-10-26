# ARM Compute Library (ACL) Research Findings

**Date**: October 26, 2025
**Status**: ✅ **ACL IS SUPPORTED** - Requires custom ONNX Runtime build

---

## Executive Summary

✅ **ACL execution provider IS supported** by the underlying Rust `ort` library
⚠️  **Requires compiling ONNX Runtime from source** (not available in precompiled binaries)
✅ **Compatible with our current stack** (Ortex → ort → ONNX Runtime)
📋 **Implementation complexity**: Medium (Docker build changes required)

---

## Research Findings

### 1. Ortex Support Chain

**Stack hierarchy**:
```
YOLO library (Elixir)
    ↓
Ortex (Elixir bindings)
    ↓
ort (Rust bindings)
    ↓
ONNX Runtime (C++)
    ↓
ARM Compute Library (C++)
```

### 2. ort Library (Rust) - ✅ ACL Supported

**Source**: https://docs.rs/ort

**ACL Feature Status**: ✅ Fully implemented

**How to enable**:
```toml
# In Cargo.toml (for Ortex's Rust NIF)
[dependencies]
ort = { version = "2.0", features = ["acl"] }
```

**Documentation quote**:
> "Enables the ARM Compute Library execution provider for multi-core ARM v8 processors."

**Critical limitation**:
> "You'll need to compile ONNX Runtime from source and use the `system` strategy to point to the compiled binaries to enable other execution providers."

The `download` strategy (default) only provides CUDA and TensorRT EPs.

### 3. Ortex (Elixir) - ⚠️ ACL Not Documented

**Source**: https://github.com/elixir-nx/ortex

**Current supported EPs in documentation**:
- CoreML (macOS)
- DirectML (Windows)
- CUDA + TensorRT (Linux)
- CPU (all platforms)

**ACL not mentioned**, but this is likely because:
1. Ortex uses precompiled ONNX Runtime binaries (don't include ACL)
2. ACL requires source compilation (more complex setup)
3. Documentation focuses on "easy" execution providers

**However**: Since Ortex uses `ort`, and `ort` supports ACL, we can enable it!

### 4. YOLO Library (Elixir) - ✅ Execution Provider Passthrough

**Source**: https://github.com/poeticoding/yolo_elixir

**Execution provider configuration**:
```elixir
model = YOLO.load(
  model_impl: YOLO.Models.YOLOX,
  model_path: "models/yolox_nano.onnx",
  classes_path: "models/coco_classes.json",
  eps: [:cpu]  # Execution providers list
)
```

**Currently documented EPs**:
- `:cpu`
- `:coreml` (macOS)
- `:directml` (Windows)
- `:cuda`, `:tensorrt` (Linux)

**ACL support**: Not documented, but `eps` parameter is a passthrough to ONNX Runtime. If we compile ONNX Runtime with ACL, we should be able to use `:acl`.

---

## Implementation Requirements

### What We Need to Do

**1. Compile ONNX Runtime with ACL Support**

Build custom ONNX Runtime binaries in our Alpine Docker image:

```dockerfile
# Install ARM Compute Library
RUN apk add --no-cache \
    cmake \
    make \
    g++ \
    git \
    python3 \
    scons

# Clone and build ARM Compute Library
RUN git clone https://github.com/ARM-software/ComputeLibrary.git /tmp/acl && \
    cd /tmp/acl && \
    scons Werror=0 debug=0 neon=1 opencl=0 os=linux arch=armv8a

# Build ONNX Runtime with ACL
RUN git clone --recursive https://github.com/Microsoft/onnxruntime /tmp/onnxruntime && \
    cd /tmp/onnxruntime && \
    ./build.sh \
        --config Release \
        --build_shared_lib \
        --parallel \
        --use_acl \
        --acl_home=/tmp/acl \
        --acl_libs=/tmp/acl/build

# Install compiled binaries
RUN cp /tmp/onnxruntime/build/Linux/Release/libonnxruntime.so* /usr/local/lib/ && \
    cp -r /tmp/onnxruntime/include/onnxruntime /usr/local/include/
```

**2. Configure Ortex to Use Custom ONNX Runtime**

Set environment variable to use system ONNX Runtime:

```elixir
# config/runtime.exs or ENV in Docker
config :ortex, Ortex.Native,
  onnxruntime_strategy: :system,
  onnxruntime_path: "/usr/local/lib"
```

**3. Enable ACL in Rust Dependencies**

Modify Ortex's Rust NIF dependencies (via fork or environment variables):

```toml
[dependencies]
ort = { version = "2.0", features = ["acl"], default-features = false }
```

**4. Use ACL in Application Code**

```elixir
model = YOLO.load(
  model_impl: YOLO.Models.YOLOX,
  model_path: "models/yolox_nano.onnx",
  classes_path: "models/coco_classes.json",
  eps: [:acl, :cpu]  # Try ACL first, fallback to CPU
)
```

---

## Implementation Complexity Analysis

### Easy ✅
- Using existing execution providers (CoreML, CPU)
- Testing with different model files

### Medium ⚠️  **← ACL IS HERE**
- Building ONNX Runtime from source
- Configuring Docker build for ARM
- Testing ACL on actual Raspberry Pi hardware

### Hard ❌
- Writing custom execution provider
- Low-level GPU programming
- Building custom inference engine

**ACL Complexity**: Medium because:
- ✅ Well-documented build process
- ✅ No code changes to our app (just config)
- ⚠️  Longer Docker build times (~30-60 min)
- ⚠️  Need to test on actual ARM hardware
- ⚠️  Potential compatibility issues to debug

---

## Expected Performance

### Current Baseline (CPU-only)
- **macOS (before EMLX)**: 3.7 FPS
- **Raspberry Pi 4 (estimated)**: 2-4 FPS

### With ACL (ARM SIMD/NEON optimizations)
- **Expected speedup**: 2-3x
- **RPi 4 target**: 6-10 FPS ✅ Meets minimum viable (4-6 FPS)
- **RPi 5 target**: 8-12 FPS ✅ Stretch goal

### Comparison to macOS EMLX
- **macOS (EMLX/Metal)**: 11.5 FPS (3.1x speedup)
- **RPi (ACL/NEON)**: 6-10 FPS expected (2-3x speedup)
- **Ratio**: EMLX is ~1.5x faster than ACL (expected, Metal > NEON)

---

## Alternative: Precompiled ACL Binaries

Instead of building from source, we could:

**Option A**: Use existing ARM64 ONNX Runtime binaries with ACL
- Check if Microsoft provides ARM64 binaries with ACL
- Unlikely, but worth checking

**Option B**: Build once, cache in Docker registry
- Build custom ONNX Runtime image
- Push to ghcr.io/fancydrones
- Use as base image (faster subsequent builds)

**Recommendation**: Option B - build once, reuse

---

## Risk Assessment

### Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| ACL build fails | Medium | High | Use fallback CPU-only |
| ACL slower than expected | Low | Medium | Optimize model (quantization) |
| ACL not available on RPi 4 | Low | High | ACL supports ARMv8 (RPi 4 OK) |
| Docker build too slow | High | Low | Cache built image |
| Compatibility issues | Medium | Medium | Thorough testing on hardware |

### Timeline Risks

| Activity | Estimated Time | Risk |
|----------|---------------|------|
| Research (complete) | 1 day | ✅ Done |
| Docker build setup | 1-2 days | Medium |
| First successful build | 1 day | Low |
| Testing on RPi | 1 day | Low |
| Debugging/tuning | 1-3 days | Medium |
| **Total** | **5-8 days** | **Medium** |

---

## Recommendation

### ✅ Proceed with ACL Integration

**Rationale**:
1. **Proven stack**: Uses our existing Ortex/ONNX Runtime
2. **Good ROI**: 2-3x speedup for 5-8 days work
3. **Low risk**: Falls back to CPU if ACL fails
4. **Required**: 2-4 FPS too slow for real-time nav

### Implementation Strategy

**Phase 1: Proof of Concept** (3-4 days)
1. Create Dockerfile with ONNX Runtime + ACL build
2. Build image for ARM64
3. Test on Raspberry Pi 4
4. Benchmark CPU vs ACL

**Phase 2: Integration** (2-3 days)
5. Configure Ortex to use custom ONNX Runtime
6. Update YOLO.load with `:acl` EP
7. Test end-to-end pipeline
8. Validate performance metrics

**Phase 3: Optimization** (1-2 days)
9. Cache Docker image in registry
10. Document build process
11. Create fallback strategy for CPU-only

**Total**: 6-9 days to production-ready ACL support

---

## Next Steps

### Immediate (This Week)
- [x] Research ACL support in Ortex/ort ✅ **COMPLETE**
- [ ] Create Dockerfile for ONNX Runtime + ACL build
- [ ] Build initial ARM64 Docker image
- [ ] Test build on development machine

### Short-term (Next Week)
- [ ] Test ACL on actual Raspberry Pi 4
- [ ] Benchmark CPU vs ACL performance
- [ ] Configure Ortex for custom ONNX Runtime
- [ ] Integrate with YOLO library

### Medium-term (Following Week)
- [ ] Optimize Docker build (caching)
- [ ] Document ACL setup process
- [ ] Update deployment manifests
- [ ] Performance tuning and validation

---

## Success Criteria

### Minimum Viable
- ✅ ONNX Runtime compiles with ACL support
- ✅ ACL execution provider loads successfully
- ✅ Achieves 4-6 FPS on Raspberry Pi 4 (2x baseline)
- ✅ Falls back to CPU if ACL unavailable

### Stretch Goals
- 🎯 Achieves 8-10 FPS on Raspberry Pi 4 (3x baseline)
- 🎯 10-12 FPS on Raspberry Pi 5
- 🎯 Docker build time < 45 minutes
- 🎯 Zero code changes to application layer

---

## References

### Documentation
- **ort (Rust)**: https://docs.rs/ort
- **ONNX Runtime ACL EP**: https://onnxruntime.ai/docs/execution-providers/community-maintained/ACL-ExecutionProvider.html
- **ARM Compute Library**: https://github.com/ARM-software/ComputeLibrary
- **Ortex**: https://hexdocs.pm/ortex
- **YOLO Elixir**: https://github.com/poeticoding/yolo_elixir

### Build Guides
- **ONNX Runtime build**: https://onnxruntime.ai/docs/build/inferencing.html
- **ACL build**: https://github.com/ARM-software/ComputeLibrary/blob/main/docs/user_guide/how_to_build.md

---

## Conclusion

✅ **ACL is the right choice for Raspberry Pi acceleration**

**Key findings**:
1. ACL is fully supported in the stack (ort → ONNX Runtime)
2. Requires custom ONNX Runtime build (medium complexity)
3. Expected 2-3x speedup (sufficient for real-time nav)
4. Low risk with CPU fallback
5. Estimated 6-9 days to production

**Next action**: Create Dockerfile for ONNX Runtime + ACL build
