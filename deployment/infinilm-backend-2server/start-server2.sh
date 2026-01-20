#!/usr/bin/env bash
# Start Server 2: Babysitter B (InfiniLM backend) registering to Server 1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-infinilm-svc:infinilm-demo}"
USE_HOST_NETWORK="${USE_HOST_NETWORK:-true}"

if [ $# -lt 2 ]; then
  echo "Usage: $0 <SERVER1_IP> <SERVER2_IP>"
  exit 1
fi

SERVER1_IP="$1"
SERVER2_IP="$2"

INFINILM_DIR="${INFINILM_DIR:-}"
MODEL_DIR="${MODEL_DIR:-}"

if [ -z "${INFINILM_DIR}" ] || [ ! -d "${INFINILM_DIR}" ]; then
  echo "Error: INFINILM_DIR must point to an InfiniLM checkout on this host."
  echo "  Example: export INFINILM_DIR=/path/to/InfiniLM"
  exit 1
fi

if [ -z "${MODEL_DIR}" ] || [ ! -d "${MODEL_DIR}" ]; then
  echo "Error: MODEL_DIR must point to the model directory on this host."
  echo "  Example: export MODEL_DIR=/path/to/model_dir"
  exit 1
fi

echo "=========================================="
echo "Starting InfiniLM-SVC Server 2 (InfiniLM backend)"
echo "=========================================="
echo "Server 1 IP (Registry/Router): ${SERVER1_IP}"
echo "Server 2 IP (This server):     ${SERVER2_IP}"
echo "Image: ${IMAGE_NAME}"
echo "Components: Babysitter B"
echo "Docker network: $([ "${USE_HOST_NETWORK}" = "true" ] && echo "host" || echo "bridge (-p ports)")"
echo "INFINILM_DIR: ${INFINILM_DIR}"
echo "MODEL_DIR: ${MODEL_DIR}"
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
if [ "${USE_HOST_NETWORK}" = "true" ]; then
  docker run -d \
    --network host \
    --name infinilm-svc-infinilm-server2 \
    -e LAUNCH_COMPONENTS=babysitter \
    -e REGISTRY_URL="http://${SERVER1_IP}:18000" \
    -e ROUTER_URL="http://${SERVER1_IP}:8000" \
    -e BABYSITTER_HOST="${SERVER2_IP}" \
    -e BABYSITTER_CONFIGS="babysitter-b.toml" \
    -v "${SCRIPT_DIR}/config:/app/config:ro" \
    -v "${INFINILM_DIR}:/mnt/InfiniLM:ro" \
    -v "${MODEL_DIR}:/models/model:ro" \
    "${IMAGE_NAME}"
else
  docker run -d \
    --name infinilm-svc-infinilm-server2 \
    -e LAUNCH_COMPONENTS=babysitter \
    -e REGISTRY_URL="http://${SERVER1_IP}:18000" \
    -e ROUTER_URL="http://${SERVER1_IP}:8000" \
    -e BABYSITTER_HOST="${SERVER2_IP}" \
    -e BABYSITTER_CONFIGS="babysitter-b.toml" \
    -p 8100:8100 -p 8101:8101 \
    -v "${SCRIPT_DIR}/config:/app/config:ro" \
    -v "${INFINILM_DIR}:/mnt/InfiniLM:ro" \
    -v "${MODEL_DIR}:/models/model:ro" \
    "${IMAGE_NAME}"
fi

echo ""
echo "✅ Server 2 container started: infinilm-svc-infinilm-server2"
echo "Logs: docker logs -f infinilm-svc-infinilm-server2"
