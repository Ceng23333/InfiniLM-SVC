#!/usr/bin/env bash
# Start Server 1: Registry, Router, Babysitter A (InfiniLM backend)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER1_IP="${1:-localhost}"

IMAGE_NAME="${IMAGE_NAME:-infinilm-svc:infinilm-demo}"

INFINILM_DIR="${INFINILM_DIR:-}"
MODEL1_DIR="${MODEL1_DIR:-}"
MODEL2_DIR="${MODEL2_DIR:-}"

if [ -z "${INFINILM_DIR}" ] || [ ! -d "${INFINILM_DIR}" ]; then
  echo "Error: INFINILM_DIR must point to an InfiniLM checkout on this host."
  echo "  Example: export INFINILM_DIR=/path/to/InfiniLM"
  exit 1
fi

if [ -z "${MODEL1_DIR}" ] || [ ! -d "${MODEL1_DIR}" ]; then
  echo "Error: MODEL1_DIR must point to the 9g8b model directory on this host."
  echo "  Example: export MODEL1_DIR=/path/to/9g8b_model_dir"
  exit 1
fi

if [ -z "${MODEL2_DIR}" ] || [ ! -d "${MODEL2_DIR}" ]; then
  echo "Error: MODEL2_DIR must point to the Qwen3 model directory on this host."
  echo "  Example: export MODEL2_DIR=/path/to/qwen3_model_dir"
  exit 1
fi

echo "=========================================="
echo "Starting InfiniLM-SVC Server 1 (InfiniLM backend)"
echo "=========================================="
echo "Server IP: ${SERVER1_IP}"
echo "Image: ${IMAGE_NAME}"
echo "Components: Registry, Router, Babysitter A"
echo "INFINILM_DIR: ${INFINILM_DIR}"
echo "MODEL1_DIR: ${MODEL1_DIR}"
echo "MODEL2_DIR: ${MODEL2_DIR}"
echo ""

# Remove existing container if present
if docker ps -a --format '{{.Names}}' | grep -q "^infinilm-svc-infinilm-server1$"; then
  echo "Removing existing container infinilm-svc-infinilm-server1 ..."
  docker rm -f infinilm-svc-infinilm-server1 >/dev/null
fi

echo "🚀 Starting Docker container..."
docker run -d \
  --network host \
  --uts host \
  --ipc host \
  --device /dev/dri \
  --device /dev/htcd \
  --device /dev/infiniband \
  --group-add video \
  --privileged=true \
  --security-opt apparmor=unconfined \
  --shm-size 100gb \
  --ulimit memlock=-1 \
  --name infinilm-svc-infinilm-server1 \
  -e LAUNCH_COMPONENTS=all \
  -e REGISTRY_PORT=18000 \
  -e ROUTER_PORT=8000 \
  -e BABYSITTER_CONFIGS="babysitter-a.toml" \
  -v "${SCRIPT_DIR}/config:/app/config:ro" \
  -v "${INFINILM_DIR}:/mnt/InfiniLM:ro" \
  -v "${MODEL1_DIR}:/models/9g_8b_thinking_llama:ro" \
  -v "${MODEL2_DIR}:/models/Qwen3-32B:ro" \
  "${IMAGE_NAME}"

echo ""
echo "✅ Server 1 container started: infinilm-svc-infinilm-server1"
echo "Registry: http://${SERVER1_IP}:18000"
echo "Router:   http://${SERVER1_IP}:8000"
echo ""
echo "Logs: docker logs -f infinilm-svc-infinilm-server1"
