#!/usr/bin/env bash
# Start Server 1: Registry, Router, and two babysitters (InfiniLM backends)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER1_IP="${1:-localhost}"

IMAGE_NAME="${IMAGE_NAME:-infinilm-svc:infinilm-demo}"

# Configurable ports (defaults)
REGISTRY_PORT="${REGISTRY_PORT:-18000}"
ROUTER_PORT="${ROUTER_PORT:-8000}"

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
echo "Starting InfiniLM-SVC Server 1"
echo "=========================================="
echo "Server IP: ${SERVER1_IP}"
echo "Image: ${IMAGE_NAME}"
echo "Registry Port: ${REGISTRY_PORT}"
echo "Router Port: ${ROUTER_PORT}"
echo "Components: Registry, Router, server1-9g_8b_thinking_llama, server1-Qwen3-32B"
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

# Remove existing container if present
if docker ps -a --format '{{.Names}}' | grep -q "^infinilm-svc-infinilm-server1$"; then
  echo "Removing existing container infinilm-svc-infinilm-server1 ..."
  docker rm -f infinilm-svc-infinilm-server1 >/dev/null
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
  --name infinilm-svc-infinilm-server1
  -e LAUNCH_COMPONENTS=all
  -e REGISTRY_PORT="${REGISTRY_PORT}"
  -e ROUTER_PORT="${ROUTER_PORT}"
  -e BABYSITTER_CONFIGS="server1-9g_8b_thinking.toml server1-Qwen3-32B.toml"
)

# Mount config directory
DOCKER_ARGS+=(-v "${CONFIG_DIR}:/app/config:ro")

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
  -v "${MODEL1_DIR}:/models/9g_8b_thinking:ro"
  -v "${MODEL2_MOUNT_DIR}:${MODEL2_CONTAINER_PATH}:ro"
  "${IMAGE_NAME}"
)

docker run "${DOCKER_ARGS[@]}"

echo ""
echo "✅ Server 1 container started: infinilm-svc-infinilm-server1"
echo "Registry: http://${SERVER1_IP}:${REGISTRY_PORT}"
echo "Router:   http://${SERVER1_IP}:${ROUTER_PORT}"
echo ""
echo "Logs: docker logs -f infinilm-svc-infinilm-server1"
