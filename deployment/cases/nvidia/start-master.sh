#!/usr/bin/env bash
# Start Master: Registry, Router, and single babysitter (9g_8b_thinking via InfiniLM --nvidia)
# NVIDIA GPU deployment - uses --gpus all

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REGISTRY_IP="${1:-localhost}"
LOCALHOST_IP="${REGISTRY_IP}"

# Load environment file if it exists
if [ -f "${SCRIPT_DIR}/.env" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/.env"
fi

# Load deployment case defaults
DEPLOYMENT_CASE="${DEPLOYMENT_CASE:-nvidia}"
if [ -f "${SCRIPT_DIR}/install.defaults.sh" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/install.defaults.sh"
fi

IMAGE_NAME="${IMAGE_NAME:-infinilm-svc:nvidia}"
CONTAINER_NAME="${CONTAINER_NAME:-infinilm-svc-master}"
LAUNCH_COMPONENTS="${LAUNCH_COMPONENTS:-all}"
BABYSITTER_CONFIGS="${BABYSITTER_CONFIGS:-master-9g_8b_thinking.toml}"

REGISTRY_PORT="${REGISTRY_PORT:-18000}"
ROUTER_PORT="${ROUTER_PORT:-8000}"
CONFIG_DIR="${CONFIG_DIR:-${SCRIPT_DIR}/config}"
MODEL1_DIR="${MODEL1_DIR:-}"

if [ -z "${MODEL1_DIR}" ] || [ ! -d "${MODEL1_DIR}" ]; then
  echo "Error: MODEL1_DIR must point to the model directory on this host."
  echo "  Accepts: 9g_8b_thinking (FM9G) or 9g_8b_thinking_llama (Llama, for InfiniLM)"
  echo "  Current value: MODEL1_DIR=${MODEL1_DIR}"
  echo "  Example: export MODEL1_DIR=/path/to/9g_8b_thinking"
  echo "  Example: export MODEL1_DIR=/path/to/9g_8b_thinking_llama"
  exit 1
fi

# Resolve MODEL1_DIR: if non-_llama provided and _llama not ready, run converter
MODEL1_DIR_RESOLVED="${MODEL1_DIR}"
if [[ "${MODEL1_DIR}" != *"_llama" ]]; then
  MODEL1_LLAMA_DIR="${MODEL1_DIR}_llama"
  # Check if _llama dir is ready (config.json + safetensors)
  LLAMA_READY=false
  if [ -d "${MODEL1_LLAMA_DIR}" ] && [ -f "${MODEL1_LLAMA_DIR}/config.json" ]; then
    if [ -f "${MODEL1_LLAMA_DIR}/model.safetensors.index.json" ] || \
       compgen -G "${MODEL1_LLAMA_DIR}/model-*.safetensors" >/dev/null 2>&1; then
      LLAMA_READY=true
    fi
  fi
  if [ "${LLAMA_READY}" = false ]; then
    echo "Converting 9g_8b_thinking to 9g_8b_thinking_llama (required by InfiniLM)..."
    MODEL1_PARENT="$(dirname "${MODEL1_DIR}")"
    docker run --rm --entrypoint "" \
      -v "${SCRIPT_DIR}:/app/deployment/cases/nvidia:ro" \
      -v "${MODEL1_PARENT}:${MODEL1_PARENT}" \
      "${IMAGE_NAME}" \
      python3 /app/deployment/cases/nvidia/9g_converter.py "${MODEL1_DIR}"
    echo "Conversion complete: ${MODEL1_LLAMA_DIR}"
  fi
  MODEL1_DIR_RESOLVED="${MODEL1_LLAMA_DIR}"
fi
MODEL1_DIR="${MODEL1_DIR_RESOLVED}"

echo "=========================================="
echo "Starting InfiniLM-SVC Master (NVIDIA GPU)"
echo "=========================================="
echo "Registry IP: ${REGISTRY_IP}"
echo "Image: ${IMAGE_NAME}"
echo "Registry Port: ${REGISTRY_PORT}"
echo "Router Port: ${ROUTER_PORT}"
echo "Components: Registry, Router, master-9g_8b_thinking"
echo "Container: ${CONTAINER_NAME}"
echo ""
echo "Model paths:"
echo "  MODEL1_DIR (9g_8b_thinking_llama): ${MODEL1_DIR}"
echo ""

# Remove existing container if present
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "Removing existing container ${CONTAINER_NAME} ..."
  docker rm -f "${CONTAINER_NAME}" >/dev/null
fi

echo "🚀 Starting Docker container..."

DOCKER_ARGS=(
  -d
  --network host
  --gpus all
  --name "${CONTAINER_NAME}"
  -e LAUNCH_COMPONENTS="${LAUNCH_COMPONENTS}"
  -e REGISTRY_PORT="${REGISTRY_PORT}"
  -e ROUTER_PORT="${ROUTER_PORT}"
  -e BABYSITTER_CONFIGS="${BABYSITTER_CONFIGS}"
)

# NO_PROXY for local registry/router
if [ -n "${NO_PROXY:-}" ]; then
  DOCKER_ARGS+=(-e "NO_PROXY=${NO_PROXY},localhost,127.0.0.1,0.0.0.0")
  DOCKER_ARGS+=(-e "no_proxy=${NO_PROXY},localhost,127.0.0.1,0.0.0.0")
else
  DOCKER_ARGS+=(-e "NO_PROXY=localhost,127.0.0.1,0.0.0.0")
  DOCKER_ARGS+=(-e "no_proxy=localhost,127.0.0.1,0.0.0.0")
fi

DOCKER_ARGS+=(-v "${CONFIG_DIR}:/app/config:ro")
DOCKER_ARGS+=(-v "${MODEL1_DIR}:/models/9g_8b_thinking:ro")
DOCKER_ARGS+=("${IMAGE_NAME}")

docker run "${DOCKER_ARGS[@]}"

echo ""
echo "✅ Master container started: ${CONTAINER_NAME}"
echo "Registry: http://${REGISTRY_IP}:${REGISTRY_PORT}"
echo "Router:   http://${REGISTRY_IP}:${ROUTER_PORT}"
echo "Logs: docker logs -f ${CONTAINER_NAME}"
