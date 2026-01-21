#!/usr/bin/env bash
# Start Slave: Two babysitters (InfiniLM backends) registering to Master

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-infinilm-svc:infinilm-demo}"

usage() {
  echo "Usage: $0 <MASTER_IP> <SLAVE_IP> [SLAVE_ID]"
  echo ""
  echo "Examples:"
  echo "  $0 172.22.162.17 172.22.162.18"
  echo "  $0 172.22.162.17 172.22.162.19 2   # registers as slave2-*"
}

if [ $# -lt 2 ]; then
  usage
  exit 1
fi

REGISTRY_IP="$1"
LOCALHOST_IP="$2"
SLAVE_ID="${3:-1}"

if ! [[ "${SLAVE_ID}" =~ ^[0-9]+$ ]] || [ "${SLAVE_ID}" -lt 1 ]; then
  echo "Error: SLAVE_ID must be a positive integer (got: ${SLAVE_ID})"
  exit 1
fi

SLAVE_NAME="slave"
if [ "${SLAVE_ID}" -gt 1 ]; then
  SLAVE_NAME="slave${SLAVE_ID}"
fi

# Default container naming: infinilm-svc-slave / infinilm-svc-slave2 / ...
CONTAINER_NAME_DEFAULT="infinilm-svc-${SLAVE_NAME}"
CONTAINER_NAME="${CONTAINER_NAME:-${CONTAINER_NAME_DEFAULT}}"

REGISTRY_PORT="${REGISTRY_PORT:-18000}"
ROUTER_PORT="${ROUTER_PORT:-8000}"

# Optional directories - use /workspace defaults if not provided
INFINILM_DIR="${INFINILM_DIR:-}"
INFINICORE_DIR="${INFINICORE_DIR:-}"
CONFIG_DIR="${CONFIG_DIR:-${SCRIPT_DIR}/config}"

# Config filenames for this slave id
CFG_9G="${SLAVE_NAME}-9g_8b_thinking.toml"
CFG_QWEN="${SLAVE_NAME}-Qwen3-32B.toml"
CFG_QWEN_SVC="${SLAVE_NAME}-service_qwen.toml"

# If SLAVE_ID > 1, auto-generate configs (so registration names are unique) unless already present.
# This avoids having to maintain N copies in git.
if [ "${SLAVE_ID}" -gt 1 ]; then
  if [ ! -f "${CONFIG_DIR}/${CFG_QWEN_SVC}" ]; then
    cat > "${CONFIG_DIR}/${CFG_QWEN_SVC}" <<EOF
[Qwen3-32B]
path = "/models/Qwen3-32B.gguf"
gpus = [4,5,6,7]
max-tokens = 32768
temperature = 0.6
top-p = 0.95
repetition-penalty = 1.02
thinking = false
max-sessions = 1
EOF
  fi

  if [ ! -f "${CONFIG_DIR}/${CFG_9G}" ]; then
    cat > "${CONFIG_DIR}/${CFG_9G}" <<EOF
# ${SLAVE_NAME} (Worker) - 9g_8b_thinking model
#
# Note: registry_url/router_url/host are overridden at runtime by docker entrypoint env:
#   - BABYSITTER_HOST (for registration)
#   - REGISTRY_URL / ROUTER_URL (remote URLs)

name = "${SLAVE_NAME}-9g_8b_thinking"
host = "0.0.0.0"
port = 8100

registry_url = "http://localhost:18000"
router_url = "http://localhost:8000"

[babysitter]
max_restarts = 10000
restart_delay = 5
heartbeat_interval = 30

[backend]
type = "command"
command = "/opt/conda/bin/python"
args = [
  "/workspace/InfiniLM/python/infinilm/server/inference_server.py",
  "--metax",
  "--model_path", "/models/9g_8b_thinking",
  "--max_batch_size", "8",
  "--tp", "1",
  "--temperature", "1.0",
  "--top_p", "0.8",
  "--top_k", "1",
  "--host", "0.0.0.0",
  "--port", "8100",
]
work_dir = "/workspace/InfiniLM"

[backend.env]
PATH = "/opt/conda/bin:/root/.infini/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
PYTHONPATH = "/workspace/InfiniLM/python:/workspace/InfiniCore/python"
INFINI_ROOT = "/root/.infini"
LD_LIBRARY_PATH = "/opt/conda/lib:/root/.infini/lib:/opt/hpcc/lib:/opt/hpcc/htgpu_llvm/lib"
MACA_HOME = "/opt/hpcc"
MACA_PATH = "/opt/hpcc"
HPCC_PATH = "/opt/hpcc"
C_INCLUDE_PATH = "/opt/hpcc/include/hcr:/opt/hpcc/tools/cu-bridge/include"
XMAKE_ROOT = "y"
EOF
  fi

  if [ ! -f "${CONFIG_DIR}/${CFG_QWEN}" ]; then
    cat > "${CONFIG_DIR}/${CFG_QWEN}" <<EOF
# ${SLAVE_NAME} (Worker) - Qwen3-32B model
#
# Note: registry_url/router_url/host are overridden at runtime by docker entrypoint env:
#   - BABYSITTER_HOST (for registration)
#   - REGISTRY_URL / ROUTER_URL (remote URLs)

name = "${SLAVE_NAME}-Qwen3-32B"
host = "0.0.0.0"
port = 8200

registry_url = "http://localhost:18000"
router_url = "http://localhost:8000"

[babysitter]
max_restarts = 10000
restart_delay = 5
heartbeat_interval = 30

[backend]
type = "command"
command = "/root/.infini/bin/xtask"
args = [
  "service",
  "/app/config/${CFG_QWEN_SVC}",
  "-p", "8200"
]
work_dir = "/app"

[backend.env]
PATH = "/opt/conda/bin:/root/.infini/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
INFINI_ROOT = "/root/.infini"
LD_LIBRARY_PATH = "/opt/conda/lib:/root/.infini/lib:/opt/hpcc/lib:/opt/hpcc/htgpu_llvm/lib"
MACA_HOME = "/opt/hpcc"
MACA_PATH = "/opt/hpcc"
HPCC_PATH = "/opt/hpcc"
C_INCLUDE_PATH = "/opt/hpcc/include/hcr:/opt/hpcc/tools/cu-bridge/include"
XMAKE_ROOT = "y"
# Note: GPU selection is controlled by the 'gpus' field in ${CFG_QWEN_SVC}, not by HPCC_VISIBLE_DEVICES
HPCC_VISIBLE_DEVICES = "4,5,6,7"
EOF
  fi
fi

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
echo "Starting InfiniLM-SVC Slave"
echo "=========================================="
echo "Registry IP (Master): ${REGISTRY_IP}"
echo "Localhost IP (Slave): ${LOCALHOST_IP}"
echo "Registry Port: ${REGISTRY_PORT}"
echo "Router Port: ${ROUTER_PORT}"
echo "Image: ${IMAGE_NAME}"
echo "Slave ID: ${SLAVE_ID} (registration prefix: ${SLAVE_NAME}-*)"
echo "Components: ${SLAVE_NAME}-9g_8b_thinking, ${SLAVE_NAME}-Qwen3-32B"
echo "Container: ${CONTAINER_NAME}"
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
echo "🔍 Checking connection to Master registry..."
if ! curl -s -f --connect-timeout 5 "http://${REGISTRY_IP}:${REGISTRY_PORT}/health" > /dev/null 2>&1; then
  echo "❌ Error: Cannot reach Master registry at http://${REGISTRY_IP}:${REGISTRY_PORT}"
  exit 1
fi
echo "✅ Master registry reachable"

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
  -e LAUNCH_COMPONENTS=babysitter
  -e REGISTRY_URL="http://${REGISTRY_IP}:${REGISTRY_PORT}"
  -e ROUTER_URL="http://${REGISTRY_IP}:${ROUTER_PORT}"
  -e BABYSITTER_HOST="${LOCALHOST_IP}"
  -e BABYSITTER_CONFIGS="${CFG_9G} ${CFG_QWEN}"
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
  -v "${MODEL1_DIR}:/models/9g_8b_thinking:ro"
  -v "${MODEL2_MOUNT_DIR}:${MODEL2_CONTAINER_PATH}:ro"
  "${IMAGE_NAME}"
)

docker run "${DOCKER_ARGS[@]}"

echo ""
echo "✅ Slave container started: ${CONTAINER_NAME}"
echo ""
echo "⚠️  IMPORTANT: Install InfiniCore and InfiniLM inside the container if needed:"
echo "   docker exec -it ${CONTAINER_NAME} bash -c '"
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
echo "Logs: docker logs -f ${CONTAINER_NAME}"
