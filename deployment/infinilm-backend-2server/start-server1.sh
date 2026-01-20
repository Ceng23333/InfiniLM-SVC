#!/usr/bin/env bash
# Start Server 1: Registry, Router, Babysitter A (InfiniLM backend)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER1_IP="${1:-localhost}"

IMAGE_NAME="${IMAGE_NAME:-infinilm-svc:infinilm-demo}"
USE_HOST_NETWORK="${USE_HOST_NETWORK:-true}"

INFINILM_DIR="${INFINILM_DIR:-}"
MODEL_DIR="${MODEL_DIR:-}"

if [ -z "${INFINILM_DIR}" ] || [ ! -d "${INFINILM_DIR}" ]; then
  echo "Error: INFINILM_DIR must point to an InfiniLM checkout on this host."
  echo "  Example: export INFINILM_DIR=/path/to/InfiniLM"
  exit 1
fi

if [ -z "${MODEL_DIR}" ] || [ ! -d "${MODEL_DIR}" ]; then
  echo "Error: MODEL_DIR must point to the model directory on this host."
  echo "  Example: export MODEL_DIR=/path/to/model_dir"
  exit 1
fi

echo "=========================================="
echo "Starting InfiniLM-SVC Server 1 (InfiniLM backend)"
echo "=========================================="
echo "Server IP: ${SERVER1_IP}"
echo "Image: ${IMAGE_NAME}"
echo "Components: Registry, Router, Babysitter A"
echo "Docker network: $([ "${USE_HOST_NETWORK}" = "true" ] && echo "host" || echo "bridge (-p ports)")"
echo "INFINILM_DIR: ${INFINILM_DIR}"
echo "MODEL_DIR: ${MODEL_DIR}"
echo ""

# Remove existing container if present
if docker ps -a --format '{{.Names}}' | grep -q "^infinilm-svc-infinilm-server1$"; then
  echo "Removing existing container infinilm-svc-infinilm-server1 ..."
  docker rm -f infinilm-svc-infinilm-server1 >/dev/null
fi

echo "🚀 Starting Docker container..."
if [ "${USE_HOST_NETWORK}" = "true" ]; then
  docker run -d \
    --network host \
    --name infinilm-svc-infinilm-server1 \
    -e LAUNCH_COMPONENTS=all \
    -e REGISTRY_PORT=18000 \
    -e ROUTER_PORT=8000 \
    -e BABYSITTER_CONFIGS="babysitter-a.toml" \
    -v "${SCRIPT_DIR}/config:/app/config:ro" \
    -v "${INFINILM_DIR}:/mnt/InfiniLM:ro" \
    -v "${MODEL_DIR}:/models/model:ro" \
    "${IMAGE_NAME}"
else
  docker run -d \
    --name infinilm-svc-infinilm-server1 \
    -e LAUNCH_COMPONENTS=all \
    -e REGISTRY_PORT=18000 \
    -e ROUTER_PORT=8000 \
    -e BABYSITTER_CONFIGS="babysitter-a.toml" \
    -p 18000:18000 \
    -p 8000:8000 \
    -p 8100:8100 -p 8101:8101 \
    -v "${SCRIPT_DIR}/config:/app/config:ro" \
    -v "${INFINILM_DIR}:/mnt/InfiniLM:ro" \
    -v "${MODEL_DIR}:/models/model:ro" \
    "${IMAGE_NAME}"
fi

echo ""
echo "✅ Server 1 container started: infinilm-svc-infinilm-server1"
echo "Registry: http://${SERVER1_IP}:18000"
echo "Router:   http://${SERVER1_IP}:8000"
echo ""
echo "Logs: docker logs -f infinilm-svc-infinilm-server1"
