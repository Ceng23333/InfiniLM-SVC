#!/usr/bin/env bash
# Start Master: Registry, Router, and babysitter(s) for Qwen3-32B
# Size-based routing: paged cache (GPUs 0-3) + static cache (GPUs 4-7)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY_IP="${1:-localhost}"
LOCALHOST_IP="${REGISTRY_IP}"

# Load environment file if it exists (allows easy configuration)
if [ -f "${SCRIPT_DIR}/.env" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/.env"
fi

# Load deployment case defaults (for LAUNCH_COMPONENTS)
DEPLOYMENT_CASE="${DEPLOYMENT_CASE:-cache-type-routing-validation}"
if [ -f "${SCRIPT_DIR}/install.defaults.sh" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/install.defaults.sh"
fi

IMAGE_NAME="${IMAGE_NAME:-infinilm-svc:infinilm-demo}"
CONTAINER_NAME="${CONTAINER_NAME:-infinilm-svc-master-qwen3-32b}"

LAUNCH_COMPONENTS="${LAUNCH_COMPONENTS:-all}"

# Qwen3-32B instances: paged cache (GPUs 0-3) and static cache (GPUs 4-7)
BABYSITTER_CONFIGS="${BABYSITTER_CONFIGS:-paged-cache-qwen3-32b.toml static-cache-qwen3-32b.toml}"

REGISTRY_PORT="${REGISTRY_PORT:-18000}"
ROUTER_PORT="${ROUTER_PORT:-8000}"

INFINILM_DIR="${INFINILM_DIR:-}"
INFINICORE_DIR="${INFINICORE_DIR:-}"
CONFIG_DIR="${CONFIG_DIR:-${SCRIPT_DIR}/config}"

# Qwen3-32B model path
QWEN3_32B_DIR="${QWEN3_32B_DIR:-}"

if [ -z "${QWEN3_32B_DIR}" ] || [ ! -d "${QWEN3_32B_DIR}" ]; then
  echo "Error: QWEN3_32B_DIR must point to the Qwen3-32B model directory on this host."
  echo "  Current value: QWEN3_32B_DIR=${QWEN3_32B_DIR}"
  echo "  Example: export QWEN3_32B_DIR=/data-aisoft/zenghua/models/Qwen3-32B"
  exit 1
fi

echo "=========================================="
echo "Starting InfiniLM-SVC (Qwen3-32B Cache Type Routing)"
echo "=========================================="
echo "Registry IP: ${REGISTRY_IP}"
echo "Image: ${IMAGE_NAME}"
echo "Registry Port: ${REGISTRY_PORT}"
echo "Router Port: ${ROUTER_PORT}"
echo "Components: Registry, Router, paged-cache-qwen3-32b (8100, GPUs 0-3), static-cache-qwen3-32b (8200, GPUs 4-7)"
echo "Container: ${CONTAINER_NAME}"
echo ""
echo "Model paths:"
echo "  QWEN3_32B_DIR: ${QWEN3_32B_DIR}"
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

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "Removing existing container ${CONTAINER_NAME} ..."
  docker rm -f "${CONTAINER_NAME}" >/dev/null
fi

echo "🚀 Starting Docker container..."

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
  -e CACHE_TYPE_ROUTING_THRESHOLD="${CACHE_TYPE_ROUTING_THRESHOLD:-10000}" # Default 10KB (adjusted for proper routing with larger contexts)
  -e PROXY_TIMEOUT_SECONDS="${PROXY_TIMEOUT_SECONDS:-1800}" # Default 30 minutes
  --entrypoint "/app/docker_entrypoint.sh"
)

if [ -n "${NO_PROXY:-}" ]; then
  DOCKER_ARGS+=(-e "NO_PROXY=${NO_PROXY},localhost,127.0.0.1,0.0.0.0")
  DOCKER_ARGS+=(-e "no_proxy=${NO_PROXY},localhost,127.0.0.1,0.0.0.0")
else
  DOCKER_ARGS+=(-e "NO_PROXY=localhost,127.0.0.1,0.0.0.0")
  DOCKER_ARGS+=(-e "no_proxy=localhost,127.0.0.1,0.0.0.0")
fi

DOCKER_ARGS+=(-v "${CONFIG_DIR}:/app/config:ro")

if [ -n "${INFINILM_DIR}" ] && [ -d "${INFINILM_DIR}" ]; then
  DOCKER_ARGS+=(-v "${INFINILM_DIR}:/workspace/InfiniLM:ro")
fi

if [ -n "${INFINICORE_DIR}" ] && [ -d "${INFINICORE_DIR}" ]; then
  DOCKER_ARGS+=(-v "${INFINICORE_DIR}:/workspace/InfiniCore:ro")
fi

DOCKER_ARGS+=(
  -v "${QWEN3_32B_DIR}:/models/Qwen3-32B:ro"
)

DOCKER_ARGS+=("${IMAGE_NAME}")

docker run "${DOCKER_ARGS[@]}"

echo ""
echo "✅ Container started: ${CONTAINER_NAME}"
echo "Registry: http://${REGISTRY_IP}:${REGISTRY_PORT}"
echo "Router:   http://${REGISTRY_IP}:${ROUTER_PORT}"
echo ""
echo "Instance 1 (paged-cache-qwen3-32b): port 8100, GPUs 0-3 (tp=4)"
echo "Instance 2 (static-cache-qwen3-32b): port 8200, GPUs 4-7 (tp=4)"
echo ""
echo "Logs: docker logs -f ${CONTAINER_NAME}"
