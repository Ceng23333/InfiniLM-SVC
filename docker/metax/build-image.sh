#!/usr/bin/env bash
# Build script for InfiniLM-SVC deployment image
#
# Two build paths:
#   dep-runtime: deps (remote repos) + runtime FROM deps. Use when no local repo override.
#   build-runtime: deps + build (optional local repos) + runtime FROM build. Use when --infinicore-src or --infinilm-src provided.
#   runtime: Build runtime only FROM existing deps or build image (requires --deps-image).
#
# Usage:
#   ./docker/metax/build-image.sh [OPTIONS]
#   or from project root:
#   docker/metax/build-image.sh [OPTIONS]
#
# Options:
#   --phase PHASE          dep-runtime|build-runtime|runtime (default: dep-runtime)
#   --deps-image IMAGE     Use existing deps/build image (for build-runtime or runtime)
#   --base-image IMAGE     GPU factory base image (default: see script)
#   --tag TAG              Output image tag (default: infinilm-svc:infinilm-demo)
#   --proxy PROXY          Set HTTP/HTTPS proxy (e.g., http://127.0.0.1:7890)
#   --infinicore-src PATH  Path to InfiniCore source (for build-runtime)
#   --infinilm-src PATH    Path to InfiniLM source (for build-runtime)
#   -h, --help             Show this help message
#
# Examples:
#   # dep-runtime: deps + runtime (remote repos only)
#   docker/metax/build-image.sh --phase dep-runtime --deployment-case infinilm-metax-deployment-opt
#
#   # build-runtime: deps + build + runtime (with local repo override)
#   docker/metax/build-image.sh --phase build-runtime --deps-image infinilm-svc:deps --infinilm-src /path/to/InfiniLM
#
#   # runtime only: build runtime FROM existing deps or build image
#   docker/metax/build-image.sh --phase runtime --deps-image infinilm-svc:deps

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Default values
DEFAULT_BASE_IMAGE="cr.metax-tech.com/public-ai-release-wb/x201/vllm:hpcc2.32.0.11-torch2.4-py310-kylin2309a-arm64"
BASE_IMAGE="${BASE_IMAGE:-${DEFAULT_BASE_IMAGE}}"
IMAGE_TAG="${IMAGE_TAG:-infinilm-svc:infinilm-demo}"
DEPS_IMAGE_TAG="${DEPS_IMAGE_TAG:-infinilm-svc:deps}"
BUILD_PHASE="${BUILD_PHASE:-dep-runtime}"
RUNTIME_TAG="${RUNTIME_TAG:-}"
DEPS_IMAGE="${DEPS_IMAGE:-}"
NO_CACHE="${NO_CACHE:-false}"
USE_DEBUG="${USE_DEBUG:-false}"
PROGRESS_TYPE="${PROGRESS_TYPE:-auto}"
PUSH_IMAGE="${PUSH_IMAGE:-false}"
REGISTRY="${REGISTRY:-}"
# Support both uppercase and lowercase proxy environment variables
HTTP_PROXY="${HTTP_PROXY:-${http_proxy:-}}"
HTTPS_PROXY="${HTTPS_PROXY:-${https_proxy:-}}"
ALL_PROXY="${ALL_PROXY:-${all_proxy:-}}"
NO_PROXY="${NO_PROXY:-${no_proxy:-}}"
INFINICORE_SRC="${INFINICORE_SRC:-}"
INFINILM_SRC="${INFINILM_SRC:-}"
INFINICORE_BRANCH="${INFINICORE_BRANCH:-}"
INFINILM_BRANCH="${INFINILM_BRANCH:-}"
DEPLOYMENT_CASE="${DEPLOYMENT_CASE:-infinilm-metax-deployment}"

usage() {
    cat <<EOF
Build script for InfiniLM-SVC deployment image

Two build paths:
  dep-runtime:   deps (remote repos) + runtime FROM deps
  build-runtime: deps + build (optional local repos) + runtime FROM build

Usage:
  $0 [OPTIONS]

Options:
  --phase PHASE          dep-runtime|build-runtime|runtime (default: dep-runtime)
  --deps-image IMAGE     Use existing deps/build image (for build-runtime or runtime)
  --base-image IMAGE     GPU factory base image (default: ${DEFAULT_BASE_IMAGE})
  --tag TAG              Output image tag (default: ${IMAGE_TAG})
  --deps-tag TAG         Tag for deps image (default: ${DEPS_IMAGE_TAG})
  --no-cache             Build without using cache
  --debug                Use debug output (verbose)
  --progress TYPE        Docker build progress type (auto, plain, tty)
  --push                 Push image to registry after build
  --registry REGISTRY    Registry to push to (required if --push)
  --proxy PROXY          Set HTTP/HTTPS proxy (e.g., http://127.0.0.1:7890)
  --no-proxy NO_PROXY    Set NO_PROXY list (comma-separated)
  --infinicore-src PATH  Path to InfiniCore source (for build-runtime)
  --infinilm-src PATH    Path to InfiniLM source (for build-runtime)
  --infinilm-svc-src PATH Path to InfiniLM-SVC source (for build-runtime)
  --deployment-case NAME Deployment case preset name (default: ${DEPLOYMENT_CASE})
  -h, --help             Show this help message

Examples:
  # dep-runtime: deps + runtime (remote repos only)
  $0 --phase dep-runtime --deployment-case infinilm-metax-deployment-opt

  # build-runtime: deps + build + runtime (with local repo override)
  $0 --phase build-runtime --deps-image infinilm-svc:deps --infinilm-src /path/to/InfiniLM

  # runtime only: build runtime FROM existing deps or build image
  $0 --phase runtime --deps-image infinilm-svc:deps

Environment variables:
  BASE_IMAGE             Override base image (same as --base-image)
  IMAGE_TAG              Override image tag (same as --tag)
  BUILD_PHASE            Override phase (same as --phase)
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
        --infinicore-branch)
            INFINICORE_BRANCH="$2"
            shift 2
            ;;
        --infinilm-branch)
            INFINILM_BRANCH="$2"
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

if [ "${BUILD_PHASE}" != "dep-runtime" ] && [ "${BUILD_PHASE}" != "build-runtime" ] && [ "${BUILD_PHASE}" != "runtime" ]; then
    echo "Error: --phase must be one of: dep-runtime, build-runtime, runtime"
    exit 1
fi

if [ "${BUILD_PHASE}" = "runtime" ] && [ -z "${DEPS_IMAGE}" ]; then
    echo "Error: --deps-image is required when --phase=runtime"
    echo "  Example: --deps-image infinilm-svc:deps"
    exit 1
fi

# Load deployment case defaults (including BASE_IMAGE and tag formats if specified)
# This allows each deployment case to specify its own defaults in install.defaults.sh
# Load AFTER argument parsing so CLI arguments can override defaults
if [ -n "${DEPLOYMENT_CASE}" ]; then
    DEPLOYMENT_CASE_DIR="${PROJECT_ROOT}/deployment/cases/${DEPLOYMENT_CASE}"
    INSTALL_DEFAULTS_FILE="${DEPLOYMENT_CASE_DIR}/install.defaults.sh"
    if [ -f "${INSTALL_DEFAULTS_FILE}" ]; then
        echo "Loading deployment case defaults from ${INSTALL_DEFAULTS_FILE}..."
        # Save values that were set via CLI/env (should not be overridden by defaults)
        SAVED_BASE_IMAGE="${BASE_IMAGE}"
        SAVED_IMAGE_TAG="${IMAGE_TAG}"
        SAVED_DEPS_IMAGE_TAG="${DEPS_IMAGE_TAG}"
        SAVED_RUNTIME_TAG="${RUNTIME_TAG}"
        # shellcheck disable=SC1090
        source "${INSTALL_DEFAULTS_FILE}"
        # Restore CLI/env values if they were explicitly set (not defaults)
        if [ "${SAVED_BASE_IMAGE}" != "${DEFAULT_BASE_IMAGE}" ]; then
            BASE_IMAGE="${SAVED_BASE_IMAGE}"
            echo "  Using BASE_IMAGE from CLI/env: ${BASE_IMAGE}"
        elif [ -n "${BASE_IMAGE:-}" ] && [ "${BASE_IMAGE}" != "${DEFAULT_BASE_IMAGE}" ]; then
            echo "  Using BASE_IMAGE from install.defaults.sh: ${BASE_IMAGE}"
        fi
        if [ "${SAVED_IMAGE_TAG}" != "infinilm-svc:infinilm-demo" ]; then
            IMAGE_TAG="${SAVED_IMAGE_TAG}"
            echo "  Using IMAGE_TAG from CLI/env: ${IMAGE_TAG}"
        elif [ -n "${IMAGE_TAG:-}" ] && [ "${IMAGE_TAG}" != "infinilm-svc:infinilm-demo" ]; then
            echo "  Using IMAGE_TAG from install.defaults.sh: ${IMAGE_TAG}"
        fi
        if [ "${SAVED_DEPS_IMAGE_TAG}" != "infinilm-svc:deps" ]; then
            DEPS_IMAGE_TAG="${SAVED_DEPS_IMAGE_TAG}"
            echo "  Using DEPS_IMAGE_TAG from CLI/env: ${DEPS_IMAGE_TAG}"
        elif [ -n "${DEPS_IMAGE_TAG:-}" ] && [ "${DEPS_IMAGE_TAG}" != "infinilm-svc:deps" ]; then
            echo "  Using DEPS_IMAGE_TAG from install.defaults.sh: ${DEPS_IMAGE_TAG}"
        fi
        if [ -n "${SAVED_RUNTIME_TAG}" ]; then
            RUNTIME_TAG="${SAVED_RUNTIME_TAG}"
            echo "  Using RUNTIME_TAG from CLI/env: ${RUNTIME_TAG}"
        elif [ -n "${RUNTIME_TAG:-}" ]; then
            echo "  Using RUNTIME_TAG from install.defaults.sh: ${RUNTIME_TAG}"
        fi
    fi
fi

# Final resolution: CLI/env override > install.defaults.sh > script defaults
BASE_IMAGE="${BASE_IMAGE:-${DEFAULT_BASE_IMAGE}}"
IMAGE_TAG="${IMAGE_TAG:-infinilm-svc:infinilm-demo}"
DEPS_IMAGE_TAG="${DEPS_IMAGE_TAG:-infinilm-svc:deps}"

# Dockerfile paths
# Phase 1 uses Dockerfile.deps (dedicated deps stage)
# Phase 2 uses Dockerfile.build (which only has build stage)
DOCKERFILE="${PROJECT_ROOT}/docker/Dockerfile.build"
PHASE1_DOCKERFILE="${PROJECT_ROOT}/docker/Dockerfile.deps"

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
if [ "${BUILD_PHASE}" = "build-runtime" ] && [ -n "${DEPS_IMAGE}" ]; then
    echo "Deps image: ${DEPS_IMAGE}"
fi
if [ "${BUILD_PHASE}" = "runtime" ]; then
    echo "Source image (deps/build): ${DEPS_IMAGE}"
fi
echo "Output tag: ${IMAGE_TAG}"
if [ "${BUILD_PHASE}" = "dep-runtime" ] || ( [ "${BUILD_PHASE}" = "build-runtime" ] && [ -z "${DEPS_IMAGE}" ] ); then
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

# Track if we build deps (for push logic in build-runtime)
DEPS_IMAGE_PROVIDED_BY_USER="${DEPS_IMAGE}"

# Phase 1: Build deps image
# dep-runtime: always build Phase 1; build-runtime: build Phase 1 unless --deps-image provided
if [ "${BUILD_PHASE}" = "dep-runtime" ] || ( [ "${BUILD_PHASE}" = "build-runtime" ] && [ -z "${DEPS_IMAGE}" ] ); then
    echo "=========================================="
    echo "Phase 1: Building Dependencies Image"
    echo "=========================================="
    echo ""

    # Use Dockerfile.deps for Phase 1 (dedicated deps stage)
    if [ ! -f "${PHASE1_DOCKERFILE}" ]; then
        echo "Error: Phase 1 Dockerfile not found: ${PHASE1_DOCKERFILE}"
        exit 1
    fi

    # Generate timestamp tag (default: minute precision)
    BUILD_TIMESTAMP="${BUILD_TIMESTAMP:-$(date -u +'%Y%m%d%H%M')}"

    # Build Phase 1 args (use PHASE1_DOCKERFILE instead of DOCKERFILE)
    # Phase 1 clones from remote (not using local synced repos)
    PHASE1_ARGS=(
        -f "${PHASE1_DOCKERFILE}"
        --build-arg "BASE_IMAGE=${BASE_IMAGE}"
        --build-arg "DEPLOYMENT_CASE=${DEPLOYMENT_CASE}"
        --build-arg "BUILD_TIMESTAMP=${BUILD_TIMESTAMP}"
        --progress "${PROGRESS_TYPE}"
    )

    # Add branch args for Phase 1 (to clone from specific branch with fixes)
    # Phase 1 uses remote code, so we can specify which branch to clone
    if [ -n "${INFINICORE_BRANCH:-}" ]; then
        PHASE1_ARGS+=(--build-arg "INFINICORE_BRANCH=${INFINICORE_BRANCH}")
        echo "  Phase 1 will clone InfiniCore from branch: ${INFINICORE_BRANCH}"
    fi
    if [ -n "${INFINILM_BRANCH:-}" ]; then
        PHASE1_ARGS+=(--build-arg "INFINILM_BRANCH=${INFINILM_BRANCH}")
        echo "  Phase 1 will clone InfiniLM from branch: ${INFINILM_BRANCH}"
    fi

    # Add proxy build args if set
    if [ -n "${HTTP_PROXY}" ]; then
        PHASE1_ARGS+=(--build-arg "HTTP_PROXY=${HTTP_PROXY}")
        PHASE1_ARGS+=(--build-arg "http_proxy=${HTTP_PROXY}")
    fi
    if [ -n "${HTTPS_PROXY}" ]; then
        PHASE1_ARGS+=(--build-arg "HTTPS_PROXY=${HTTPS_PROXY}")
        PHASE1_ARGS+=(--build-arg "https_proxy=${HTTPS_PROXY}")
    fi
    if [ -n "${ALL_PROXY}" ]; then
        PHASE1_ARGS+=(--build-arg "ALL_PROXY=${ALL_PROXY}")
        PHASE1_ARGS+=(--build-arg "all_proxy=${ALL_PROXY}")
    fi
    if [ -n "${NO_PROXY}" ]; then
        PHASE1_ARGS+=(--build-arg "NO_PROXY=${NO_PROXY}")
        PHASE1_ARGS+=(--build-arg "no_proxy=${NO_PROXY}")
    fi
    if [ -n "${PIP_INDEX_URL:-}" ]; then
        PHASE1_ARGS+=(--build-arg "PIP_INDEX_URL=${PIP_INDEX_URL}")
        echo "  Phase 1 will use PyPI index: ${PIP_INDEX_URL}"
    fi

    # Add --network host if localhost proxy detected
    if [ "${USE_HOST_NETWORK}" = "true" ]; then
        PHASE1_ARGS+=(--network host)
    fi

    if [ "${NO_CACHE}" = "true" ]; then
        PHASE1_ARGS+=(--no-cache)
    fi

    # Add labels
    PHASE1_ARGS+=(
        --label "build.date=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
        --label "build.base-image=${BASE_IMAGE}"
        --label "build.phase=deps"
        --label "build.timestamp=${BUILD_TIMESTAMP}"
    )
    if [ -n "${DEPLOYMENT_CASE}" ]; then
        PHASE1_ARGS+=(--label "build.deployment-case=${DEPLOYMENT_CASE}")
    fi

    PHASE1_ARGS+=(--target deps)
    PHASE1_ARGS+=(-t "${DEPS_IMAGE_TAG}")

    echo "Building Phase 1 (dependencies)..."
    echo "  Using Dockerfile: ${PHASE1_DOCKERFILE}"
    echo "Command: DOCKER_BUILDKIT=0 docker build ${PHASE1_ARGS[*]} ."
    echo ""

    if DOCKER_BUILDKIT=0 docker build "${PHASE1_ARGS[@]}" .; then
        echo ""
        echo "✅ Phase 1 image built successfully: ${DEPS_IMAGE_TAG}"

        # Show image info
        echo ""
        echo "Phase 1 image information:"
        docker images "${DEPS_IMAGE_TAG}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"

        # Set DEPS_IMAGE for Phase 2 when building build-runtime
        if [ "${BUILD_PHASE}" = "build-runtime" ]; then
            DEPS_IMAGE="${DEPS_IMAGE_TAG}"
        fi
    else
        echo ""
        echo "❌ Phase 1 build failed"
        exit 1
    fi
fi

# dep-runtime path: Build runtime FROM deps (no Phase 2)
if [ "${BUILD_PHASE}" = "dep-runtime" ]; then
    echo ""
    echo "=========================================="
    echo "dep-runtime: Building Runtime Image FROM deps"
    echo "=========================================="
    echo ""

    BUILD_TIMESTAMP="${BUILD_TIMESTAMP:-$(date -u +'%Y%m%d%H%M')}"
    if [ -z "${RUNTIME_TAG}" ]; then
        if [ -n "${DEFAULT_RUNTIME_TAG_FORMAT:-}" ]; then
            RUNTIME_TAG="${DEFAULT_RUNTIME_TAG_FORMAT}-${BUILD_TIMESTAMP}"
        elif [[ "${IMAGE_TAG}" == *":"* ]]; then
            RUNTIME_REPO="${IMAGE_TAG%%:*}"
            RUNTIME_TAG="${RUNTIME_REPO}:runtime-${BUILD_TIMESTAMP}"
        else
            RUNTIME_TAG="${IMAGE_TAG}-runtime-${BUILD_TIMESTAMP}"
        fi
    fi

    RUNTIME_DOCKERFILE="${PROJECT_ROOT}/docker/Dockerfile.runtime"
    if [ ! -f "${RUNTIME_DOCKERFILE}" ]; then
        echo "Error: Runtime Dockerfile not found: ${RUNTIME_DOCKERFILE}"
        exit 1
    fi

    RUNTIME_ARGS=(
        -f "${RUNTIME_DOCKERFILE}"
        --build-arg "BUILD_IMAGE=${DEPS_IMAGE_TAG}"
        --build-arg "BUILD_TIMESTAMP=${BUILD_TIMESTAMP}"
        --build-arg "DEPLOYMENT_CASE=${DEPLOYMENT_CASE}"
        --progress "${PROGRESS_TYPE:-auto}"
    )
    RUNTIME_ARGS+=(
        --label "build.date=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
        --label "build.base-image=${BASE_IMAGE}"
        --label "build.phase=dep-runtime"
        --label "build.timestamp=${BUILD_TIMESTAMP}"
    )
    if [ -n "${DEPLOYMENT_CASE}" ]; then
        RUNTIME_ARGS+=(--label "build.deployment-case=${DEPLOYMENT_CASE}")
    fi
    if [ "${NO_CACHE}" = "true" ]; then
        RUNTIME_ARGS+=(--no-cache)
    fi
    RUNTIME_ARGS+=(-t "${RUNTIME_TAG}")

    echo "Building runtime stage FROM deps..."
    echo "  Using deps image: ${DEPS_IMAGE_TAG}"
    echo "  Output tag: ${RUNTIME_TAG}"
    echo ""

    if DOCKER_BUILDKIT=0 docker build "${RUNTIME_ARGS[@]}" .; then
        echo ""
        echo "✅ dep-runtime: Runtime image built successfully: ${RUNTIME_TAG}"
        docker images "${RUNTIME_TAG}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
        docker tag "${RUNTIME_TAG}" "${IMAGE_TAG}-runtime" 2>/dev/null || true
        echo ""
        echo "ℹ️  Runtime image also tagged as: ${IMAGE_TAG}-runtime"
    else
        echo ""
        echo "❌ dep-runtime: Runtime build failed"
        exit 1
    fi
fi

# runtime-only: Build runtime FROM existing deps or build image
if [ "${BUILD_PHASE}" = "runtime" ]; then
    echo ""
    echo "=========================================="
    echo "runtime: Building Runtime Image FROM ${DEPS_IMAGE}"
    echo "=========================================="
    echo ""

    if ! docker image inspect "${DEPS_IMAGE}" >/dev/null 2>&1; then
        echo "Error: Source image not found: ${DEPS_IMAGE}"
        exit 1
    fi

    BUILD_TIMESTAMP="${BUILD_TIMESTAMP:-$(date -u +'%Y%m%d%H%M')}"
    if [ -z "${RUNTIME_TAG}" ]; then
        if [ -n "${DEFAULT_RUNTIME_TAG_FORMAT:-}" ]; then
            RUNTIME_TAG="${DEFAULT_RUNTIME_TAG_FORMAT}-${BUILD_TIMESTAMP}"
        elif [[ "${IMAGE_TAG}" == *":"* ]]; then
            RUNTIME_REPO="${IMAGE_TAG%%:*}"
            RUNTIME_TAG="${RUNTIME_REPO}:runtime-${BUILD_TIMESTAMP}"
        else
            RUNTIME_TAG="${IMAGE_TAG}-runtime-${BUILD_TIMESTAMP}"
        fi
    fi

    RUNTIME_DOCKERFILE="${PROJECT_ROOT}/docker/Dockerfile.runtime"
    if [ ! -f "${RUNTIME_DOCKERFILE}" ]; then
        echo "Error: Runtime Dockerfile not found: ${RUNTIME_DOCKERFILE}"
        exit 1
    fi

    RUNTIME_ARGS=(
        -f "${RUNTIME_DOCKERFILE}"
        --build-arg "BUILD_IMAGE=${DEPS_IMAGE}"
        --build-arg "BUILD_TIMESTAMP=${BUILD_TIMESTAMP}"
        --build-arg "DEPLOYMENT_CASE=${DEPLOYMENT_CASE}"
        --progress "${PROGRESS_TYPE:-auto}"
    )
    RUNTIME_ARGS+=(
        --label "build.date=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
        --label "build.base-image=${BASE_IMAGE}"
        --label "build.phase=runtime"
        --label "build.timestamp=${BUILD_TIMESTAMP}"
    )
    if [ -n "${DEPLOYMENT_CASE}" ]; then
        RUNTIME_ARGS+=(--label "build.deployment-case=${DEPLOYMENT_CASE}")
    fi
    if [ "${NO_CACHE}" = "true" ]; then
        RUNTIME_ARGS+=(--no-cache)
    fi
    RUNTIME_ARGS+=(-t "${RUNTIME_TAG}")

    echo "Building runtime stage FROM ${DEPS_IMAGE}..."
    echo "  Output tag: ${RUNTIME_TAG}"
    echo ""

    if DOCKER_BUILDKIT=0 docker build "${RUNTIME_ARGS[@]}" .; then
        echo ""
        echo "✅ runtime: Runtime image built successfully: ${RUNTIME_TAG}"
        docker images "${RUNTIME_TAG}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
        docker tag "${RUNTIME_TAG}" "${IMAGE_TAG}-runtime" 2>/dev/null || true
        echo ""
        echo "ℹ️  Runtime image also tagged as: ${IMAGE_TAG}-runtime"
    else
        echo ""
        echo "❌ runtime: Runtime build failed"
        exit 1
    fi
fi

# Phase 2: Build from sources (build-runtime path only)
if [ "${BUILD_PHASE}" = "build-runtime" ]; then
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
    PHASE2_DOCKERFILE="${PROJECT_ROOT}/docker/Dockerfile.build"
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

    # Function to sync external repo into build context
    sync_repo_into_context() {
        local external_path="$1"
        local repo_name="$2"
        local context_dest="${PROJECT_ROOT}/${repo_name}"

        if [ ! -d "${external_path}" ]; then
            echo "  Warning: ${repo_name} path does not exist: ${external_path}"
            return 1
        fi

        echo "  Cleaning build context for ${repo_name} before syncing..."
        # Remove existing directory to ensure clean sync (no stale files)
        # Use multiple attempts to ensure complete removal, including sudo for root-owned files
        if [ -e "${context_dest}" ]; then
            # First attempt: standard removal
            rm -rf "${context_dest}" 2>/dev/null || true
            # Wait a moment for filesystem to sync
            sleep 0.1
            # Second attempt: if still exists, make writable and remove
            if [ -e "${context_dest}" ]; then
                chmod -R u+w "${context_dest}" 2>/dev/null || true
                rm -rf "${context_dest}" 2>/dev/null || true
                sleep 0.1
            fi
            # Third attempt: if still exists, try with sudo (for root-owned files from Docker)
            if [ -e "${context_dest}" ]; then
                echo "  Warning: Standard removal failed, trying sudo for root-owned files..."
                sudo rm -rf "${context_dest}" 2>/dev/null || true
                sleep 0.1
            fi
            # Fourth attempt: if still exists, use find to delete files/dirs individually
            if [ -e "${context_dest}" ]; then
                echo "  Warning: Using find to clean ${context_dest}..."
                find "${context_dest}" -type f -exec rm -f {} + 2>/dev/null || \
                    sudo find "${context_dest}" -type f -exec rm -f {} + 2>/dev/null || true
                find "${context_dest}" -type d -exec rmdir {} + 2>/dev/null || \
                    sudo find "${context_dest}" -type d -exec rmdir {} + 2>/dev/null || true
                # Final removal attempt
                rm -rf "${context_dest}" 2>/dev/null || sudo rm -rf "${context_dest}" 2>/dev/null || true
            fi
            # Verify removal succeeded
            if [ -e "${context_dest}" ]; then
                echo "  Error: Failed to remove ${context_dest}, sync may contain stale files"
                return 1
            fi
        fi

        echo "  Cleaning root-owned files in source directory before syncing..."
        # Remove root-owned files/dirs that may have been created by Docker (try without sudo first)
        if [ -d "${external_path}/python/infinicore/lib" ]; then
            rm -rf "${external_path}/python/infinicore/lib" 2>/dev/null || \
                sudo rm -rf "${external_path}/python/infinicore/lib" 2>/dev/null || true
        fi
        find "${external_path}/scripts" -name "*.backup" -type f -delete 2>/dev/null || \
            sudo find "${external_path}/scripts" -name "*.backup" -type f -delete 2>/dev/null || true

        echo "  Syncing ${repo_name} from ${external_path} into build context..."
        # Ensure destination directory exists (rsync will create it, but be explicit)
        mkdir -p "${context_dest}"
        # Use rsync to copy, excluding .git and build artifacts for faster sync
        # --delete ensures files in dest that don't exist in source are removed
        # Trailing slashes mean: copy contents of source into dest
        if command -v rsync >/dev/null 2>&1; then
            rsync -a --delete \
                --exclude='.xmake' \
                --exclude='build' \
                --exclude='target' \
                --exclude='__pycache__' \
                --exclude='*.pyc' \
                --exclude='.pytest_cache' \
                --exclude='*.backup' \
                --exclude='python/infinicore/lib' \
                "${external_path}/" "${context_dest}/"
        else
            # Fallback to cp if rsync not available
            # Ensure destination doesn't exist first
            [ -e "${context_dest}" ] && rm -rf "${context_dest}"
            cp -r "${external_path}" "${context_dest}"
        fi
        echo "  ✓ ${repo_name} synced to ${context_dest}"
        return 0
    }

    # Check if external repos are provided and outside build context
    # If so, sync them into the build context so Docker can access them
    INFINICORE_SRC_ORIG="${INFINICORE_SRC}"
    INFINILM_SRC_ORIG="${INFINILM_SRC}"

    # Handle InfiniCore: sync external path into build context if needed
    if [ -n "${INFINICORE_SRC}" ]; then
        case "${INFINICORE_SRC}" in
            "/app/../InfiniCore"|"../InfiniCore"|"/app/InfiniCore"|"./InfiniCore"|"InfiniCore")
                # Already in build context, use as-is
                : ;;
            *)
                # External path - check if it's absolute and outside build context
                if [[ "${INFINICORE_SRC}" == /* ]] && [[ "${INFINICORE_SRC}" != "${PROJECT_ROOT}"* ]]; then
                    # Sync into build context
                    if sync_repo_into_context "${INFINICORE_SRC}" "InfiniCore"; then
                        INFINICORE_SRC="InfiniCore"
                    else
                        echo "  Warning: Failed to sync InfiniCore, using from deps image instead"
                        INFINICORE_SRC=""
                    fi
                elif [ -d "${INFINICORE_SRC}" ]; then
                    # Relative path that exists - try to sync
                    local abs_path="$(cd "${INFINICORE_SRC}" 2>/dev/null && pwd || echo "${INFINICORE_SRC}")"
                    if [[ "${abs_path}" != "${PROJECT_ROOT}"* ]]; then
                        if sync_repo_into_context "${abs_path}" "InfiniCore"; then
                            INFINICORE_SRC="InfiniCore"
                        else
                            echo "  Warning: Failed to sync InfiniCore, using from deps image instead"
                            INFINICORE_SRC=""
                        fi
                    else
                        # Path is inside project root, use relative path
                        INFINICORE_SRC="${INFINICORE_SRC#${PROJECT_ROOT}/}"
                    fi
                else
                    echo "  Note: InfiniCore path ${INFINICORE_SRC} not found, using from deps image instead"
                    INFINICORE_SRC=""
                fi
                ;;
        esac
    fi

    # Handle InfiniLM: sync external path into build context if needed
    if [ -n "${INFINILM_SRC}" ]; then
        case "${INFINILM_SRC}" in
            "/app/../InfiniLM"|"../InfiniLM"|"/app/InfiniLM"|"./InfiniLM"|"InfiniLM")
                # Already in build context, use as-is
                : ;;
            *)
                # External path - check if it's absolute and outside build context
                if [[ "${INFINILM_SRC}" == /* ]] && [[ "${INFINILM_SRC}" != "${PROJECT_ROOT}"* ]]; then
                    # Sync into build context
                    if sync_repo_into_context "${INFINILM_SRC}" "InfiniLM"; then
                        INFINILM_SRC="InfiniLM"
                    else
                        echo "  Warning: Failed to sync InfiniLM, using from deps image instead"
                        INFINILM_SRC=""
                    fi
                elif [ -d "${INFINILM_SRC}" ]; then
                    # Relative path that exists - try to sync
                    local abs_path="$(cd "${INFINILM_SRC}" 2>/dev/null && pwd || echo "${INFINILM_SRC}")"
                    if [[ "${abs_path}" != "${PROJECT_ROOT}"* ]]; then
                        if sync_repo_into_context "${abs_path}" "InfiniLM"; then
                            INFINILM_SRC="InfiniLM"
                        else
                            echo "  Warning: Failed to sync InfiniLM, using from deps image instead"
                            INFINILM_SRC=""
                        fi
                    else
                        # Path is inside project root, use relative path
                        INFINILM_SRC="${INFINILM_SRC#${PROJECT_ROOT}/}"
                    fi
                else
                    echo "  Note: InfiniLM path ${INFINILM_SRC} not found, using from deps image instead"
                    INFINILM_SRC=""
                fi
                ;;
        esac
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
    # When INFINICORE_SRC is set (external/synced source), pass INFINICORE_BRANCH=__USE_SRC_AS_IS__
    # so install.sh skips git checkout and uses the provided tree (e.g. issue/1004) as-is.
    if [ -n "${INFINICORE_SRC}" ]; then
        PHASE2_ARGS+=(--build-arg "INFINICORE_SRC=${INFINICORE_SRC}")
        PHASE2_ARGS+=(--build-arg "INFINICORE_BRANCH=__USE_SRC_AS_IS__")
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

    echo "Command: DOCKER_BUILDKIT=0 docker build ${PHASE2_ARGS[*]} ."
    echo ""

    if DOCKER_BUILDKIT=0 docker build "${PHASE2_ARGS[@]}" .; then
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
    # Use a separate runtime-only Dockerfile to avoid rebuilding the build stage
    echo ""
    echo "=========================================="
    echo "Phase 2 (continued): Building Runtime Image"
    echo "=========================================="
    echo ""

    # Generate timestamp tag (default: minute precision)
    BUILD_TIMESTAMP="${BUILD_TIMESTAMP:-$(date -u +'%Y%m%d%H%M')}"

    # Generate runtime tag with timestamp
    if [ -z "${RUNTIME_TAG}" ]; then
        # Use DEFAULT_RUNTIME_TAG_FORMAT from install.defaults.sh if available
        if [ -n "${DEFAULT_RUNTIME_TAG_FORMAT:-}" ]; then
            # Append timestamp to the format: <format>-<timestamp>
            RUNTIME_TAG="${DEFAULT_RUNTIME_TAG_FORMAT}-${BUILD_TIMESTAMP}"
        # Otherwise, extract repository and base tag from IMAGE_TAG
        elif [[ "${IMAGE_TAG}" == *":"* ]]; then
            RUNTIME_REPO="${IMAGE_TAG%%:*}"
            RUNTIME_TAG="${RUNTIME_REPO}:runtime-${BUILD_TIMESTAMP}"
        else
            RUNTIME_TAG="${IMAGE_TAG}-runtime-${BUILD_TIMESTAMP}"
        fi
    fi

    # Build args for runtime stage
    # Use the runtime Dockerfile to avoid rebuilding the build stage
    # This directly uses the build image without re-evaluating build steps
    RUNTIME_DOCKERFILE="${PROJECT_ROOT}/docker/Dockerfile.runtime"
    if [ ! -f "${RUNTIME_DOCKERFILE}" ]; then
        echo "Error: Runtime Dockerfile not found: ${RUNTIME_DOCKERFILE}"
        exit 1
    fi

    RUNTIME_ARGS=(
        -f "${RUNTIME_DOCKERFILE}"
        --build-arg "BUILD_IMAGE=${IMAGE_TAG}"
        --build-arg "BUILD_TIMESTAMP=${BUILD_TIMESTAMP}"
        --build-arg "DEPLOYMENT_CASE=${DEPLOYMENT_CASE}"
        --progress "${PROGRESS_TYPE:-auto}"
    )

    # Add labels
    RUNTIME_ARGS+=(
        --label "build.date=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
        --label "build.base-image=${BASE_IMAGE}"
        --label "build.phase=build-runtime"
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

    echo "Building runtime stage FROM build (for deployment)..."
    echo "  Using build image: ${IMAGE_TAG}"
    echo "  Base image: ${BASE_IMAGE}"
    echo "  Timestamp: ${BUILD_TIMESTAMP}"
    echo "  Output tag: ${RUNTIME_TAG}"
    echo "Command: DOCKER_BUILDKIT=0 docker build ${RUNTIME_ARGS[*]} ."
    echo ""

    if DOCKER_BUILDKIT=0 docker build "${RUNTIME_ARGS[@]}" .; then
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

# Push if requested
if [ "${PUSH_IMAGE}" = "true" ]; then
    echo ""
    echo "=========================================="
    echo "Pushing Images to Registry"
    echo "=========================================="
    echo ""

    # dep-runtime: push deps and runtime (we built both)
    if [ "${BUILD_PHASE}" = "dep-runtime" ]; then
        FULL_DEPS_TAG="${REGISTRY}/${DEPS_IMAGE_TAG}"
        echo "Pushing deps image..."
        docker tag "${DEPS_IMAGE_TAG}" "${FULL_DEPS_TAG}"
        if docker push "${FULL_DEPS_TAG}"; then
            echo "✅ Deps image pushed: ${FULL_DEPS_TAG}"
        else
            echo "❌ Failed to push deps image: ${FULL_DEPS_TAG}"
            exit 1
        fi
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

    # build-runtime: push deps if we built it, build, and runtime
    if [ "${BUILD_PHASE}" = "build-runtime" ]; then
        if [ -z "${DEPS_IMAGE_PROVIDED_BY_USER}" ]; then
            FULL_DEPS_TAG="${REGISTRY}/${DEPS_IMAGE_TAG}"
            echo "Pushing deps image..."
            docker tag "${DEPS_IMAGE_TAG}" "${FULL_DEPS_TAG}"
            if docker push "${FULL_DEPS_TAG}"; then
                echo "✅ Deps image pushed: ${FULL_DEPS_TAG}"
            else
                echo "❌ Failed to push deps image: ${FULL_DEPS_TAG}"
                exit 1
            fi
        fi
        FULL_TAG="${REGISTRY}/${IMAGE_TAG}"
        echo "Pushing build image..."
        docker tag "${IMAGE_TAG}" "${FULL_TAG}"
        if docker push "${FULL_TAG}"; then
            echo "✅ Build image pushed: ${FULL_TAG}"
        else
            echo "❌ Failed to push build image: ${FULL_TAG}"
            exit 1
        fi
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

    # runtime: push runtime image only
    if [ "${BUILD_PHASE}" = "runtime" ] && [ -n "${RUNTIME_TAG}" ]; then
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

echo ""
echo "=========================================="
echo "Build completed successfully!"
echo "=========================================="
echo ""

if [ "${BUILD_PHASE}" = "dep-runtime" ]; then
    echo "dep-runtime: deps image ${DEPS_IMAGE_TAG}, runtime image ${RUNTIME_TAG}"
    echo ""
    echo "To use the runtime image (recommended for deployment):"
    echo "  export IMAGE_NAME=${RUNTIME_TAG}"
    echo "  ./start-master.sh <MASTER_IP>"
    echo ""
    echo "Or use the convenience tag:"
    echo "  export IMAGE_NAME=${IMAGE_TAG}-runtime"
    echo "  ./start-master.sh <MASTER_IP>"
elif [ "${BUILD_PHASE}" = "build-runtime" ]; then
    echo "build-runtime: build image ${IMAGE_TAG}, runtime image ${RUNTIME_TAG}"
    echo ""
    echo "To use the runtime image (recommended for deployment):"
    echo "  export IMAGE_NAME=${RUNTIME_TAG}"
    echo "  ./start-master.sh <MASTER_IP>"
    echo ""
    echo "Or use the convenience tag:"
    echo "  export IMAGE_NAME=${IMAGE_TAG}-runtime"
    echo "  ./start-master.sh <MASTER_IP>"
    if [ -z "${DEPS_IMAGE_PROVIDED_BY_USER}" ]; then
        echo ""
        echo "To reuse deps for faster rebuilds:"
        echo "  $0 --phase build-runtime --deps-image ${DEPS_IMAGE_TAG} --infinilm-src /path/to/InfiniLM"
    fi
elif [ "${BUILD_PHASE}" = "runtime" ]; then
    echo "runtime: runtime image ${RUNTIME_TAG} (from ${DEPS_IMAGE})"
    echo ""
    echo "To use the runtime image (recommended for deployment):"
    echo "  export IMAGE_NAME=${RUNTIME_TAG}"
    echo "  ./start-master.sh <MASTER_IP>"
    echo ""
    echo "Or use the convenience tag:"
    echo "  export IMAGE_NAME=${IMAGE_TAG}-runtime"
    echo "  ./start-master.sh <MASTER_IP>"
fi

echo ""
