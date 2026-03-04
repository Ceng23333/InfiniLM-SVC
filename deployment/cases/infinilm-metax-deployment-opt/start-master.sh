#!/usr/bin/env bash
# Start Master: Registry, Router, embedding (optional), 9g_8b_thinking, Qwen3-32B paged
# Deployment case: infinilm-metax-deployment-opt

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
DEPLOYMENT_CASE="${DEPLOYMENT_CASE:-infinilm-metax-deployment-opt}"
if [ -f "${SCRIPT_DIR}/install.defaults.sh" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/install.defaults.sh"
fi

IMAGE_NAME="${IMAGE_NAME:-infinilm-svc:infinilm-demo-runtime}"
CONTAINER_NAME="${CONTAINER_NAME:-infinilm-svc-master-opt}"

# Use LAUNCH_COMPONENTS from deployment case defaults, or allow override via env
LAUNCH_COMPONENTS="${LAUNCH_COMPONENTS:-all}"

# Build BABYSITTER_CONFIGS - base set by MASTER_PRESET, then optional embeddings
# When MASTER_PRESET is set (e.g. 3vllm), it overrides .env so the correct backend is used
MASTER_PRESET="${MASTER_PRESET:-}"
if [ "${MASTER_PRESET}" = "3vllm" ]; then
  BABYSITTER_CONFIGS_BASE="master-9g_8b_thinking.toml master-3vllm-vllm-1.toml"
  COMPONENTS_DESC="Registry, Router, master-9g_8b_thinking, master-3vllm-vllm-1"
else
  BABYSITTER_CONFIGS_BASE="master-9g_8b_thinking.toml master-qwen3-32b-paged.toml"
  COMPONENTS_DESC="Registry, Router, master-9g_8b_thinking, master-qwen3-32b-paged"
fi
if [ -n "${MASTER_PRESET}" ]; then
  # Preset overrides .env so container gets the intended config
  if [ -n "${EMBEDDING_MODEL_DIR}" ] && [ -d "${EMBEDDING_MODEL_DIR}" ]; then
    BABYSITTER_CONFIGS="${BABYSITTER_CONFIGS_BASE} master-embeddings.toml"
  else
    BABYSITTER_CONFIGS="${BABYSITTER_CONFIGS_BASE}"
  fi
elif [ -n "${EMBEDDING_MODEL_DIR}" ] && [ -d "${EMBEDDING_MODEL_DIR}" ]; then
  BABYSITTER_CONFIGS="${BABYSITTER_CONFIGS:-${BABYSITTER_CONFIGS_BASE} master-embeddings.toml}"
else
  BABYSITTER_CONFIGS="${BABYSITTER_CONFIGS:-${BABYSITTER_CONFIGS_BASE}}"
fi

# Configurable ports (defaults)
REGISTRY_PORT="${REGISTRY_PORT:-18000}"
ROUTER_PORT="${ROUTER_PORT:-8000}"
EMBEDDING_PORT="${EMBEDDING_PORT:-20002}"

# Optional directories - use /workspace defaults if not provided
INFINILM_DIR="${INFINILM_DIR:-}"
INFINICORE_DIR="${INFINICORE_DIR:-}"
CONFIG_DIR="${CONFIG_DIR:-${SCRIPT_DIR}/config}"

# Required model paths (MODEL2_DIR or QWEN3_32B_DIR for Qwen3-32B)
MODEL1_DIR="${MODEL1_DIR:-}"
MODEL2_DIR="${MODEL2_DIR:-${QWEN3_32B_DIR:-}}"

# Embedding model paths (optional)
EMBEDDING_MODEL_DIR="${EMBEDDING_MODEL_DIR:-}"
RERANK_MODEL_DIR="${RERANK_MODEL_DIR:-}"
BCE_RERANK_MODEL_DIR="${BCE_RERANK_MODEL_DIR:-}"

if [ -z "${MODEL1_DIR}" ] || [ ! -d "${MODEL1_DIR}" ]; then
  echo "Error: MODEL1_DIR must point to the 9g_8b_thinking_llama model directory on this host."
  echo "  Current value: MODEL1_DIR=${MODEL1_DIR}"
  echo "  Example: export MODEL1_DIR=/data-aisoft/zenghua/models/9g_8b_thinking_llama"
  exit 1
fi

if [ -z "${MODEL2_DIR}" ] || [ ! -d "${MODEL2_DIR}" ]; then
  echo "Error: MODEL2_DIR or QWEN3_32B_DIR must point to the Qwen3-32B model directory on this host."
  echo "  Current value: MODEL2_DIR=${MODEL2_DIR}"
  echo "  Example: export MODEL2_DIR=/data-aisoft/zenghua/models/Qwen3-32B"
  exit 1
fi

echo "=========================================="
echo "Starting InfiniLM-SVC Master (infinilm-metax-deployment-opt)"
echo "=========================================="
echo "Registry IP: ${REGISTRY_IP}"
echo "Image: ${IMAGE_NAME}"
echo "Registry Port: ${REGISTRY_PORT}"
echo "Router Port: ${ROUTER_PORT}"
echo "Components: ${COMPONENTS_DESC}"
echo "Container: ${CONTAINER_NAME}"
echo ""
echo "Model paths:"
echo "  MODEL1_DIR (9g_8b_thinking_llama): ${MODEL1_DIR}"
echo "  MODEL2_DIR (Qwen3-32B): ${MODEL2_DIR}"
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
if [ -n "${EMBEDDING_MODEL_DIR}" ] && [ -d "${EMBEDDING_MODEL_DIR}" ]; then
  echo "Embedding Server (inside ${CONTAINER_NAME}):"
  echo "  Port: ${EMBEDDING_PORT}"
  echo "  EMBEDDING_MODEL_DIR: ${EMBEDDING_MODEL_DIR}"
  [ -n "${RERANK_MODEL_DIR}" ] && echo "  RERANK_MODEL_DIR: ${RERANK_MODEL_DIR}"
  [ -n "${BCE_RERANK_MODEL_DIR}" ] && echo "  BCE_RERANK_MODEL_DIR: ${BCE_RERANK_MODEL_DIR}"
  echo ""
fi

# Remove existing container if present
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "Removing existing container ${CONTAINER_NAME} ..."
  docker rm -f "${CONTAINER_NAME}" >/dev/null
fi

echo "Starting Docker container..."

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

# Optional: size-based routing threshold (if router supports it)
if [ -n "${CACHE_TYPE_ROUTING_THRESHOLD:-}" ]; then
  DOCKER_ARGS+=(-e "CACHE_TYPE_ROUTING_THRESHOLD=${CACHE_TYPE_ROUTING_THRESHOLD}")
fi

if [ -n "${NO_PROXY:-}" ]; then
  DOCKER_ARGS+=(-e "NO_PROXY=${NO_PROXY},localhost,127.0.0.1,0.0.0.0")
  DOCKER_ARGS+=(-e "no_proxy=${NO_PROXY},localhost,127.0.0.1,0.0.0.0")
else
  DOCKER_ARGS+=(-e "NO_PROXY=localhost,127.0.0.1,0.0.0.0")
  DOCKER_ARGS+=(-e "no_proxy=localhost,127.0.0.1,0.0.0.0")
fi

# Mount config directory
DOCKER_ARGS+=(-v "${CONFIG_DIR}:/app/config:ro")

# Mount embedding server script if present (required for master-embeddings.toml)
if [ -f "${SCRIPT_DIR}/embeddings_server.py" ]; then
  DOCKER_ARGS+=(-v "${SCRIPT_DIR}/embeddings_server.py:/app/embeddings_server.py:ro")
fi

# Mount InfiniLM / InfiniCore if provided
if [ -n "${INFINILM_DIR}" ] && [ -d "${INFINILM_DIR}" ]; then
  DOCKER_ARGS+=(-v "${INFINILM_DIR}:/workspace/InfiniLM:ro")
fi
if [ -n "${INFINICORE_DIR}" ] && [ -d "${INFINICORE_DIR}" ]; then
  DOCKER_ARGS+=(-v "${INFINICORE_DIR}:/workspace/InfiniCore:ro")
fi

# Mount models
DOCKER_ARGS+=(
  -v "${MODEL1_DIR}:/models/9g_8b_thinking:ro"
  -v "${MODEL2_DIR}:/models/Qwen3-32B:ro"
)

# Mount embedding models if provided
if [ -n "${EMBEDDING_MODEL_DIR}" ] && [ -d "${EMBEDDING_MODEL_DIR}" ]; then
  if [ -d "${EMBEDDING_MODEL_DIR}/MiniCPM-Embedding-Light" ]; then
    DOCKER_ARGS+=(-v "${EMBEDDING_MODEL_DIR}/MiniCPM-Embedding-Light:/workspace/models/MiniCPM-Embedding-Light:ro")
  else
    DOCKER_ARGS+=(-v "${EMBEDDING_MODEL_DIR}:/workspace/models/MiniCPM-Embedding-Light:ro")
  fi
  if [ -d "${EMBEDDING_MODEL_DIR}/MiniCPM-Reranker-Light" ]; then
    DOCKER_ARGS+=(-v "${EMBEDDING_MODEL_DIR}/MiniCPM-Reranker-Light:/workspace/models/MiniCPM-Reranker-Light:ro")
  fi
  if [ -d "${EMBEDDING_MODEL_DIR}/bce-reranker-base_v1" ]; then
    DOCKER_ARGS+=(-v "${EMBEDDING_MODEL_DIR}/bce-reranker-base_v1:/workspace/models/bce-reranker-base_v1:ro")
  fi
fi
if [ -n "${RERANK_MODEL_DIR}" ] && [ -d "${RERANK_MODEL_DIR}" ]; then
  DOCKER_ARGS+=(-v "${RERANK_MODEL_DIR}:/workspace/models/MiniCPM-Reranker-Light:ro")
fi
if [ -n "${BCE_RERANK_MODEL_DIR}" ] && [ -d "${BCE_RERANK_MODEL_DIR}" ]; then
  DOCKER_ARGS+=(-v "${BCE_RERANK_MODEL_DIR}:/workspace/models/bce-reranker-base_v1:ro")
fi

DOCKER_ARGS+=("${IMAGE_NAME}")

docker run "${DOCKER_ARGS[@]}"

echo ""
echo "Master container started: ${CONTAINER_NAME}"
echo "Registry: http://${REGISTRY_IP}:${REGISTRY_PORT}"
echo "Router:   http://${REGISTRY_IP}:${ROUTER_PORT}"
echo ""
echo "Logs: docker logs -f ${CONTAINER_NAME}"

if [ -n "${EMBEDDING_MODEL_DIR}" ] && [ -d "${EMBEDDING_MODEL_DIR}" ]; then
  echo ""
  echo "Embedding server will be managed by babysitter (master-embeddings.toml)"
  echo "  Embedding API: http://${REGISTRY_IP}:${EMBEDDING_PORT}/v1/embeddings"
else
  echo ""
  echo "Embedding server config included but will not start (EMBEDDING_MODEL_DIR not set or invalid)"
  echo "  To enable: export EMBEDDING_MODEL_DIR=/path/to/MiniCPM-Embedding-Light"
fi
