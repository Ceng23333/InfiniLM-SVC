#!/usr/bin/env bash
# Incremental build script for InfiniLM-SVC
# Creates a container from existing image, reinstalls InfiniLM-SVC, and commits as new image
# This avoids rebuilding everything from scratch and is faster for code updates

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Default values
SOURCE_IMAGE="${SOURCE_IMAGE:-infinilm-svc:infinilm-demo}"
NEW_TAG="${NEW_TAG:-infinilm-svc:infinilm-demo}"
CONTAINER_NAME="infinilm-svc-build-$(date +%s)"

usage() {
    cat <<EOF
Incremental build script for InfiniLM-SVC

Usage:
  $0 [OPTIONS]

Options:
  --source-image IMAGE    Source image to use as base (default: infinilm-svc:infinilm-demo)
  --tag TAG              Output image tag (default: infinilm-svc:infinilm-demo)
  --container-name NAME  Container name (default: auto-generated)
  -h, --help             Show this help message

Examples:
  # Use yesterday's image and rebuild
  $0 --source-image infinilm-svc:infinilm-demo

  # Use specific image tag
  $0 --source-image infinilm-svc:infinilm-demo-20260202 --tag infinilm-svc:infinilm-demo-latest
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --source-image)
            SOURCE_IMAGE="$2"
            shift 2
            ;;
        --tag)
            NEW_TAG="$2"
            shift 2
            ;;
        --container-name)
            CONTAINER_NAME="$2"
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

echo "=========================================="
echo "Incremental Build: InfiniLM-SVC"
echo "=========================================="
echo "Source image: ${SOURCE_IMAGE}"
echo "Output tag: ${NEW_TAG}"
echo "Container name: ${CONTAINER_NAME}"
echo "Project root: ${PROJECT_ROOT}"
echo ""

# Check if source image exists
if ! docker image inspect "${SOURCE_IMAGE}" >/dev/null 2>&1; then
    echo "Error: Source image '${SOURCE_IMAGE}' not found"
    echo "Available images:"
    docker images | grep infinilm-svc || echo "  (none found)"
    exit 1
fi

# Clean up any existing container with same name
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Removing existing container: ${CONTAINER_NAME}"
    docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
fi

echo "Step 1: Creating container from source image..."
# Override entrypoint to prevent services from starting during build
# Use sleep infinity to keep container running
docker create \
    --name "${CONTAINER_NAME}" \
    --workdir /app \
    --entrypoint /bin/bash \
    "${SOURCE_IMAGE}" \
    -c "sleep infinity"

echo "Step 2: Copying latest code changes to container..."
# Copy the entire project (Docker will handle incremental copy efficiently)
docker cp "${PROJECT_ROOT}/." "${CONTAINER_NAME}:/app/"

echo "Step 3: Starting container..."
docker start "${CONTAINER_NAME}"

# Wait a moment for container to be ready
sleep 2

echo "Step 4: Reinstalling InfiniLM-SVC..."
docker exec "${CONTAINER_NAME}" /bin/bash -c "
    set -e
    cd /app
    echo '=========================================='
    echo 'Reinstalling InfiniLM-SVC'
    echo '=========================================='
    echo ''

    # Run install script to rebuild ONLY Rust binaries (InfiniLM-SVC)
    # Skip InfiniCore/InfiniLM rebuild since they're already in the base image
    # This makes incremental builds much faster
    ./scripts/install.sh \
        --install-path /usr/local/bin \
        --deployment-case infinilm-metax-deployment \
        --install-infinicore false \
        --install-infinilm false \
        --infinicore-src /workspace/InfiniCore \
        --infinilm-src /workspace/InfiniLM

    echo ''
    echo '=========================================='
    echo 'Verifying installation...'
    echo '=========================================='
    which infini-registry || echo 'Warning: infini-registry not found'
    which infini-router || echo 'Warning: infini-router not found'
    which infini-babysitter || echo 'Warning: infini-babysitter not found'

    echo ''
    echo '=========================================='
    echo 'Installation complete!'
    echo '=========================================='
"

if [ $? -eq 0 ]; then
    echo ""
    echo "Step 5: Committing container as new image..."
    docker commit \
        --change 'WORKDIR /app' \
        --change 'ENTRYPOINT ["/bin/bash", "/app/docker_entrypoint.sh"]' \
        "${CONTAINER_NAME}" \
        "${NEW_TAG}"

    echo ""
    echo "Step 6: Cleaning up container..."
    docker stop "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    docker rm "${CONTAINER_NAME}" >/dev/null 2>&1 || true

    echo ""
    echo "✅ Image built successfully: ${NEW_TAG}"
    echo ""
    echo "Image information:"
    docker images "${NEW_TAG}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
    echo ""
    echo "To use this image:"
    echo "  export IMAGE_NAME=${NEW_TAG}"
    echo "  ./start-master.sh <MASTER_IP>"
    echo ""
else
    echo ""
    echo "❌ Build failed"
    echo "Container ${CONTAINER_NAME} is kept for debugging"
    echo "To inspect: docker exec -it ${CONTAINER_NAME} /bin/bash"
    exit 1
fi
