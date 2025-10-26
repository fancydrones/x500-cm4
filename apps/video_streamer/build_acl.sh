#!/bin/bash
set -e

# ACL Build Script for video_streamer
# Builds Docker image with ARM Compute Library support for Raspberry Pi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== ARM Compute Library (ACL) Build Script ===${NC}"
echo ""

# Check if docker buildx is available
if ! docker buildx version > /dev/null 2>&1; then
    echo -e "${RED}Error: docker buildx is not available${NC}"
    echo "Please install Docker Desktop or enable buildx"
    exit 1
fi

# Get git commit hash for tagging
COMMIT_HASH=$(git rev-parse --short HEAD)
echo -e "${GREEN}Building for commit: ${COMMIT_HASH}${NC}"

# Registry configuration
REGISTRY="ghcr.io/fancydrones/x500-cm4"
IMAGE_NAME="video-streamer"
IMAGE_TAG_SHORT="acl-${COMMIT_HASH}"
IMAGE_TAG_LATEST="acl-latest"
CACHE_TAG="acl-buildcache"

# Full image names
IMAGE_FULL_SHORT="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG_SHORT}"
IMAGE_FULL_LATEST="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG_LATEST}"
CACHE_REF="${REGISTRY}/${IMAGE_NAME}:${CACHE_TAG}"

echo ""
echo "Configuration:"
echo "  Registry: ${REGISTRY}"
echo "  Image: ${IMAGE_NAME}"
echo "  Short tag: ${IMAGE_TAG_SHORT}"
echo "  Latest tag: ${IMAGE_TAG_LATEST}"
echo ""

# Build mode selection
echo "Build modes:"
echo "  1) Fast build with cache (recommended)"
echo "  2) Fresh build without cache"
echo "  3) Local test build (no push)"
echo ""
read -p "Select build mode [1-3]: " BUILD_MODE

case $BUILD_MODE in
    1)
        echo -e "${GREEN}Building with cache...${NC}"
        echo -e "${YELLOW}Note: First build takes ~45-60 minutes${NC}"
        echo ""

        docker buildx build \
            --platform linux/arm64 \
            --file Dockerfile.acl \
            --tag "${IMAGE_FULL_SHORT}" \
            --tag "${IMAGE_FULL_LATEST}" \
            --cache-from type=registry,ref="${CACHE_REF}" \
            --cache-to type=registry,ref="${CACHE_REF}",mode=max \
            --push \
            .

        echo ""
        echo -e "${GREEN}✓ Build complete!${NC}"
        echo ""
        echo "Images pushed:"
        echo "  - ${IMAGE_FULL_SHORT}"
        echo "  - ${IMAGE_FULL_LATEST}"
        ;;

    2)
        echo -e "${YELLOW}Warning: Fresh build without cache${NC}"
        echo -e "${YELLOW}This will take 45-60 minutes and rebuild everything${NC}"
        read -p "Are you sure? [y/N]: " CONFIRM

        if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
            echo "Cancelled"
            exit 0
        fi

        echo -e "${GREEN}Building without cache...${NC}"
        echo ""

        docker buildx build \
            --platform linux/arm64 \
            --file Dockerfile.acl \
            --tag "${IMAGE_FULL_SHORT}" \
            --tag "${IMAGE_FULL_LATEST}" \
            --no-cache \
            --push \
            .

        echo ""
        echo -e "${GREEN}✓ Build complete!${NC}"
        echo ""
        echo "Images pushed:"
        echo "  - ${IMAGE_FULL_SHORT}"
        echo "  - ${IMAGE_FULL_LATEST}"
        ;;

    3)
        echo -e "${GREEN}Building local test image...${NC}"
        echo -e "${YELLOW}Note: ACL acceleration requires ARM64 hardware${NC}"
        echo ""

        docker build \
            -f Dockerfile.acl \
            -t video-streamer-acl:test \
            .

        echo ""
        echo -e "${GREEN}✓ Build complete!${NC}"
        echo ""
        echo "Test commands:"
        echo "  # Check version"
        echo "  docker run --rm -it video-streamer-acl:test /app/bin/video_streamer version"
        echo ""
        echo "  # Interactive shell"
        echo "  docker run --rm -it video-streamer-acl:test sh"
        echo ""
        echo "  # Verify ACL linking"
        echo "  docker run --rm -it video-streamer-acl:test ldd /usr/local/lib/libonnxruntime.so"
        ;;

    *)
        echo -e "${RED}Invalid selection${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "  1. Update k8s deployment manifest to use: ${IMAGE_FULL_LATEST}"
echo "  2. Deploy: kubectl apply -f k8s/deployments/video-streamer-deployment.yaml"
echo "  3. Monitor: kubectl logs -f deployment/video-streamer"
echo "  4. Benchmark performance on Raspberry Pi"
echo ""
echo "See ACL_BUILD_GUIDE.md for detailed documentation"
