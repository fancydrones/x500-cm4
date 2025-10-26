# Phase 1 Progress: ACL Integration for Raspberry Pi

**Status**: Setup Complete - Ready for Build & Deploy
**Date**: 2025-10-26
**Commit**: a08e73d

## Objective

Deploy video annotation with ARM Compute Library (ACL) hardware acceleration on Raspberry Pi, achieving 2-3x inference speedup (2-4 FPS → 6-10 FPS target).

## Completed Tasks ✅

### 1. ACL Build Infrastructure

**Files Created**:
- [apps/video_streamer/Dockerfile.acl](../../apps/video_streamer/Dockerfile.acl) - Multi-stage build for ACL + ONNX Runtime
- [apps/video_streamer/build_acl.sh](../../apps/video_streamer/build_acl.sh) - Convenient build script with caching
- [apps/video_streamer/.dockerignore](../../apps/video_streamer/.dockerignore) - Build artifact exclusions
- [apps/video_streamer/ACL_BUILD_GUIDE.md](../../apps/video_streamer/ACL_BUILD_GUIDE.md) - Complete documentation

**Docker Build**:
- **Stage 1**: ARM Compute Library v24.11 compilation
- **Stage 2**: ONNX Runtime 1.20.1 with ACL execution provider
- **Stage 3**: Elixir 1.18.4 + OTP 28.1.1 application build
- **Stage 4**: Lightweight Alpine Edge runtime image

**Build Time**:
- First build: ~45-60 minutes (compiling ACL + ONNX Runtime)
- Cached builds: ~5-10 minutes (using registry cache)

### 2. Kubernetes Deployment

**File Created**:
- [deployments/apps/video-streamer-acl-deployment.yaml](../../deployments/apps/video-streamer-acl-deployment.yaml)

**Key Configuration**:
```yaml
image: ghcr.io/fancydrones/x500-cm4/video-streamer:acl-latest
env:
  - name: ONNX_EXECUTION_PROVIDERS
    value: "acl,cpu"  # Try ACL first, fallback to CPU
resources:
  limits:
    cpu: "4"
    memory: 3072Mi
  requests:
    cpu: "1"
    memory: 1024Mi
```

### 3. Documentation

Complete guides created:
- Build instructions with 3 modes (cached, fresh, local test)
- Deployment workflow
- Verification procedures
- Troubleshooting guide
- Performance comparison table

## Pending Tasks 🔄

### Task 1: Build ACL Docker Image ⏭️ NEXT

**Command**:
```bash
cd apps/video_streamer
./build_acl.sh
# Select option 1 (Fast build with cache)
```

**Expected Output**:
- Image: `ghcr.io/fancydrones/x500-cm4/video-streamer:acl-latest`
- Build time: ~45-60 minutes (first build)
- Registry cache created for future builds

**Verification**:
```bash
# Check image exists
docker buildx imagetools inspect ghcr.io/fancydrones/x500-cm4/video-streamer:acl-latest
```

### Task 2: Deploy to Raspberry Pi

**Command**:
```bash
kubectl apply -f deployments/apps/video-streamer-acl-deployment.yaml

# Watch rollout
kubectl rollout status deployment/video-streamer -n rpiuav

# Check logs for ACL initialization
kubectl logs -f deployment/video-streamer -n rpiuav | grep -i "acl\|execution provider"
```

**Success Criteria**:
- Pod starts successfully
- ACL execution provider initialized
- RTSP stream available at rtsp://<pod-ip>:8554/video
- No crash loops or errors

### Task 3: Benchmark Performance

**Test Plan**:
1. Connect RTSP client (QGroundControl or VLC)
2. Monitor logs for inference timing
3. Measure FPS over 60 seconds
4. Compare to CPU-only baseline

**Metrics to Collect**:
```bash
# Watch for performance data
kubectl logs -f deployment/video-streamer -n rpiuav | grep -E "inference|fps|frame|ms"
```

**Target Metrics**:
- **Inference time**: < 250ms per frame (4 FPS minimum)
- **Full pipeline**: 6-10 FPS (vs 2-4 FPS CPU-only)
- **Speedup**: 2-3x improvement

### Task 4: Document Results

Create benchmark report in `PHASE_1_RESULTS.md`:
- Actual vs expected performance
- Inference time breakdown
- Resource utilization (CPU, memory)
- Issues encountered and resolutions
- Recommendations for Phase 1.5

## Technical Details

### ACL Configuration

The Dockerfile compiles ACL with:
```bash
scons Werror=0 debug=0 neon=1 opencl=0 os=linux arch=armv8a build=native
```

ONNX Runtime build includes ACL execution provider:
```bash
./build.sh --config Release --build_shared_lib --use_acl \
  --acl_home=/build/acl --acl_libs=/build/acl/build
```

### Execution Provider Priority

Application will try execution providers in order:
1. **ACL** (ARM NEON acceleration) - preferred
2. **CPU** (fallback) - if ACL unavailable

### Resource Requirements

**Build Machine**:
- 8GB+ RAM recommended
- ARM64 architecture (or QEMU emulation)
- Docker buildx with multi-platform support

**Runtime (Raspberry Pi)**:
- CPU: 4 cores reserved (burst to handle peaks)
- Memory: 1GB baseline, 3GB limit
- Privileged container (camera access)
- Host network mode (RTSP streaming)

## Validation Checklist

Before proceeding to Phase 1.5:

- [ ] ACL Docker image built successfully
- [ ] Image pushed to ghcr.io registry
- [ ] Deployment applied to cluster
- [ ] Pod running without crash loops
- [ ] ACL execution provider initialized (check logs)
- [ ] RTSP stream accessible
- [ ] Inference FPS ≥ 6 (target: 6-10 FPS)
- [ ] Performance results documented
- [ ] No significant resource issues (CPU/memory)

## Performance Baseline

### Phase 0 Results (macOS Development)

| Configuration | Inference Time | FPS | Speedup |
|--------------|----------------|-----|---------|
| macOS CPU (EXLA) | ~270ms | 3.7 | 1.0x baseline |
| macOS GPU (EMLX Metal) | ~87ms | 11.5 | 3.1x |

### Phase 1 Targets (Raspberry Pi)

| Configuration | Inference Time | FPS | Speedup |
|--------------|----------------|-----|---------|
| RPi CPU (estimated) | ~250-500ms | 2-4 | 1.0x baseline |
| RPi ACL (target) | ~100-170ms | 6-10 | 2-3x |

## Next Phase Preview

**Phase 1.5: Dual-Path Pipeline** (Week 4)

After ACL validation, implement:
- 30 FPS original stream (piloting)
- 2-4 FPS annotated stream (situational awareness)
- Server-side overlay rendering
- Dual RTSP streams for QGroundControl

See [implementation_plan.md](implementation_plan.md#phase-15-dual-path-pipeline-for-smooth-piloting-week-4) for details.

## Build Command Reference

### Quick Build
```bash
cd apps/video_streamer
./build_acl.sh
# Select: 1 (Fast build with cache)
```

### Manual Build
```bash
cd apps/video_streamer

# Get commit hash
COMMIT_HASH=$(git rev-parse --short HEAD)

# Build with cache
docker buildx build \
  --platform linux/arm64 \
  --file Dockerfile.acl \
  --tag ghcr.io/fancydrones/x500-cm4/video-streamer:acl-${COMMIT_HASH} \
  --tag ghcr.io/fancydrones/x500-cm4/video-streamer:acl-latest \
  --cache-from type=registry,ref=ghcr.io/fancydrones/x500-cm4/video-streamer:acl-buildcache \
  --cache-to type=registry,ref=ghcr.io/fancydrones/x500-cm4/video-streamer:acl-buildcache,mode=max \
  --push \
  .
```

### Local Testing
```bash
# Build without push
docker build -f Dockerfile.acl -t video-streamer-acl:test .

# Verify libraries
docker run --rm -it video-streamer-acl:test ldd /usr/local/lib/libonnxruntime.so | grep arm_compute
```

## Troubleshooting

Common issues and solutions documented in [ACL_BUILD_GUIDE.md](../../apps/video_streamer/ACL_BUILD_GUIDE.md#troubleshooting).

## References

- [ACL Research Findings](ACL_RESEARCH_FINDINGS.md)
- [ACL Implementation Plan](ACL_IMPLEMENTATION_PLAN.md)
- [Main Implementation Plan](implementation_plan.md)
- [ARM Compute Library GitHub](https://github.com/ARM-software/ComputeLibrary)
- [ONNX Runtime ACL Provider Docs](https://onnxruntime.ai/docs/execution-providers/ACL-ExecutionProvider.html)
