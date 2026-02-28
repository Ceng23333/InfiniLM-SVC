#!/usr/bin/env bash
# Offline deployment: load Docker image from tar and start services with model
#
# Prerequisites:
#   - Docker with NVIDIA Container Toolkit
#   - Image tar (e.g. infinilm-svc-nvidia.tar from: docker save infinilm-svc:nvidia -o infinilm-svc-nvidia.tar)
#   - Model directory: 9g_8b_thinking_llama or 9g_8b_thinking (will auto-convert)
#
# Usage:
#   ./deploy-offline.sh --image-tar /path/to/infinilm-svc-nvidia.tar --model-dir /path/to/9g_8b_thinking_llama
#   # Or via env:
#   IMAGE_TAR=./infinilm-svc-nvidia.tar MODEL1_DIR=/data/models/9g_8b_thinking_llama ./deploy-offline.sh
#
# Options:
#   --image-tar PATH   Docker image tar file (required if IMAGE_TAR not set)
#   --model-dir PATH   Model directory (required if MODEL1_DIR not set)
#   --ports PORT       Registry:router ports, e.g. 18000:8000 (default)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_TAR=""
MODEL1_DIR=""
REGISTRY_PORT=""
ROUTER_PORT=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --image-tar)
      IMAGE_TAR="$2"
      shift 2
      ;;
    --model-dir)
      MODEL1_DIR="$2"
      shift 2
      ;;
    --ports)
      # Format: 18000:8000
      REGISTRY_PORT="${2%%:*}"
      ROUTER_PORT="${2##*:}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--image-tar PATH] [--model-dir PATH] [--ports REGISTRY:ROUTER]"
      echo "  --image-tar   Docker image tar (or set IMAGE_TAR)"
      echo "  --model-dir   Model directory (or set MODEL1_DIR)"
      echo "  --ports       e.g. 18000:8000"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Defaults (env vars override if set before script run)
REGISTRY_PORT="${REGISTRY_PORT:-18000}"
ROUTER_PORT="${ROUTER_PORT:-8000}"

# Validate
if [ -z "${IMAGE_TAR}" ] || [ ! -f "${IMAGE_TAR}" ]; then
  echo "Error: Image tar not found. Use --image-tar PATH or set IMAGE_TAR"
  echo "  Example: docker save infinilm-svc:nvidia -o infinilm-svc-nvidia.tar"
  exit 1
fi

if [ -z "${MODEL1_DIR}" ] || [ ! -d "${MODEL1_DIR}" ]; then
  echo "Error: Model directory not found. Use --model-dir PATH or set MODEL1_DIR"
  echo "  Accepts: 9g_8b_thinking or 9g_8b_thinking_llama"
  exit 1
fi

echo "=========================================="
echo "InfiniLM-SVC 离线部署 (Offline Deployment)"
echo "=========================================="
echo "Image tar:  ${IMAGE_TAR}"
echo "Model dir:  ${MODEL1_DIR}"
echo "Ports:      Registry ${REGISTRY_PORT}, Router ${ROUTER_PORT}"
echo ""

# 1. Load image
echo "[1/3] 加载 Docker 镜像..."
docker load -i "${IMAGE_TAR}"
echo "  -> 完成"
echo ""

# 2. Export for start-master
export IMAGE_NAME="infinilm-svc:nvidia"
export MODEL1_DIR
export REGISTRY_PORT
export ROUTER_PORT
export CONTAINER_NAME="infinilm-svc-master"

# 3. Start services
echo "[2/3] 启动服务..."
"${SCRIPT_DIR}/start-master.sh" localhost
echo ""

echo "[3/3] 验证..."
sleep 5
if [ -x "${SCRIPT_DIR}/validate.sh" ]; then
  REGISTRY_PORT="${REGISTRY_PORT}" ROUTER_PORT="${ROUTER_PORT}" "${SCRIPT_DIR}/validate.sh" || true
else
  echo "  curl http://localhost:${REGISTRY_PORT}/health"
  echo "  curl http://localhost:${ROUTER_PORT}/health"
fi

echo ""
echo "部署完成。"
echo "  Registry: http://localhost:${REGISTRY_PORT}"
echo "  Router:   http://localhost:${ROUTER_PORT}"
echo "  日志:     docker logs -f ${CONTAINER_NAME}"
echo "  停止:     docker stop ${CONTAINER_NAME}"
