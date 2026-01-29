#!/usr/bin/env bash
# Build script for InfiniLM-SVC deployment image based on GPU factory base image
#
# This script builds the InfiniLM-SVC deployment image using a GPU factory
# provided base image (e.g., Metax GPU factory image with HPCC, PyTorch, etc.)
#
# Usage:
#   ./build-image.sh [OPTIONS]
#
# Options:
#   --base-image IMAGE     GPU factory base image (default: see script)
#   --tag TAG              Output image tag (default: infinilm-svc:infinilm-demo)
#   --no-cache             Build without cache
#   --debug                Use debug Dockerfile with verbose output
#   --progress TYPE        Docker build progress type (auto, plain, tty)
#   --push                 Push image to registry after build
#   --registry REGISTRY    Registry to push to (required if --push)
#   -h, --help             Show this help message

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Default values
DEFAULT_BASE_IMAGE="cr.metax-tech.com/public-ai-release-wb/x201/vllm:hpcc2.32.0.11-torch2.4-py310-kylin2309a-arm64"
BASE_IMAGE="${BASE_IMAGE:-${DEFAULT_BASE_IMAGE}}"
IMAGE_TAG="${IMAGE_TAG:-infinilm-svc:infinilm-demo}"
NO_CACHE="${NO_CACHE:-false}"
USE_DEBUG="${USE_DEBUG:-false}"
PROGRESS_TYPE="${PROGRESS_TYPE:-auto}"
PUSH_IMAGE="${PUSH_IMAGE:-false}"
REGISTRY="${REGISTRY:-}"

usage() {
    cat <<EOF
Build script for InfiniLM-SVC deployment image based on GPU factory base image

Usage:
  $0 [OPTIONS]

Options:
  --base-image IMAGE     GPU factory base image
                         (default: ${DEFAULT_BASE_IMAGE})
  --tag TAG              Output image tag
                         (default: ${IMAGE_TAG})
  --no-cache             Build without using cache
  --push                 Push image to registry after build
  --registry REGISTRY    Registry to push to (required if --push)
  -h, --help             Show this help message

Examples:
  # Build with default base image
  $0

  # Build with custom base image
  $0 --base-image your-registry/image:tag

  # Build with debug output (verbose, step-by-step)
  $0 --debug

  # Build with plain progress output
  $0 --progress plain

  # Build without cache
  $0 --no-cache

  # Build and push to registry
  $0 --push --registry your-registry.com --tag your-registry/infinilm-svc:latest

  # Full debug build (no cache + debug Dockerfile + plain output)
  $0 --debug --no-cache

Environment variables:
  BASE_IMAGE             Override base image (same as --base-image)
  IMAGE_TAG              Override image tag (same as --tag)
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --base-image)
            BASE_IMAGE="$2"
            shift 2
            ;;
        --tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        --no-cache)
            NO_CACHE="true"
            shift
            ;;
        --debug)
            USE_DEBUG="true"
            PROGRESS_TYPE="plain"
            shift
            ;;
        --progress)
            PROGRESS_TYPE="$2"
            shift 2
            ;;
        --push)
            PUSH_IMAGE="true"
            shift
            ;;
        --registry)
            REGISTRY="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate arguments
if [ "${PUSH_IMAGE}" = "true" ] && [ -z "${REGISTRY}" ]; then
    echo "Error: --registry is required when using --push"
    exit 1
fi

# Build Dockerfile path
if [ "${USE_DEBUG}" = "true" ]; then
    DOCKERFILE="${SCRIPT_DIR}/Dockerfile.gpu-factory.debug"
    echo "Using debug Dockerfile for verbose output"
else
    DOCKERFILE="${SCRIPT_DIR}/Dockerfile.gpu-factory"
fi

if [ ! -f "${DOCKERFILE}" ]; then
    echo "Error: Dockerfile not found at ${DOCKERFILE}"
    exit 1
fi

echo "=========================================="
echo "Building InfiniLM-SVC Deployment Image"
echo "=========================================="
echo "Project root: ${PROJECT_ROOT}"
echo "Dockerfile: ${DOCKERFILE}"
echo "Base image: ${BASE_IMAGE}"
echo "Output tag: ${IMAGE_TAG}"
echo "No cache: ${NO_CACHE}"
echo ""

# Build Docker build arguments
BUILD_ARGS=(
    -f "${DOCKERFILE}"
    --build-arg "BASE_IMAGE=${BASE_IMAGE}"
    --progress "${PROGRESS_TYPE}"
    -t "${IMAGE_TAG}"
)

if [ "${NO_CACHE}" = "true" ]; then
    BUILD_ARGS+=(--no-cache)
fi

# Add labels for build info
BUILD_ARGS+=(
    --label "build.date=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    --label "build.base-image=${BASE_IMAGE}"
)

# Change to project root for build context
cd "${PROJECT_ROOT}"

echo "Building image..."
echo "Command: docker build ${BUILD_ARGS[*]} ."
echo ""

if docker build "${BUILD_ARGS[@]}" .; then
    echo ""
    echo "✅ Image built successfully: ${IMAGE_TAG}"

    # Show image info
    echo ""
    echo "Image information:"
    docker images "${IMAGE_TAG}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"

    # Push if requested
    if [ "${PUSH_IMAGE}" = "true" ]; then
        echo ""
        echo "Pushing image to registry..."
        FULL_TAG="${REGISTRY}/${IMAGE_TAG}"
        docker tag "${IMAGE_TAG}" "${FULL_TAG}"

        if docker push "${FULL_TAG}"; then
            echo "✅ Image pushed successfully: ${FULL_TAG}"
        else
            echo "❌ Failed to push image: ${FULL_TAG}"
            exit 1
        fi
    fi

    echo ""
    echo "=========================================="
    echo "Build completed successfully!"
    echo "=========================================="
    echo ""
    echo "To use this image:"
    echo "  export IMAGE_NAME=${IMAGE_TAG}"
    echo "  ./start-master.sh <MASTER_IP>"
    echo ""

    exit 0
else
    echo ""
    echo "❌ Build failed"
    exit 1
fi
