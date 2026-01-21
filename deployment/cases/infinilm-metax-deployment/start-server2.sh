#!/usr/bin/env bash
# Start Server 2: Two babysitters (InfiniLM backends) registering to Server 1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-infinilm-svc:infinilm-demo}"

if [ $# -lt 2 ]; then
  echo "Usage: $0 <SERVER1_IP> <SERVER2_IP> [REGISTRY_PORT] [ROUTER_PORT]"
  echo "  Default ports: REGISTRY_PORT=18000, ROUTER_PORT=8000"
  exit 1
fi

SERVER1_IP="$1"
SERVER2_IP="$2"
REGISTRY_PORT="${3:-18000}"
ROUTER_PORT="${4:-8000}"

# Optional directories - use /workspace defaults if not provided
INFINILM_DIR="${INFINILM_DIR:-}"
INFINICORE_DIR="${INFINICORE_DIR:-}"
CONFIG_DIR="${CONFIG_DIR:-${SCRIPT_DIR}/config}"

# Required model paths
MODEL1_DIR="${MODEL1_DIR:-}"
MODEL2_GGUF="${MODEL2_GGUF:-}"

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
echo "Starting InfiniLM-SVC Server 2"
echo "=========================================="
echo "Server 1 IP (Registry/Router): ${SERVER1_IP}"
echo "Server 2 IP (This server):     ${SERVER2_IP}"
echo "Registry Port: ${REGISTRY_PORT}"
echo "Router Port: ${ROUTER_PORT}"
echo "Image: ${IMAGE_NAME}"
echo "Components: server2-9g_8b_thinking_llama, server2-Qwen3-32B"
echo ""
echo "Model paths:"
echo "  MODEL1_DIR: ${MODEL1_DIR}"
echo "  MODEL2_GGUF: ${MODEL2_GGUF} (mounted to ${MODEL2_CONTAINER_PATH})"
echo ""
if [ -n "${INFINILM_DIR}" ]; then
  echo "INFINILM_DIR: ${INFINILM_DIR} (will mount to /workspace/InfiniLM)"
else
  echo "INFINILM_DIR: not set (using /workspace/InfiniLM in container)"
fi
if [ -n "${INFINICORE_DIR}" ]; then
  echo "INFINICORE_DIR: ${INFINICORE_DIR} (will mount to /workspace/InfiniCore)"
else
  echo "INFINICORE_DIR: not set (using /workspace/InfiniCore in container)"
fi
if [ "${CONFIG_DIR}" != "${SCRIPT_DIR}/config" ]; then
  echo "CONFIG_DIR: ${CONFIG_DIR} (will mount to /app/config)"
else
  echo "CONFIG_DIR: using default ${CONFIG_DIR}"
fi
echo ""

# Quick reachability check
echo "🔍 Checking connection to Server 1 registry..."
if ! curl -s -f --connect-timeout 5 "http://${SERVER1_IP}:${REGISTRY_PORT}/health" > /dev/null 2>&1; then
  echo "❌ Error: Cannot reach Server 1 registry at http://${SERVER1_IP}:${REGISTRY_PORT}"
  exit 1
fi
echo "✅ Server 1 registry reachable"

# Remove existing container if present
if docker ps -a --format '{{.Names}}' | grep -q "^infinilm-svc-infinilm-server2$"; then
  echo "Removing existing container infinilm-svc-infinilm-server2 ..."
  docker rm -f infinilm-svc-infinilm-server2 >/dev/null
fi

echo "🚀 Starting Docker container..."

# Build docker run command with conditional mounts
DOCKER_ARGS=(
  -d
  --network host
  --uts host
  --ipc host
  --device /dev/dri
  --device /dev/htcd
  --device /dev/infiniband
  --group-add video
  --privileged=true
  --security-opt apparmor=unconfined
  --shm-size 100gb
  --ulimit memlock=-1
  --name infinilm-svc-infinilm-server2
  -e LAUNCH_COMPONENTS=babysitter
  -e REGISTRY_URL="http://${SERVER1_IP}:${REGISTRY_PORT}"
  -e ROUTER_URL="http://${SERVER1_IP}:${ROUTER_PORT}"
  -e BABYSITTER_HOST="${SERVER2_IP}"
  -e BABYSITTER_CONFIGS="server2-9g_8b_thinking_llama.toml server2-Qwen3-32B.toml"
)

# Mount config directory
DOCKER_ARGS+=(-v "${CONFIG_DIR}:/app/config:ro")

# Mount scripts and deployment directories (needed for install.sh)
DOCKER_ARGS+=(
  -v "${SCRIPT_DIR}/../scripts:/app/scripts:ro"
  -v "${SCRIPT_DIR}/../deployment:/app/deployment:ro"
)

# Mount InfiniLM if provided (override /workspace/InfiniLM at runtime)
if [ -n "${INFINILM_DIR}" ] && [ -d "${INFINILM_DIR}" ]; then
  DOCKER_ARGS+=(-v "${INFINILM_DIR}:/workspace/InfiniLM:ro")
fi

# Mount InfiniCore if provided (override /workspace/InfiniCore at runtime)
if [ -n "${INFINICORE_DIR}" ] && [ -d "${INFINICORE_DIR}" ]; then
  DOCKER_ARGS+=(-v "${INFINICORE_DIR}:/workspace/InfiniCore:ro")
fi

# Mount models
DOCKER_ARGS+=(
  -v "${MODEL1_DIR}:/models/9g_8b_thinking_llama:ro"
  -v "${MODEL2_MOUNT_DIR}:${MODEL2_CONTAINER_PATH}:ro"
  "${IMAGE_NAME}"
)

docker run "${DOCKER_ARGS[@]}"

echo ""
echo "✅ Server 2 container started: infinilm-svc-infinilm-server2"
echo ""
echo "⚠️  IMPORTANT: Install InfiniCore and InfiniLM inside the container if needed:"
echo "   docker exec -it infinilm-svc-infinilm-server2 bash -c '"
echo "     cd /app && "
echo "     bash scripts/install.sh \\"
echo "       --deployment-case infinilm-metax-deployment \\"
echo "       --install-infinicore true \\"
echo "       --install-infinilm true \\"
echo "       --infinicore-src /workspace/InfiniCore \\"
echo "       --infinilm-src /workspace/InfiniLM \\"
echo "       --allow-xmake-root auto"
echo "   '"
echo ""
echo "Logs: docker logs -f infinilm-svc-infinilm-server2"
