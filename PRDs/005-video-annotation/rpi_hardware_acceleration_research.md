# Raspberry Pi Hardware Acceleration Research

**Date**: October 26, 2025
**Context**: After achieving 3.1x speedup with EMLX on macOS (3.7 → 11.5 FPS), investigating hardware acceleration options for Raspberry Pi

## Current Status

- **macOS (EMLX/Metal)**: 11.5 FPS (3.1x speedup)
- **Raspberry Pi (EXLA/CPU)**: 2-4 FPS (estimated, not yet tested on RPi)

**Goal**: Achieve similar hardware acceleration on Raspberry Pi

---

## Hardware Acceleration Options for Raspberry Pi

### Option 1: ONNX Runtime with ARM Compute Library (ACL) ⭐ **RECOMMENDED**

**What it is**: ARM Compute Library provides SIMD/NEON optimizations for ARM processors

**Compatibility**:
- ✅ Raspberry Pi 4/5 (ARM Cortex-A72/A76)
- ✅ Works with existing ONNX models (no conversion needed)
- ✅ Integrates with Ortex library we already use

**Expected speedup**: 2-3x over pure CPU

**Implementation**:
```elixir
# In YOLO.load or Ortex configuration
execution_providers: [:acl, :cpu]  # Try ACL first, fallback to CPU
```

**Resources**:
- ONNX Runtime ARM ACL: https://onnxruntime.ai/docs/execution-providers/ACL-ExecutionProvider.html
- Ortex execution providers: https://hexdocs.pm/ortex/Ortex.html

**Pros**:
- ✅ Easy to enable (just change execution provider)
- ✅ No model conversion needed
- ✅ Works with Ortex (already in our stack)
- ✅ Maintained by ARM/Microsoft
- ✅ Low risk

**Cons**:
- ⚠️  Not as fast as GPU (but RPi doesn't have powerful GPU)
- ⚠️  Need to compile ONNX Runtime with ACL support

**Next Steps**:
1. Build ONNX Runtime with ACL support in Docker
2. Test with Ortex + ACL execution provider
3. Benchmark vs CPU-only

---

### Option 2: TensorFlow Lite with XNNPACK Delegate

**What it is**: Optimized inference engine for mobile/edge devices

**Compatibility**:
- ✅ Raspberry Pi 4/5
- ❌ Requires model conversion (ONNX → TFLite)
- ❌ Different inference library (not Ortex)

**Expected speedup**: 2-4x over pure CPU

**Implementation**:
- Convert YOLOX model to TFLite format
- Use TFLite Elixir bindings (if exist) or NIF

**Pros**:
- ✅ Highly optimized for ARM
- ✅ XNNPACK delegate is very fast
- ✅ Maintained by Google

**Cons**:
- ❌ Requires model conversion
- ❌ Need new Elixir library or custom NIF
- ❌ High development effort
- ❌ Different inference stack

**Verdict**: Higher effort, uncertain payoff. Skip for now.

---

### Option 3: Raspberry Pi GPU (VideoCore) with OpenGL ES

**What it is**: Use RPi's VideoCore GPU for compute

**Compatibility**:
- ⚠️  Limited support on RPi 4
- ⚠️  Better on RPi 5 but still limited

**Expected speedup**: 1.5-2x (GPU is weak)

**Implementation**:
- Custom OpenGL ES shaders for inference
- Or use OpenCL (if available)

**Pros**:
- ✅ Uses dedicated GPU hardware

**Cons**:
- ❌ Very limited GPU compute capability
- ❌ Complex implementation
- ❌ Likely not worth the effort
- ❌ High maintenance burden

**Verdict**: RPi GPU is not designed for ML compute. Skip.

---

### Option 4: Coral USB Accelerator (TPU)

**What it is**: External USB Edge TPU accelerator

**Compatibility**:
- ✅ Raspberry Pi 4/5 via USB
- ❌ Requires model conversion to TFLite + quantization
- ❌ Hardware purchase required ($60-75)

**Expected speedup**: 10-20x over CPU 🚀

**Implementation**:
- Convert model to TFLite with INT8 quantization
- Use TensorFlow Lite + Edge TPU runtime
- Custom Elixir NIF or Python bridge

**Pros**:
- ✅ Massive speedup potential
- ✅ Dedicated ML accelerator
- ✅ Proven technology

**Cons**:
- ❌ Requires hardware purchase ($60-75)
- ❌ Model conversion + quantization (quality loss)
- ❌ High development effort
- ❌ External dependency (USB dongle)
- ❌ Not practical for production drones

**Verdict**: Great for prototyping, not practical for production. Consider for future.

---

### Option 5: NCNN Framework (Tencent)

**What it is**: Lightweight neural network inference framework optimized for mobile/ARM

**Compatibility**:
- ✅ Raspberry Pi 4/5
- ✅ Highly optimized for ARM
- ⚠️  Requires model conversion (ONNX → NCNN)
- ⚠️  Need Elixir bindings or NIF

**Expected speedup**: 2-3x over CPU

**Implementation**:
- Convert YOLOX to NCNN format
- Build Elixir NIF for NCNN (custom work)
- Replace Ortex with NCNN backend

**Pros**:
- ✅ Very optimized for ARM
- ✅ Used in production by Tencent
- ✅ Active development

**Cons**:
- ❌ Requires custom Elixir bindings (significant work)
- ❌ Model conversion needed
- ❌ Replaces our Ortex stack
- ❌ Maintenance burden

**Verdict**: Mentioned in original implementation plan but high effort. Consider only if ACL doesn't work.

---

## Recommendation: Start with ARM Compute Library (ACL)

### Why ACL First?

1. **Lowest effort**: Just change execution provider config
2. **Low risk**: Works with existing ONNX models + Ortex
3. **Good speedup**: Expected 2-3x improvement
4. **Easy to test**: Can benchmark quickly
5. **Fallback safe**: Falls back to CPU if ACL fails

### Implementation Plan

**Phase 1: Docker Build with ACL** (1-2 days)
```dockerfile
# Dockerfile changes
RUN apt-get install -y \
    libarmcl-dev \
    libgomp1

# Build ONNX Runtime with ACL support
ENV ONNXRUNTIME_PROVIDERS="acl,cpu"
```

**Phase 2: Ortex Configuration** (1 day)
```elixir
# In YOLO.load or model initialization
model = YOLO.load(
  model_path: model_path,
  classes_path: classes_path,
  model_impl: YOLO.Models.YOLOX,
  execution_providers: [:acl, :cpu]  # Try ACL first, fallback to CPU
)
```

**Phase 3: Benchmark** (1 day)
- Test on actual Raspberry Pi 4/5
- Compare CPU-only vs ACL
- Measure FPS improvement

**Expected Timeline**: 3-4 days total

**Expected Result**: 2-4 FPS → 6-10 FPS on Raspberry Pi

---

## Alternative: If ACL Doesn't Work

If ARM Compute Library doesn't provide sufficient speedup or has issues:

**Fallback Option: Optimize Model Size**

1. **Model Quantization**: Convert to INT8
   - Expected: 2-3x speedup
   - Tradeoff: ~2-5% accuracy loss
   - Effort: Medium (model conversion)

2. **Smaller Model**: Use YOLOX-Tiny instead of YOLOX-Nano
   - Expected: 2x speedup
   - Tradeoff: Lower accuracy
   - Effort: Low (just swap model file)

3. **Resolution Reduction**: 640x640 → 416x416
   - Expected: 2x speedup
   - Tradeoff: Miss small objects
   - Effort: Low (config change)

---

## Success Metrics

### Minimum Viable Performance
- **Target**: 4-6 FPS on Raspberry Pi 4/5
- **Rationale**: Usable for real-time navigation decisions

### Stretch Goal
- **Target**: 8-10 FPS on Raspberry Pi 5
- **Rationale**: Smooth real-time performance

### Current Baseline
- **CPU-only (estimated)**: 2-4 FPS
- **With ACL (expected)**: 6-10 FPS ✅ Meets minimum viable

---

## Next Steps

1. **Immediate** (This week):
   - [ ] Research Ortex ACL execution provider support
   - [ ] Check if YOLO library supports ACL
   - [ ] Review ONNX Runtime ARM ACL documentation

2. **Short-term** (Next sprint):
   - [ ] Build ONNX Runtime with ACL in Alpine Docker
   - [ ] Test ACL execution provider with Ortex
   - [ ] Benchmark on Raspberry Pi 4

3. **Medium-term** (Future):
   - [ ] If ACL insufficient, explore model quantization
   - [ ] If still insufficient, evaluate Coral TPU for prototyping
   - [ ] Document findings and update implementation plan

---

## Related Work

- **Phase 0**: macOS development pipeline (COMPLETE)
  - EMLX integration: 3.1x speedup (3.7 → 11.5 FPS)
  - Proves hardware acceleration is critical

- **Phase 1**: Raspberry Pi deployment (CURRENT)
  - Need to achieve similar acceleration
  - ACL is most promising path forward

---

## Resources

### ONNX Runtime + ACL
- ARM Compute Library: https://github.com/ARM-software/ComputeLibrary
- ONNX Runtime ACL EP: https://onnxruntime.ai/docs/execution-providers/ACL-ExecutionProvider.html
- Building ONNX Runtime: https://onnxruntime.ai/docs/build/inferencing.html

### Ortex
- Ortex docs: https://hexdocs.pm/ortex/Ortex.html
- Ortex GitHub: https://github.com/elixir-nx/ortex

### Alternative Frameworks
- NCNN: https://github.com/Tencent/ncnn
- TFLite: https://www.tensorflow.org/lite
- Coral TPU: https://coral.ai/docs/accelerator/get-started/

---

## Conclusion

The 3.1x speedup achieved with EMLX on macOS demonstrates that hardware acceleration is **critical** for real-time performance. ARM Compute Library (ACL) is the most promising path for Raspberry Pi because:

✅ Low effort (just change execution provider)
✅ Low risk (works with existing stack)
✅ Good expected speedup (2-3x)
✅ Easy to benchmark and validate

**Recommendation**: Prioritize ACL integration for Phase 1 (Raspberry Pi deployment). This should get us to 6-10 FPS, which is sufficient for real-time navigation.
