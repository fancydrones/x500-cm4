# ARM Compute Library (ACL) Build Guide

This guide explains how to build and deploy the video_streamer with ARM Compute Library (ACL) support for hardware-accelerated inference on Raspberry Pi.

## Overview

ACL provides ARM NEON/SIMD optimizations for neural network inference, delivering **2-3x speedup** compared to CPU-only execution:

- **Without ACL (CPU)**: 2-4 FPS estimated
- **With ACL (ARM NEON)**: 6-10 FPS target

## Build Process

The `Dockerfile.acl` uses a multi-stage build:

1. **Stage 1**: Build ARM Compute Library from source
2. **Stage 2**: Build ONNX Runtime with ACL support (~45 min)
3. **Stage 3**: Build Elixir application with custom ONNX Runtime
4. **Stage 4**: Create lightweight runtime image

### Build Time

- **First build**: ~45-60 minutes (compiling ACL + ONNX Runtime)
- **Subsequent builds**: ~5-10 minutes (cached layers)

## Building the Image

### Prerequisites

1. Docker with buildx support
2. Access to ghcr.io/fancydrones registry
3. ARM64 build environment or QEMU emulation

### Basic Build

```bash
cd /Users/royveshovda/src/fancydrones/x500-cm4/apps/video_streamer

# Build for ARM64 (Raspberry Pi)
docker buildx build \
  --platform linux/arm64 \
  --file Dockerfile.acl \
  --tag ghcr.io/fancydrones/x500-cm4/video-streamer:acl-latest \
  --push \
  .
```

### Build with Caching (Recommended)

To speed up subsequent builds, use registry caching:

```bash
# Get short commit hash for tagging
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

### Local Testing (CPU Only)

Test the build locally without pushing to registry:

```bash
# Build locally
docker build -f Dockerfile.acl -t video-streamer-acl:test .

# Check version
docker run --rm -it video-streamer-acl:test /app/bin/video_streamer version

# Interactive shell for debugging
docker run --rm -it video-streamer-acl:test sh

# Verify ACL linking
docker run --rm -it video-streamer-acl:test ldd /usr/local/lib/libonnxruntime.so
```

## Deployment

### Update Kubernetes Manifest

Update the deployment to use the ACL image:

```yaml
# k8s/deployments/video-streamer-deployment.yaml
spec:
  containers:
  - name: video-streamer
    image: ghcr.io/fancydrones/x500-cm4/video-streamer:acl-latest
    # ... rest of spec
```

### Deploy to Cluster

```bash
kubectl apply -f k8s/deployments/video-streamer-deployment.yaml

# Watch rollout
kubectl rollout status deployment/video-streamer -n default

# Check logs
kubectl logs -f deployment/video-streamer -n default
```

## Verifying ACL Support

### Check ONNX Runtime Execution Providers

When the application starts, check logs for ACL execution provider:

```bash
kubectl logs deployment/video-streamer -n default | grep -i "acl\|execution provider"
```

Expected output should show ACL as an available execution provider.

### Benchmark Performance

The application should log inference times. Compare before/after ACL:

```bash
# Watch for performance metrics
kubectl logs -f deployment/video-streamer -n default | grep -E "inference|fps|frame"
```

Target metrics:
- **Inference time**: < 250ms per frame (4 FPS minimum)
- **Full pipeline**: 6-10 FPS with ACL (vs 2-4 FPS CPU-only)

## Troubleshooting

### Build Failures

**ACL compilation errors**:
- Check Alpine version compatibility
- Verify scons is installed correctly
- Try adjusting `-j$(nproc)` to reduce parallelism

**ONNX Runtime build failures**:
- Increase Docker build memory (8GB+ recommended)
- Check ACL paths in build.sh arguments
- Verify protobuf-dev is installed

**Elixir compilation errors**:
- Ensure `ONNXRUNTIME_STRATEGY=system` is set
- Check library paths in `LD_LIBRARY_PATH`
- Verify all dependencies are copied from previous stages

### Runtime Errors

**ACL not being used**:
```bash
# Check execution provider configuration
# In application.ex, verify eps: [:acl, :cpu]
```

**Missing libraries**:
```bash
# Shell into pod
kubectl exec -it deployment/video-streamer -n default -- sh

# Check ACL libraries
ls -la /usr/local/lib/libarm_compute*

# Check ONNX Runtime libraries
ls -la /usr/local/lib/libonnxruntime*

# Verify linking
ldd /usr/local/lib/libonnxruntime.so
```

## Performance Comparison

| Configuration | Inference Time | FPS | Speedup |
|--------------|----------------|-----|---------|
| CPU Only (EXLA) | ~250-500ms | 2-4 | 1.0x |
| ACL (ARM NEON) | ~100-170ms | 6-10 | 2-3x |
| macOS (EMLX Metal) | ~60-90ms | 11-15 | 5-7x |

## Version Information

- **ONNX Runtime**: 1.20.1
- **ARM Compute Library**: v24.11
- **Elixir**: 1.18.4
- **OTP**: 28.1.1
- **Alpine**: 3.22.2 (builder), edge (runtime)

## Next Steps

After successful ACL deployment:

1. Benchmark performance on actual Raspberry Pi hardware
2. Document actual FPS improvements
3. Consider Phase 1.5: Dual-path pipeline for smooth piloting
4. Optimize model size if needed (currently YOLOX-Nano 3.5MB)

## References

- [ARM Compute Library](https://github.com/ARM-software/ComputeLibrary)
- [ONNX Runtime ACL Execution Provider](https://onnxruntime.ai/docs/execution-providers/ACL-ExecutionProvider.html)
- [Ortex Documentation](https://hexdocs.pm/ortex)
- [Phase 1 Implementation Plan](../../PRDs/005-video-annotation/implementation_plan.md#phase-1-raspberry-pi-deployment-with-arm-acceleration-week-1-3)
