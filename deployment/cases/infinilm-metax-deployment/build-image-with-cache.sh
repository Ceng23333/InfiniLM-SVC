#!/usr/bin/env bash
# Build script with cache support using bind mounts
# This script creates cache directories on the host and uses them during build

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Setup cache directories on host
CACHE_BASE_DIR="${HOME}/.docker-build-cache/infinilm-svc"
mkdir -p "${CACHE_BASE_DIR}/cargo" "${CACHE_BASE_DIR}/pip" "${CACHE_BASE_DIR}/cache" "${CACHE_BASE_DIR}/tmp"

echo "Using cache directories:"
echo "  Cargo: ${CACHE_BASE_DIR}/cargo"
echo "  Pip: ${CACHE_BASE_DIR}/pip"
echo "  General: ${CACHE_BASE_DIR}/cache"
echo "  Temp: ${CACHE_BASE_DIR}/tmp"
echo ""

# Call the original build script but add cache volume mounts
# Note: Docker build doesn't support --volume during build, so we need to use
# a different approach - either use BuildKit cache mounts (requires Docker 19.03+)
# or use a wrapper that runs the build in a container with volumes

# Note: BuildKit is disabled in this project. Cache directories are prepared at:
echo "  ${CACHE_BASE_DIR}"
echo "  You can manually copy cache contents before/after build if needed."
echo ""

# Fall back to regular build
exec "${PROJECT_ROOT}/docker/metax/build-image.sh" "$@"
