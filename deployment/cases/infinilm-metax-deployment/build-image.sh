#!/usr/bin/env bash
# Build script for InfiniLM-SVC deployment image
#
# This script builds the InfiniLM-SVC deployment image using a phased approach:
#   Phase 1: Install dependencies and cache Rust crates (can be cached/reused)
#   Phase 2: Build from local sources (no network needed)
#
# Usage:
#   ./build-image.sh [OPTIONS]
#
# Options:
#   --base-image IMAGE     GPU factory base image (default: see script)
#   --tag TAG              Output image tag (default: infinilm-svc:infinilm-demo)
#   --phase PHASE          deps|build|runtime|all (default: all)
#                          deps: Build only Phase 1 (dependencies)
#                          build: Build only Phase 2 (requires deps image)
#                          runtime: Build runtime stage (requires build stage)
#                          all: Build all phases including runtime (default)
#   --deps-image IMAGE     Use existing deps image for Phase 2 (when --phase=build)
#   --no-cache             Build without cache
#   --debug                Use debug output (verbose)
#   --progress TYPE        Docker build progress type (auto, plain, tty)
#   --push                 Push image to registry after build
#   --registry REGISTRY    Registry to push to (required if --push)
#   --proxy PROXY          Set HTTP/HTTPS proxy (e.g., http://127.0.0.1:7890)
#   --no-proxy NO_PROXY    Set NO_PROXY list (comma-separated)
#   --infinicore-src PATH  Path to InfiniCore source (for Phase 2)
#   --infinilm-src PATH    Path to InfiniLM source (for Phase 2)
#   -h, --help             Show this help message
#
# Examples:
#   # Build Phase 1 only (for caching dependencies)
#   ./build-image.sh --phase deps --tag infinilm-svc:deps
#
#   # Build Phase 2 using cached Phase 1
#   ./build-image.sh --phase build --deps-image infinilm-svc:deps
#
#   # Build both phases (full build)
#   ./build-image.sh --phase all
#
#   # Build with custom base image
#   ./build-image.sh --base-image your-registry/image:tag

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Default values
DEFAULT_BASE_IMAGE="cr.metax-tech.com/public-ai-release-wb/x201/vllm:hpcc2.32.0.11-torch2.4-py310-kylin2309a-arm64"
BASE_IMAGE="${BASE_IMAGE:-${DEFAULT_BASE_IMAGE}}"
IMAGE_TAG="${IMAGE_TAG:-infinilm-svc:infinilm-demo}"
DEPS_IMAGE_TAG="${DEPS_IMAGE_TAG:-infinilm-svc:deps}"
BUILD_PHASE="${BUILD_PHASE:-all}"
BUILD_RUNTIME="${BUILD_RUNTIME:-false}"
RUNTIME_TAG="${RUNTIME_TAG:-}"
DEPS_IMAGE="${DEPS_IMAGE:-}"
NO_CACHE="${NO_CACHE:-false}"
USE_DEBUG="${USE_DEBUG:-false}"
PROGRESS_TYPE="${PROGRESS_TYPE:-auto}"
PUSH_IMAGE="${PUSH_IMAGE:-false}"
REGISTRY="${REGISTRY:-}"
HTTP_PROXY="${HTTP_PROXY:-}"
HTTPS_PROXY="${HTTPS_PROXY:-}"
ALL_PROXY="${ALL_PROXY:-}"
NO_PROXY="${NO_PROXY:-}"
INFINICORE_SRC="${INFINICORE_SRC:-}"
INFINILM_SRC="${INFINILM_SRC:-}"
DEPLOYMENT_CASE="${DEPLOYMENT_CASE:-infinilm-metax-deployment}"

usage() {
    cat <<EOF
Build script for InfiniLM-SVC deployment image

Usage:
  $0 [OPTIONS]

Options:
  --base-image IMAGE     GPU factory base image
                         (default: ${DEFAULT_BASE_IMAGE})
  --tag TAG              Output image tag
                         (default: ${IMAGE_TAG})
  --phase PHASE          deps|build|all (default: all)
                         deps: Build only Phase 1 (dependencies)
                         build: Build only Phase 2 (requires deps image)
                         all: Build both phases (default)
  --deps-image IMAGE     Use existing deps image for Phase 2
                         (required when --phase=build)
  --deps-tag TAG         Tag for Phase 1 deps image
                         (default: ${DEPS_IMAGE_TAG})
  --no-cache             Build without using cache
  --debug                Use debug output (verbose)
  --progress TYPE        Docker build progress type (auto, plain, tty)
  --push                 Push image to registry after build
  --registry REGISTRY    Registry to push to (required if --push)
  --proxy PROXY          Set HTTP/HTTPS proxy (e.g., http://127.0.0.1:7890)
                         Also checks HTTP_PROXY/HTTPS_PROXY environment variables
  --no-proxy NO_PROXY    Set NO_PROXY list (comma-separated)
                         Also checks NO_PROXY environment variable
  --infinicore-src PATH  Path to InfiniCore source (for Phase 2)
  --infinilm-src PATH    Path to InfiniLM source (for Phase 2)
  --infinilm-svc-src PATH Path to InfiniLM-SVC source (for Phase 2)
  --deployment-case NAME Deployment case preset name
                         (default: ${DEPLOYMENT_CASE})
  -h, --help             Show this help message

Examples:
  # Build Phase 1 only (for caching dependencies)
  $0 --phase deps --deps-tag infinilm-svc:deps

  # Build Phase 2 using cached Phase 1
  $0 --phase build --deps-image infinilm-svc:deps

  # Build both phases (full build)
  $0 --phase all

  # Build with custom base image
  $0 --base-image your-registry/image:tag --phase all

  # Build Phase 1 with deployment case
  $0 --phase deps --deployment-case infinilm-metax-deployment

Environment variables:
  BASE_IMAGE             Override base image (same as --base-image)
  IMAGE_TAG              Override image tag (same as --tag)
  BUILD_PHASE             Override phase (same as --phase)
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
        --phase)
            BUILD_PHASE="$2"
            shift 2
            ;;
        --deps-image)
            DEPS_IMAGE="$2"
            shift 2
            ;;
        --deps-tag)
            DEPS_IMAGE_TAG="$2"
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
        --infinicore-src)
            INFINICORE_SRC="$2"
            shift 2
            ;;
        --infinilm-src)
            INFINILM_SRC="$2"
            shift 2
            ;;
        --infinilm-svc-src)
            INFINILM_SVC_SRC="$2"
            shift 2
            ;;
        --deployment-case)
            DEPLOYMENT_CASE="$2"
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

if [ "${BUILD_PHASE}" != "deps" ] && [ "${BUILD_PHASE}" != "build" ] && [ "${BUILD_PHASE}" != "runtime" ] && [ "${BUILD_PHASE}" != "all" ]; then
    echo "Error: --phase must be one of: deps, build, runtime, all"
    exit 1
fi

if [ "${BUILD_PHASE}" = "build" ] && [ -z "${DEPS_IMAGE}" ]; then
    echo "Error: --deps-image is required when --phase=build"
    echo "  Example: --deps-image infinilm-svc:deps"
    exit 1
fi

# Dockerfile path
DOCKERFILE="${PROJECT_ROOT}/docker/Dockerfile.build"

if [ ! -f "${DOCKERFILE}" ]; then
    echo "Error: Dockerfile not found at ${DOCKERFILE}"
    exit 1
fi

echo "=========================================="
echo "Building InfiniLM-SVC"
echo "=========================================="
echo "Project root: ${PROJECT_ROOT}"
echo "Dockerfile: ${DOCKERFILE}"
echo "Base image: ${BASE_IMAGE}"
echo "Build phase: ${BUILD_PHASE}"
echo "Deployment case: ${DEPLOYMENT_CASE}"
if [ "${BUILD_PHASE}" = "build" ]; then
    echo "Deps image: ${DEPS_IMAGE}"
fi
echo "Output tag: ${IMAGE_TAG}"
if [ "${BUILD_PHASE}" = "deps" ] || [ "${BUILD_PHASE}" = "all" ]; then
    echo "Deps tag: ${DEPS_IMAGE_TAG}"
fi
echo "No cache: ${NO_CACHE}"
if [ -n "${HTTP_PROXY}" ] || [ -n "${HTTPS_PROXY}" ]; then
    echo "Proxy: ${HTTP_PROXY:-${HTTPS_PROXY}}"
fi
echo ""

# Build Docker build arguments
BUILD_ARGS=(
    -f "${DOCKERFILE}"
    --build-arg "BASE_IMAGE=${BASE_IMAGE}"
    --build-arg "DEPLOYMENT_CASE=${DEPLOYMENT_CASE}"
    --progress "${PROGRESS_TYPE}"
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
    --label "build.phase=${BUILD_PHASE}"
    --label "build.deployment-case=${DEPLOYMENT_CASE}"
)

# Change to project root for build context
cd "${PROJECT_ROOT}"

# Phase 1: Build deps image
# Use the main Dockerfile.build which defines the deps stage
if [ "${BUILD_PHASE}" = "deps" ] || [ "${BUILD_PHASE}" = "all" ]; then
    echo "=========================================="
    echo "Phase 1: Building Dependencies Image"
    echo "=========================================="
    echo ""

    PHASE1_ARGS=("${BUILD_ARGS[@]}")
    PHASE1_ARGS+=(--target deps)
    PHASE1_ARGS+=(-t "${DEPS_IMAGE_TAG}")

    echo "Building Phase 1 (dependencies)..."
    echo "  Using Dockerfile: ${DOCKERFILE}"
    echo "Command: docker build ${PHASE1_ARGS[*]} ."
    echo ""

    if docker build "${PHASE1_ARGS[@]}" .; then
        echo ""
        echo "✅ Phase 1 image built successfully: ${DEPS_IMAGE_TAG}"

        # Show image info
        echo ""
        echo "Phase 1 image information:"
        docker images "${DEPS_IMAGE_TAG}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"

        # Set DEPS_IMAGE for Phase 2 if building all phases
        if [ "${BUILD_PHASE}" = "all" ]; then
            DEPS_IMAGE="${DEPS_IMAGE_TAG}"
        fi
    else
        echo ""
        echo "❌ Phase 1 build failed"
        exit 1
    fi
fi

# Phase 2: Build from sources
if [ "${BUILD_PHASE}" = "build" ] || [ "${BUILD_PHASE}" = "all" ]; then
    echo ""
    echo "=========================================="
    echo "Phase 2: Building from Sources"
    echo "=========================================="
    echo ""

    # Validate deps image exists
    if ! docker image inspect "${DEPS_IMAGE}" >/dev/null 2>&1; then
        echo "Error: Deps image not found: ${DEPS_IMAGE}"
        echo "  Please build Phase 1 first or specify --deps-image"
        exit 1
    fi

    # Phase 2 is offline - don't include proxy settings
    # Use a separate Dockerfile that doesn't define the deps stage
    # This prevents Docker from rebuilding Phase 1 dependencies
    PHASE2_DOCKERFILE="${PROJECT_ROOT}/docker/Dockerfile.build-only"
    if [ ! -f "${PHASE2_DOCKERFILE}" ]; then
        echo "Error: Phase 2 Dockerfile not found: ${PHASE2_DOCKERFILE}"
        exit 1
    fi

    # Generate timestamp tag (default: minute precision)
    BUILD_TIMESTAMP="${BUILD_TIMESTAMP:-$(date -u +'%Y%m%d%H%M')}"

    # Build args without proxy (Phase 2 should work offline)
    PHASE2_ARGS=(
        -f "${PHASE2_DOCKERFILE}"
        --build-arg "BASE_IMAGE=${BASE_IMAGE}"
        --build-arg "BUILD_TIMESTAMP=${BUILD_TIMESTAMP}"
        --progress "${PROGRESS_TYPE:-auto}"
    )

    # Add deployment case if set
    if [ -n "${DEPLOYMENT_CASE}" ]; then
        PHASE2_ARGS+=(--build-arg "DEPLOYMENT_CASE=${DEPLOYMENT_CASE}")
    fi

    # Add labels
    PHASE2_ARGS+=(
        --label "build.date=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
        --label "build.base-image=${BASE_IMAGE}"
        --label "build.phase=build"
        --label "build.timestamp=${BUILD_TIMESTAMP}"
    )
    if [ -n "${DEPLOYMENT_CASE}" ]; then
        PHASE2_ARGS+=(--label "build.deployment-case=${DEPLOYMENT_CASE}")
    fi

    # Add no-cache if requested
    if [ "${NO_CACHE}" = "true" ]; then
        PHASE2_ARGS+=(--no-cache)
    fi

    # Now add Phase 2 specific args
    PHASE2_ARGS+=(--target build)
    PHASE2_ARGS+=(--build-arg "DEPS_IMAGE=${DEPS_IMAGE}")
    PHASE2_ARGS+=(-t "${IMAGE_TAG}")

    echo "Building Phase 2 (from sources)..."
    echo "  Using deps image: ${DEPS_IMAGE}"
    echo "  Timestamp: ${BUILD_TIMESTAMP}"

    # Check if external repos are provided and outside build context
    # Docker can't access files outside the build context
    # If external paths are provided, we'll use the repos from deps image instead
    INFINICORE_SRC_ORIG="${INFINICORE_SRC}"
    INFINILM_SRC_ORIG="${INFINILM_SRC}"

    if [ -n "${INFINICORE_SRC}" ] && [ "${INFINICORE_SRC}" != "/app/../InfiniCore" ] && [ "${INFINICORE_SRC}" != "../InfiniCore" ]; then
        echo "  Note: InfiniCore path ${INFINICORE_SRC} is outside build context"
        echo "  Using InfiniCore from deps image instead (cloned during Phase 1)"
        # Don't pass the external path, let it use the one from deps image
        INFINICORE_SRC=""
    fi
    if [ -n "${INFINILM_SRC}" ] && [ "${INFINILM_SRC}" != "/app/../InfiniLM" ] && [ "${INFINILM_SRC}" != "../InfiniLM" ]; then
        echo "  Note: InfiniLM path ${INFINILM_SRC} is outside build context"
        echo "  Using InfiniLM from deps image instead (cloned during Phase 1)"
        # Don't pass the external path, let it use the one from deps image
        INFINILM_SRC=""
    fi

    # Display what will be used
    if [ -n "${INFINICORE_SRC_ORIG}" ]; then
        if [ -n "${INFINICORE_SRC}" ]; then
            echo "  InfiniCore source: ${INFINICORE_SRC}"
        else
            echo "  InfiniCore: Using from deps image (external path ${INFINICORE_SRC_ORIG} not accessible)"
        fi
    else
        echo "  InfiniCore: Using from deps image (not provided externally)"
    fi
    if [ -n "${INFINILM_SRC_ORIG}" ]; then
        if [ -n "${INFINILM_SRC}" ]; then
            echo "  InfiniLM source: ${INFINILM_SRC}"
        else
            echo "  InfiniLM: Using from deps image (external path ${INFINILM_SRC_ORIG} not accessible)"
        fi
    else
        echo "  InfiniLM: Using from deps image (not provided externally)"
    fi

    # Check if InfiniLM-SVC source is provided and outside build context
    INFINILM_SVC_SRC="${INFINILM_SVC_SRC:-}"
    INFINILM_SVC_SRC_ORIG="${INFINILM_SVC_SRC}"
    if [ -n "${INFINILM_SVC_SRC}" ] && [ "${INFINILM_SVC_SRC}" != "." ] && [ "${INFINILM_SVC_SRC}" != "./" ]; then
        # Check if it's an absolute path outside the project root
        PROJECT_ROOT_NORMALIZED="$(cd "${PROJECT_ROOT}" && pwd)"
        INFINILM_SVC_SRC_NORMALIZED="$(cd "$(dirname "${INFINILM_SVC_SRC}")" 2>/dev/null && pwd)/$(basename "${INFINILM_SVC_SRC}")" || INFINILM_SVC_SRC_NORMALIZED="${INFINILM_SVC_SRC}"
        if [[ ! "${INFINILM_SVC_SRC_NORMALIZED}" == "${PROJECT_ROOT_NORMALIZED}"* ]]; then
            echo "  Note: InfiniLM-SVC path ${INFINILM_SVC_SRC} is outside build context"
            echo "  Using InfiniLM-SVC from build context (current directory)"
            INFINILM_SVC_SRC=""
        fi
    fi

    # Add InfiniCore/InfiniLM build args only if they're valid (inside build context)
    # If empty, install-build.sh will use repos from deps image (already installed in Phase 1)
    if [ -n "${INFINICORE_SRC}" ]; then
        PHASE2_ARGS+=(--build-arg "INFINICORE_SRC=${INFINICORE_SRC}")
    fi
    if [ -n "${INFINILM_SRC}" ]; then
        PHASE2_ARGS+=(--build-arg "INFINILM_SRC=${INFINILM_SRC}")
    fi
    if [ -n "${INFINILM_SVC_SRC}" ]; then
        PHASE2_ARGS+=(--build-arg "INFINILM_SVC_SRC=${INFINILM_SVC_SRC}")
    fi

    # Don't disable installation - let install-build.sh use repos from deps image
    # The install-build.sh script will check if repos exist and use them
    # Repos should already be installed in deps image from Phase 1

    echo "Command: docker build ${PHASE2_ARGS[*]} ."
    echo ""

    if docker build "${PHASE2_ARGS[@]}" .; then
        echo ""
        echo "✅ Phase 2 (build) image built successfully: ${IMAGE_TAG}"

        # Show image info
        echo ""
        echo "Phase 2 (build) image information:"
        docker images "${IMAGE_TAG}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
    else
        echo ""
        echo "❌ Phase 2 build failed"
        exit 1
    fi

    # Phase 2 automatically includes runtime stage for deployment usage
    # Build runtime stage using the build image we just created
    echo ""
    echo "=========================================="
    echo "Phase 2 (continued): Building Runtime Image"
    echo "=========================================="
    echo ""

    # Generate timestamp tag (default: minute precision)
    BUILD_TIMESTAMP="${BUILD_TIMESTAMP:-$(date -u +'%Y%m%d%H%M')}"

    # Generate runtime tag with timestamp
    if [ -z "${RUNTIME_TAG}" ]; then
        # Extract repository and base tag from IMAGE_TAG
        if [[ "${IMAGE_TAG}" == *":"* ]]; then
            RUNTIME_REPO="${IMAGE_TAG%%:*}"
            RUNTIME_TAG="${RUNTIME_REPO}:runtime-${BUILD_TIMESTAMP}"
        else
            RUNTIME_TAG="${IMAGE_TAG}-runtime-${BUILD_TIMESTAMP}"
        fi
    fi

    # Build args for runtime stage
    # Use the same Dockerfile as Phase 2 (Dockerfile.build-only has runtime stage)
    # Runtime stage uses build stage as base, so we need to pass DEPS_IMAGE (which is actually the build image)
    # But since we're building from the build image, we should use Dockerfile.build instead
    # Actually, Dockerfile.build-only defines build stage FROM ${DEPS_IMAGE}, so we need to pass the build image as DEPS_IMAGE
    RUNTIME_ARGS=(
        -f "${PHASE2_DOCKERFILE}"
        --target runtime
        --build-arg "DEPS_IMAGE=${IMAGE_TAG}"
        --build-arg "BUILD_TIMESTAMP=${BUILD_TIMESTAMP}"
        --build-arg "DEPLOYMENT_CASE=${DEPLOYMENT_CASE}"
        --progress "${PROGRESS_TYPE:-auto}"
    )

    # Add labels
    RUNTIME_ARGS+=(
        --label "build.date=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
        --label "build.base-image=${BASE_IMAGE}"
        --label "build.phase=runtime"
        --label "build.timestamp=${BUILD_TIMESTAMP}"
    )
    if [ -n "${DEPLOYMENT_CASE}" ]; then
        RUNTIME_ARGS+=(--label "build.deployment-case=${DEPLOYMENT_CASE}")
    fi

    # Add no-cache if requested
    if [ "${NO_CACHE}" = "true" ]; then
        RUNTIME_ARGS+=(--no-cache)
    fi

    # Add output tag
    RUNTIME_ARGS+=(-t "${RUNTIME_TAG}")

    echo "Building runtime stage (for deployment)..."
    echo "  Using build image: ${IMAGE_TAG}"
    echo "  Base image: ${BASE_IMAGE}"
    echo "  Timestamp: ${BUILD_TIMESTAMP}"
    echo "  Output tag: ${RUNTIME_TAG}"
    echo "Command: docker build ${RUNTIME_ARGS[*]} ."
    echo ""

    if docker build "${RUNTIME_ARGS[@]}" .; then
        echo ""
        echo "✅ Runtime image built successfully: ${RUNTIME_TAG}"

        # Show image info
        echo ""
        echo "Runtime image information:"
        docker images "${RUNTIME_TAG}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"

        # Also tag as the main IMAGE_TAG for convenience (runtime is the deployment image)
        docker tag "${RUNTIME_TAG}" "${IMAGE_TAG}-runtime" 2>/dev/null || true
        echo ""
        echo "ℹ️  Runtime image also tagged as: ${IMAGE_TAG}-runtime"
    else
        echo ""
        echo "❌ Runtime build failed"
        exit 1
    fi
fi

# Phase 3: Build runtime stage (standalone, when --phase=runtime)
if [ "${BUILD_PHASE}" = "runtime" ]; then
    echo ""
    echo "=========================================="
    echo "Phase 3: Building Runtime Image"
    echo "=========================================="
    echo ""

    # Validate build image exists
    BUILD_IMAGE_TAG="${IMAGE_TAG}"
    if ! docker image inspect "${BUILD_IMAGE_TAG}" >/dev/null 2>&1; then
        echo "Error: Build image not found: ${BUILD_IMAGE_TAG}"
        echo "  Please build Phase 2 first or specify --deps-image and build all phases"
        exit 1
    fi

    # Generate timestamp tag (default: minute precision)
    BUILD_TIMESTAMP="${BUILD_TIMESTAMP:-$(date -u +'%Y%m%d%H%M')}"

    # Generate runtime tag with timestamp
    if [ -z "${RUNTIME_TAG}" ]; then
        # Extract repository and base tag from IMAGE_TAG
        if [[ "${IMAGE_TAG}" == *":"* ]]; then
            RUNTIME_REPO="${IMAGE_TAG%%:*}"
            RUNTIME_TAG="${RUNTIME_REPO}:runtime-${BUILD_TIMESTAMP}"
        else
            RUNTIME_TAG="${IMAGE_TAG}-runtime-${BUILD_TIMESTAMP}"
        fi
    fi

    # Build args for runtime stage
    # Runtime stage uses build stage as base, so no BASE_IMAGE needed
    RUNTIME_ARGS=(
        -f "${DOCKERFILE}"
        --target runtime
        --build-arg "BUILD_TIMESTAMP=${BUILD_TIMESTAMP}"
        --build-arg "DEPLOYMENT_CASE=${DEPLOYMENT_CASE}"
        --progress "${PROGRESS_TYPE:-auto}"
    )

    # Add labels
    RUNTIME_ARGS+=(
        --label "build.date=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
        --label "build.base-image=${BASE_IMAGE}"
        --label "build.phase=runtime"
        --label "build.timestamp=${BUILD_TIMESTAMP}"
    )
    if [ -n "${DEPLOYMENT_CASE}" ]; then
        RUNTIME_ARGS+=(--label "build.deployment-case=${DEPLOYMENT_CASE}")
    fi

    # Add no-cache if requested
    if [ "${NO_CACHE}" = "true" ]; then
        RUNTIME_ARGS+=(--no-cache)
    fi

    # Add output tag
    RUNTIME_ARGS+=(-t "${RUNTIME_TAG}")

    echo "Building Phase 3 (runtime)..."
    echo "  Using build image: ${BUILD_IMAGE_TAG}"
    echo "  Base image: ${BASE_IMAGE}"
    echo "  Timestamp: ${BUILD_TIMESTAMP}"
    echo "  Output tag: ${RUNTIME_TAG}"
    echo "Command: docker build ${RUNTIME_ARGS[*]} ."
    echo ""

    if docker build "${RUNTIME_ARGS[@]}" .; then
        echo ""
        echo "✅ Phase 3 (runtime) image built successfully: ${RUNTIME_TAG}"

        # Show image info
        echo ""
        echo "Phase 3 (runtime) image information:"
        docker images "${RUNTIME_TAG}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
    else
        echo ""
        echo "❌ Phase 3 (runtime) build failed"
        exit 1
    fi
fi

# Push if requested
if [ "${PUSH_IMAGE}" = "true" ]; then
    echo ""
    echo "=========================================="
    echo "Pushing Images to Registry"
    echo "=========================================="
    echo ""

    if [ "${BUILD_PHASE}" = "deps" ] || [ "${BUILD_PHASE}" = "all" ]; then
        FULL_DEPS_TAG="${REGISTRY}/${DEPS_IMAGE_TAG}"
        echo "Pushing Phase 1 image..."
        docker tag "${DEPS_IMAGE_TAG}" "${FULL_DEPS_TAG}"
        if docker push "${FULL_DEPS_TAG}"; then
            echo "✅ Phase 1 image pushed: ${FULL_DEPS_TAG}"
        else
            echo "❌ Failed to push Phase 1 image: ${FULL_DEPS_TAG}"
            exit 1
        fi
    fi

    if [ "${BUILD_PHASE}" = "build" ] || [ "${BUILD_PHASE}" = "all" ]; then
        FULL_TAG="${REGISTRY}/${IMAGE_TAG}"
        echo "Pushing Phase 2 (build) image..."
        docker tag "${IMAGE_TAG}" "${FULL_TAG}"
        if docker push "${FULL_TAG}"; then
            echo "✅ Phase 2 (build) image pushed: ${FULL_TAG}"
        else
            echo "❌ Failed to push Phase 2 (build) image: ${FULL_TAG}"
            exit 1
        fi

        # Push runtime image if it was built (runtime is built automatically with Phase 2)
        if [ -n "${RUNTIME_TAG}" ]; then
            FULL_RUNTIME_TAG="${REGISTRY}/${RUNTIME_TAG}"
            echo "Pushing runtime (deployment) image..."
            docker tag "${RUNTIME_TAG}" "${FULL_RUNTIME_TAG}"
            if docker push "${FULL_RUNTIME_TAG}"; then
                echo "✅ Runtime (deployment) image pushed: ${FULL_RUNTIME_TAG}"
            else
                echo "❌ Failed to push runtime (deployment) image: ${FULL_RUNTIME_TAG}"
                exit 1
            fi
        fi
    fi

    if [ "${BUILD_PHASE}" = "runtime" ]; then
        if [ -n "${RUNTIME_TAG}" ]; then
            FULL_RUNTIME_TAG="${REGISTRY}/${RUNTIME_TAG}"
            echo "Pushing runtime (deployment) image..."
            docker tag "${RUNTIME_TAG}" "${FULL_RUNTIME_TAG}"
            if docker push "${FULL_RUNTIME_TAG}"; then
                echo "✅ Runtime (deployment) image pushed: ${FULL_RUNTIME_TAG}"
            else
                echo "❌ Failed to push runtime (deployment) image: ${FULL_RUNTIME_TAG}"
                exit 1
            fi
        fi
    fi
fi

echo ""
echo "=========================================="
echo "Build completed successfully!"
echo "=========================================="
echo ""

if [ "${BUILD_PHASE}" = "deps" ]; then
    echo "Phase 1 (deps) image: ${DEPS_IMAGE_TAG}"
    echo ""
    echo "To build Phase 2, run:"
    echo "  $0 --phase build --deps-image ${DEPS_IMAGE_TAG}"
elif [ "${BUILD_PHASE}" = "build" ]; then
    echo "Phase 2 (build) image: ${IMAGE_TAG}"
    if [ -n "${RUNTIME_TAG}" ]; then
        echo "Runtime (deployment) image: ${RUNTIME_TAG}"
        echo ""
        echo "To use the runtime image (recommended for deployment):"
        echo "  export IMAGE_NAME=${RUNTIME_TAG}"
        echo "  ./start-master.sh <MASTER_IP>"
        echo ""
        echo "Or use the convenience tag:"
        echo "  export IMAGE_NAME=${IMAGE_TAG}-runtime"
        echo "  ./start-master.sh <MASTER_IP>"
    else
        echo ""
        echo "To use this image:"
        echo "  export IMAGE_NAME=${IMAGE_TAG}"
        echo "  ./start-master.sh <MASTER_IP>"
    fi
elif [ "${BUILD_PHASE}" = "runtime" ]; then
    if [ -n "${RUNTIME_TAG}" ]; then
        echo "Phase 3 (runtime) image: ${RUNTIME_TAG}"
        echo ""
        echo "To use this image:"
        echo "  export IMAGE_NAME=${RUNTIME_TAG}"
        echo "  ./start-master.sh <MASTER_IP>"
    fi
else
    echo "Phase 1 (deps) image: ${DEPS_IMAGE_TAG}"
    echo "Phase 2 (build) image: ${IMAGE_TAG}"
    if [ -n "${RUNTIME_TAG}" ]; then
        echo "Runtime (deployment) image: ${RUNTIME_TAG}"
    fi
    echo ""
    if [ -n "${RUNTIME_TAG}" ]; then
        echo "To use the runtime image (recommended for deployment):"
        echo "  export IMAGE_NAME=${RUNTIME_TAG}"
        echo "  ./start-master.sh <MASTER_IP>"
        echo ""
        echo "Or use the convenience tag:"
        echo "  export IMAGE_NAME=${IMAGE_TAG}-runtime"
        echo "  ./start-master.sh <MASTER_IP>"
    else
        echo "To use the build image:"
        echo "  export IMAGE_NAME=${IMAGE_TAG}"
        echo "  ./start-master.sh <MASTER_IP>"
    fi
    echo ""
    echo "To reuse Phase 1 for faster rebuilds:"
    echo "  $0 --phase build --deps-image ${DEPS_IMAGE_TAG}"
fi

echo ""
