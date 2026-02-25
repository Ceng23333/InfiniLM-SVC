#!/usr/bin/env bash
# Start Slave: 2x Qwen3-32B static cache (InfiniLM Python backend) registering to Master
# Deployment case: infinilm-metax-deployment-opt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment file if it exists
if [ -f "${SCRIPT_DIR}/.env.slave" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/.env.slave"
elif [ -f "${SCRIPT_DIR}/.env" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/.env"
fi

# Load deployment case defaults
DEPLOYMENT_CASE="${DEPLOYMENT_CASE:-infinilm-metax-deployment-opt}"
if [ -f "${SCRIPT_DIR}/install.defaults.sh" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/install.defaults.sh"
fi

IMAGE_NAME="${IMAGE_NAME:-infinilm-svc:infinilm-demo-runtime}"
LAUNCH_COMPONENTS="${LAUNCH_COMPONENTS:-babysitter}"

usage() {
  echo "Usage: $0 <MASTER_IP> <SLAVE_IP>"
  echo ""
  echo "Examples:"
  echo "  $0 192.168.163.151 192.168.163.152"
}

if [ $# -lt 2 ]; then
  usage
  exit 1
fi

REGISTRY_IP="$1"
LOCALHOST_IP="$2"

CONTAINER_NAME="${CONTAINER_NAME:-infinilm-svc-slave-opt}"
REGISTRY_PORT="${REGISTRY_PORT:-18000}"
ROUTER_PORT="${ROUTER_PORT:-8000}"
CONFIG_DIR="${CONFIG_DIR:-${SCRIPT_DIR}/config}"

# Fixed configs: 2x Qwen3-32B static cache
BABYSITTER_CONFIGS="slave-static-qwen3-32b.toml slave-static-qwen3-32b-2.toml"

# Model path: MODEL2_GGUF or QWEN3_32B_DIR
MODEL2_GGUF="${MODEL2_GGUF:-${QWEN3_32B_DIR:-}}"
if [ -z "${MODEL2_GGUF}" ] || [ ! -d "${MODEL2_GGUF}" ]; then
  echo "Error: MODEL2_GGUF or QWEN3_32B_DIR must point to the Qwen3-32B model directory on this host."
  echo "  Example: export QWEN3_32B_DIR=/path/to/Qwen3-32B"
  exit 1
fi

MODEL2_CONTAINER_PATH="/models/Qwen3-32B"

echo "=========================================="
echo "Starting InfiniLM-SVC Slave (infinilm-metax-deployment-opt)"
echo "=========================================="
echo "Registry IP (Master): ${REGISTRY_IP}"
echo "Slave IP: ${LOCALHOST_IP}"
echo "Registry Port: ${REGISTRY_PORT}"
echo "Router Port: ${ROUTER_PORT}"
echo "Image: ${IMAGE_NAME}"
echo "Components: slave-static-qwen3-32b, slave-static-qwen3-32b-2"
echo "Container: ${CONTAINER_NAME}"
echo ""
echo "Model path: ${MODEL2_GGUF} (mounted to ${MODEL2_CONTAINER_PATH})"
echo ""

# Check connection to master registry
echo "Checking connection to Master registry..."
if ! curl -s -f --connect-timeout 5 --noproxy "*" "http://${REGISTRY_IP}:${REGISTRY_PORT}/health" > /dev/null 2>&1; then
  echo "Error: Cannot reach Master registry at http://${REGISTRY_IP}:${REGISTRY_PORT}"
  exit 1
fi
echo "Master registry reachable"

# Remove existing container if present
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "Removing existing container ${CONTAINER_NAME} ..."
  docker rm -f "${CONTAINER_NAME}" >/dev/null
fi

echo "Starting Docker container..."

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
  -e REGISTRY_URL="http://${REGISTRY_IP}:${REGISTRY_PORT}"
  -e ROUTER_URL="http://${REGISTRY_IP}:${ROUTER_PORT}"
  -e BABYSITTER_HOST="${LOCALHOST_IP}"
  -e BABYSITTER_CONFIGS="${BABYSITTER_CONFIGS}"
)

if [ -n "${NO_PROXY:-}" ]; then
  DOCKER_ARGS+=(-e "NO_PROXY=${NO_PROXY},localhost,127.0.0.1,0.0.0.0")
  DOCKER_ARGS+=(-e "no_proxy=${NO_PROXY},localhost,127.0.0.1,0.0.0.0")
else
  DOCKER_ARGS+=(-e "NO_PROXY=localhost,127.0.0.1,0.0.0.0")
  DOCKER_ARGS+=(-e "no_proxy=localhost,127.0.0.1,0.0.0.0")
fi

DOCKER_ARGS+=(-v "${CONFIG_DIR}:/app/config:ro")

# Mount InfiniLM / InfiniCore if provided
if [ -n "${INFINILM_DIR:-}" ] && [ -d "${INFINILM_DIR}" ]; then
  DOCKER_ARGS+=(-v "${INFINILM_DIR}:/workspace/InfiniLM:ro")
fi
if [ -n "${INFINICORE_DIR:-}" ] && [ -d "${INFINICORE_DIR}" ]; then
  DOCKER_ARGS+=(-v "${INFINICORE_DIR}:/workspace/InfiniCore:ro")
fi

DOCKER_ARGS+=(
  -v "${MODEL2_GGUF}:${MODEL2_CONTAINER_PATH}:ro"
  "${IMAGE_NAME}"
)

docker run "${DOCKER_ARGS[@]}"

echo ""
echo "Slave container started: ${CONTAINER_NAME}"
echo "Logs: docker logs -f ${CONTAINER_NAME}"
