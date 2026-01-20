#!/usr/bin/env bash
# Start Server 2: Babysitter C and D (InfiniLM backends) registering to Server 1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-infinilm-svc:infinilm-demo}"

if [ $# -lt 2 ]; then
  echo "Usage: $0 <SERVER1_IP> <SERVER2_IP>"
  exit 1
fi

SERVER1_IP="$1"
SERVER2_IP="$2"

INFINILM_DIR="${INFINILM_DIR:-}"
INFINICORE_DIR="${INFINICORE_DIR:-}"
MODEL1_DIR="${MODEL1_DIR:-}"
MODEL2_GGUF="${MODEL2_GGUF:-}"

if [ -z "${INFINILM_DIR}" ] || [ ! -d "${INFINILM_DIR}" ]; then
  echo "Error: INFINILM_DIR must point to an InfiniLM checkout on this host."
  echo "  Example: export INFINILM_DIR=/path/to/InfiniLM"
  exit 1
fi

if [ -z "${INFINICORE_DIR}" ] || [ ! -d "${INFINICORE_DIR}" ]; then
  echo "Error: INFINICORE_DIR must point to an InfiniCore checkout on this host."
  echo "  Example: export INFINICORE_DIR=/path/to/InfiniCore"
  exit 1
fi

if [ -z "${MODEL1_DIR}" ] || [ ! -d "${MODEL1_DIR}" ]; then
  echo "Error: MODEL1_DIR must point to the 9g8b model directory on this host."
  echo "  Example: export MODEL1_DIR=/path/to/9g8b_model_dir"
  exit 1
fi

if [ -z "${MODEL2_GGUF}" ]; then
  echo "Error: MODEL2_GGUF must point to the Qwen3 gguf model file on this host."
  echo "  Example: export MODEL2_GGUF=/path/to/Qwen3-32B.gguf"
  exit 1
fi

if [ ! -f "${MODEL2_GGUF}" ]; then
  echo "Error: MODEL2_GGUF must be a file: ${MODEL2_GGUF}"
  exit 1
fi

# Mount the file directly to /models/Qwen3-32B.gguf
MODEL2_MOUNT_DIR="${MODEL2_GGUF}"
MODEL2_CONTAINER_PATH="/models/Qwen3-32B.gguf"

echo "=========================================="
echo "Starting InfiniLM-SVC Server 2 (InfiniLM backend)"
echo "=========================================="
echo "Server 1 IP (Registry/Router): ${SERVER1_IP}"
echo "Server 2 IP (This server):     ${SERVER2_IP}"
echo "Image: ${IMAGE_NAME}"
echo "Components: Babysitter C, Babysitter D"
echo "INFINILM_DIR: ${INFINILM_DIR}"
echo "INFINICORE_DIR: ${INFINICORE_DIR}"
echo "MODEL1_DIR: ${MODEL1_DIR}"
echo "MODEL2_GGUF: ${MODEL2_GGUF} (mounted to ${MODEL2_CONTAINER_PATH})"
echo ""

# Quick reachability check
echo "🔍 Checking connection to Server 1 registry..."
if ! curl -s -f --connect-timeout 5 "http://${SERVER1_IP}:18000/health" > /dev/null 2>&1; then
  echo "❌ Error: Cannot reach Server 1 registry at http://${SERVER1_IP}:18000"
  exit 1
fi
echo "✅ Server 1 registry reachable"

# Remove existing container if present
if docker ps -a --format '{{.Names}}' | grep -q "^infinilm-svc-infinilm-server2$"; then
  echo "Removing existing container infinilm-svc-infinilm-server2 ..."
  docker rm -f infinilm-svc-infinilm-server2 >/dev/null
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
  --name infinilm-svc-infinilm-server2 \
  -e LAUNCH_COMPONENTS=babysitter \
  -e REGISTRY_URL="http://${SERVER1_IP}:18000" \
  -e ROUTER_URL="http://${SERVER1_IP}:8000" \
  -e BABYSITTER_HOST="${SERVER2_IP}" \
  -e BABYSITTER_CONFIGS="babysitter-c.toml babysitter-d.toml" \
  -v "${SCRIPT_DIR}/config:/app/config:ro" \
  -v "${SCRIPT_DIR}/../scripts:/app/scripts:ro" \
  -v "${SCRIPT_DIR}/../deployment:/app/deployment:ro" \
  -v "${INFINILM_DIR}:/mnt/InfiniLM:ro" \
  -v "${INFINICORE_DIR}:/mnt/InfiniCore:ro" \
  -v "${MODEL1_DIR}:/models/9g_8b_thinking_llama:ro" \
  -v "${MODEL2_MOUNT_DIR}:${MODEL2_CONTAINER_PATH}:ro" \
  "${IMAGE_NAME}"

echo ""
echo "✅ Server 2 container started: infinilm-svc-infinilm-server2"
echo ""
echo "⚠️  IMPORTANT: Install InfiniCore and InfiniLM inside the container:"
echo "   docker exec -it infinilm-svc-infinilm-server2 bash -c '"
echo "     cd /app && "
echo "     bash scripts/install.sh \\"
echo "       --deployment-case infinilm-metax-deployment \\"
echo "       --install-infinicore true \\"
echo "       --install-infinilm true \\"
echo "       --infinicore-src /mnt/InfiniCore \\"
echo "       --infinilm-src /mnt/InfiniLM \\"
echo "       --allow-xmake-root auto"
echo "   '"
echo ""
echo "Logs: docker logs -f infinilm-svc-infinilm-server2"
