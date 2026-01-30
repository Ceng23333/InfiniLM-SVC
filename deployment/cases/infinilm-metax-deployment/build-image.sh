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
#   --proxy PROXY          Set HTTP/HTTPS proxy (e.g., http://127.0.0.1:7890)
#   --no-proxy NO_PROXY    Set NO_PROXY list (comma-separated)
#   --privileged           Use privileged mode for device access during build (not recommended)
#   -h, --help             Show this help message
#
# Note: Device access errors during build verification are expected and non-fatal.
#       See TROUBLESHOOTING.md for details.

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
HTTP_PROXY="${HTTP_PROXY:-}"
HTTPS_PROXY="${HTTPS_PROXY:-}"
ALL_PROXY="${ALL_PROXY:-}"
NO_PROXY="${NO_PROXY:-}"

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
  --proxy PROXY          Set HTTP/HTTPS proxy (e.g., http://127.0.0.1:7890)
                         Also checks HTTP_PROXY/HTTPS_PROXY environment variables
  --no-proxy NO_PROXY    Set NO_PROXY list (comma-separated)
                         Also checks NO_PROXY environment variable
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
        --proxy)
            HTTP_PROXY="$2"
            HTTPS_PROXY="$2"
            shift 2
            ;;
        --no-proxy)
            NO_PROXY="$2"
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
if [ -n "${HTTP_PROXY}" ] || [ -n "${HTTPS_PROXY}" ]; then
    echo "Proxy: ${HTTP_PROXY:-${HTTPS_PROXY}}"
fi
echo ""

# Build Docker build arguments
BUILD_ARGS=(
    -f "${DOCKERFILE}"
    --build-arg "BASE_IMAGE=${BASE_IMAGE}"
    --progress "${PROGRESS_TYPE}"
    -t "${IMAGE_TAG}"
)

# Check if proxy is localhost/127.0.0.1 - need host network for container to access host proxy
USE_HOST_NETWORK=false
if echo "${HTTP_PROXY}${HTTPS_PROXY}" | grep -qE "127\.0\.0\.1|localhost"; then
    USE_HOST_NETWORK=true
    echo "Detected localhost proxy - will use --network host for Docker build"
fi

# Add proxy build args if set
if [ -n "${HTTP_PROXY}" ]; then
    BUILD_ARGS+=(--build-arg "HTTP_PROXY=${HTTP_PROXY}")
    BUILD_ARGS+=(--build-arg "http_proxy=${HTTP_PROXY}")
fi
if [ -n "${HTTPS_PROXY}" ]; then
    BUILD_ARGS+=(--build-arg "HTTPS_PROXY=${HTTPS_PROXY}")
    BUILD_ARGS+=(--build-arg "https_proxy=${HTTPS_PROXY}")
fi
if [ -n "${ALL_PROXY}" ]; then
    BUILD_ARGS+=(--build-arg "ALL_PROXY=${ALL_PROXY}")
    BUILD_ARGS+=(--build-arg "all_proxy=${ALL_PROXY}")
fi
if [ -n "${NO_PROXY}" ]; then
    BUILD_ARGS+=(--build-arg "NO_PROXY=${NO_PROXY}")
    BUILD_ARGS+=(--build-arg "no_proxy=${NO_PROXY}")
fi

# Add --network host if localhost proxy detected
if [ "${USE_HOST_NETWORK}" = "true" ]; then
    BUILD_ARGS+=(--network host)
fi

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

# Setup cache directories on host for future use
# These can be used with Docker BuildKit cache mounts (Docker 19.03+) or manually
CACHE_BASE_DIR="${HOME}/.docker-build-cache/infinilm-svc"
mkdir -p "${CACHE_BASE_DIR}/cargo" "${CACHE_BASE_DIR}/pip" "${CACHE_BASE_DIR}/cache" "${CACHE_BASE_DIR}/tmp"

# Note: Docker 18.09 has limited BuildKit support and may timeout on Docker Hub
# Disable BuildKit for compatibility. For Docker 19.03+, enable BuildKit and use cache mounts:
#   DOCKER_BUILDKIT=1 docker build --mount=type=cache,target=/root/.cargo ...
export DOCKER_BUILDKIT=0

echo "Building image..."
echo "Command: docker build ${BUILD_ARGS[*]} ."
echo ""
echo "Cache directories prepared at: ${CACHE_BASE_DIR}"
echo "  - Cargo cache: ${CACHE_BASE_DIR}/cargo"
echo "  - Pip cache: ${CACHE_BASE_DIR}/pip"
echo "  - General cache: ${CACHE_BASE_DIR}/cache"
echo "  - Temp cache: ${CACHE_BASE_DIR}/tmp"
echo ""
echo "Note: For Docker 19.03+ with BuildKit cache mounts, use:"
echo "  DOCKER_BUILDKIT=1 docker build --mount=type=cache,target=/root/.cargo --mount=type=cache,target=/root/.cache/pip ..."
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
