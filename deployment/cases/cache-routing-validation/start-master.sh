#!/usr/bin/env bash
# Start Master: Registry, Router, and two babysitters (both 9g_8b_thinking instances)
# Both instances run on the same host with different ports (8100 and 8200)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY_IP="${1:-localhost}"
LOCALHOST_IP="${REGISTRY_IP}"

# Load deployment case defaults (for LAUNCH_COMPONENTS)
DEPLOYMENT_CASE="${DEPLOYMENT_CASE:-cache-routing-validation}"
if [ -f "${SCRIPT_DIR}/install.defaults.sh" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/install.defaults.sh"
fi

IMAGE_NAME="${IMAGE_NAME:-infinilm-svc:infinilm-demo}"
CONTAINER_NAME="${CONTAINER_NAME:-infinilm-svc-master}"

# Use LAUNCH_COMPONENTS from deployment case defaults, or allow override via env
LAUNCH_COMPONENTS="${LAUNCH_COMPONENTS:-all}"

# Build BABYSITTER_CONFIGS - both instances on one host
BABYSITTER_CONFIGS="${BABYSITTER_CONFIGS:-master-9g_8b_thinking.toml slave-9g_8b_thinking.toml}"

# Configurable ports (defaults)
REGISTRY_PORT="${REGISTRY_PORT:-18000}"
ROUTER_PORT="${ROUTER_PORT:-8000}"

# Optional directories - use /workspace defaults if not provided
INFINILM_DIR="${INFINILM_DIR:-}"
INFINICORE_DIR="${INFINICORE_DIR:-}"
CONFIG_DIR="${CONFIG_DIR:-${SCRIPT_DIR}/config}"

# Required model paths
MODEL1_DIR="${MODEL1_DIR:-}"

if [ -z "${MODEL1_DIR}" ] || [ ! -d "${MODEL1_DIR}" ]; then
  echo "Error: MODEL1_DIR must point to the 9g_8b_thinking_llama model directory on this host."
  echo "  Current value: MODEL1_DIR=${MODEL1_DIR}"
  echo "  Example: export MODEL1_DIR=/data-aisoft/zenghua/models/9g_8b_thinking_llama"
  exit 1
fi

echo "=========================================="
echo "Starting InfiniLM-SVC Master (Cache Routing Validation)"
echo "=========================================="
echo "Registry IP: ${REGISTRY_IP}"
echo "Image: ${IMAGE_NAME}"
echo "Registry Port: ${REGISTRY_PORT}"
echo "Router Port: ${ROUTER_PORT}"
echo "Components: Registry, Router, master-9g_8b_thinking (8100), slave-9g_8b_thinking (8200)"
echo "Container: ${CONTAINER_NAME}"
echo ""
echo "Model paths:"
echo "  MODEL1_DIR (9g_8b_thinking_llama): ${MODEL1_DIR}"
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
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "Removing existing container ${CONTAINER_NAME} ..."
  docker rm -f "${CONTAINER_NAME}" >/dev/null
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
  --name "${CONTAINER_NAME}"
  -e LAUNCH_COMPONENTS="${LAUNCH_COMPONENTS}"
  -e REGISTRY_PORT="${REGISTRY_PORT}"
  -e ROUTER_PORT="${ROUTER_PORT}"
  -e BABYSITTER_CONFIGS="${BABYSITTER_CONFIGS}"
)

# Set NO_PROXY to exclude localhost/127.0.0.1 so local registry/router connections bypass proxy
# This ensures validation scripts and internal services can access the registry directly
if [ -n "${NO_PROXY:-}" ]; then
  DOCKER_ARGS+=(-e "NO_PROXY=${NO_PROXY},localhost,127.0.0.1,0.0.0.0")
  DOCKER_ARGS+=(-e "no_proxy=${NO_PROXY},localhost,127.0.0.1,0.0.0.0")
else
  DOCKER_ARGS+=(-e "NO_PROXY=localhost,127.0.0.1,0.0.0.0")
  DOCKER_ARGS+=(-e "no_proxy=localhost,127.0.0.1,0.0.0.0")
fi

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

# Mount model
DOCKER_ARGS+=(
  -v "${MODEL1_DIR}:/models/9g_8b_thinking:ro"
)

DOCKER_ARGS+=("${IMAGE_NAME}")

docker run "${DOCKER_ARGS[@]}"

echo ""
echo "✅ Master container started: ${CONTAINER_NAME}"
echo "Registry: http://${REGISTRY_IP}:${REGISTRY_PORT}"
echo "Router:   http://${REGISTRY_IP}:${ROUTER_PORT}"
echo ""
echo "Instance 1 (master-9g_8b_thinking): port 8100"
echo "Instance 2 (slave-9g_8b_thinking): port 8200"
echo ""
echo "Logs: docker logs -f ${CONTAINER_NAME}"
