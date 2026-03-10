#!/usr/bin/env bash
# Build InfiniLM-SVC image for 9g_8b case (NVIDIA platform)
# Base image: nvcr.io/nvidia/pytorch:25.12-py3
#
# Usage:
#   ./build-image.sh [OPTIONS]
#   Run from project root: docker/nvidia/build-image.sh
#
# Options:
#   --proxy PROXY    Set HTTP/HTTPS proxy (default: http://127.0.0.1:7890 if env unset)
#   --base-image IMAGE  Override base image
#   --no-cache       Build without cache
#   -h, --help       Show help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# docker/nvidia -> go up 2 levels to project root (InfiniLM-SVC)
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

DEFAULT_BASE_IMAGE="nvcr.io/nvidia/pytorch:25.12-py3"
BASE_IMAGE="${BASE_IMAGE:-${DEFAULT_BASE_IMAGE}}"
# Default: unique tag with timestamp; also tag as infinilm-svc:nvidia for deps reuse
IMAGE_TAG="${IMAGE_TAG:-infinilm-svc:nvidia-$(date +%Y%m%d-%H%M%S)}"
NO_CACHE=""
# Accept a --phase flag (for compatibility with metax build script),
# but this simple NVIDIA builder is effectively single-phase.
PHASE="${PHASE:-runtime}"

# Proxy: honor existing env, but do NOT default to localhost:7890
HTTP_PROXY="${HTTP_PROXY:-${http_proxy:-}}"
HTTPS_PROXY="${HTTPS_PROXY:-${https_proxy:-}}"

while [[ $# -gt 0 ]]; do
  case $1 in
    --proxy)
      HTTP_PROXY="$2"
      HTTPS_PROXY="$2"
      shift 2
      ;;
    --base-image)
      BASE_IMAGE="$2"
      shift 2
      ;;
    --phase)
      # Keep for CLI compatibility; this script always builds the single NVIDIA image.
      PHASE="$2"
      shift 2
      ;;
    --no-cache)
      NO_CACHE="--no-cache"
      shift
      ;;
    # Compatibility options (accepted but ignored)
    --deps-image)
      DEPS_IMAGE="$2"
      shift 2
      ;;
    --infinilm-src)
      INFINILM_SRC="$2"
      shift 2
      ;;
    --infinicore-src)
      INFINICORE_SRC="$2"
      shift 2
      ;;
    --deployment-case)
      DEPLOYMENT_CASE="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--proxy PROXY] [--base-image IMAGE] [--no-cache] [--phase PHASE] [--deps-image IMAGE] [--infinilm-src PATH] [--infinicore-src PATH] [--deployment-case NAME]"
      echo "  --proxy PROXY         HTTP/HTTPS proxy (default: http://127.0.0.1:7890)"
      echo "  --base-image IMAGE    Base image (default: ${DEFAULT_BASE_IMAGE})"
      echo "  --no-cache            Build without cache"
      echo "  --phase PHASE         Ignored (compatibility only)"
      echo "  --deps-image IMAGE    Use as base image (e.g. infinilm-svc:nvidia)"
      echo "  --infinilm-src PATH   Ignored (compatibility only)"
      echo "  --infinicore-src PATH Ignored (compatibility only)"
      echo "  --deployment-case NAME Ignored (compatibility only)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# When --deps-image is provided, use it as the base image (e.g. pre-built infinilm-svc:nvidia)
if [ -n "${DEPS_IMAGE:-}" ]; then
  BASE_IMAGE="${DEPS_IMAGE}"
  echo "Using deps image as base: ${BASE_IMAGE}"
fi

# When proxy is localhost, use --network host so build container can reach host proxy
BUILD_ARGS=(
  -f "${PROJECT_ROOT}/deployment/cases/9g_8b/Dockerfile.nvidia"
  -t "${IMAGE_TAG}"
  --build-arg "BASE_IMAGE=${BASE_IMAGE}"
  --build-arg "HTTP_PROXY=${HTTP_PROXY}"
  --build-arg "HTTPS_PROXY=${HTTPS_PROXY}"
  --build-arg "http_proxy=${HTTP_PROXY}"
  --build-arg "https_proxy=${HTTPS_PROXY}"
)
[ -n "${NO_CACHE}" ] && BUILD_ARGS+=("${NO_CACHE}")

if echo "${HTTP_PROXY}${HTTPS_PROXY}" | grep -qE "127\.0\.0\.1|localhost"; then
  echo "Using --network host for Docker build (proxy is localhost)"
  BUILD_ARGS+=(--network host)
fi

echo "Building ${IMAGE_TAG}..."
echo "  Base image: ${BASE_IMAGE}"
echo "  Proxy: ${HTTP_PROXY}"
echo "  Context: ${PROJECT_ROOT}"
docker build "${BUILD_ARGS[@]}" "${PROJECT_ROOT}"
echo "✅ Built ${IMAGE_TAG}"
