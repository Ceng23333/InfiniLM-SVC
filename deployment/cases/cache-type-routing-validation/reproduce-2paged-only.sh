#!/usr/bin/env bash
# Reproduce only the 2-paged round-robin benchmarks (16KB + 65KB) for cache-type-routing-validation.
# Uses same env and wait logic as reproduce-results.sh; one container start, two benchmark runs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

REGISTRY_IP="${1:-localhost}"
IMAGE_NAME="${IMAGE_NAME:-infinilm-svc:runtime-cache-type-routing-validation-issue1004}"
MODEL="${MODEL:-Qwen3-32B}"
REQUEST_RATE="${REQUEST_RATE:-1.0}"
MAX_CONCURRENCY="${MAX_CONCURRENCY:-4}"
NUM_CONVERSATIONS="${NUM_CONVERSATIONS:-4}"
MESSAGES_PER_CONV="${MESSAGES_PER_CONV:-4}"
QWEN3_32B_DIR="${QWEN3_32B_DIR:-}"
VLLM_DIR="${VLLM_DIR:-/home/zenghua/repos/vllm}"
TOKENIZER_DIR="${TOKENIZER_DIR:-${QWEN3_32B_DIR}}"
MAX_READY_WAIT="${MAX_READY_WAIT:-600}"

if [ -z "${QWEN3_32B_DIR}" ] || [ ! -d "${QWEN3_32B_DIR}" ]; then
  echo "❌ Error: QWEN3_32B_DIR must point to the Qwen3-32B model directory"
  exit 1
fi
if [ ! -d "${VLLM_DIR}" ]; then
  echo "❌ Error: VLLM_DIR does not exist: ${VLLM_DIR}"
  exit 1
fi
if ! docker images "${IMAGE_NAME}" 2>/dev/null | tail -n +2 | grep -q .; then
  echo "❌ Error: Docker image ${IMAGE_NAME} not found"
  exit 1
fi

echo "=========================================="
echo "2-Paged Only: Reproducing Benchmarks"
echo "=========================================="
echo "Image: ${IMAGE_NAME}"
echo "Model: ${MODEL}"
echo ""

# Ensure datasets exist
DATASET_16KB="${SCRIPT_DIR}/large_context_16000.jsonl"
DATASET_65KB="${SCRIPT_DIR}/large_context_65536.jsonl"
for f in "${DATASET_16KB}" "${DATASET_65KB}"; do
  if [ ! -f "${f}" ]; then
    echo "Generating ${f}..."
    python gen-large-context.py \
      --output "${f}" \
      --num-conversations "${NUM_CONVERSATIONS}" \
      --messages-per-conv "${MESSAGES_PER_CONV}" \
      --context-len 512 \
      --new-msg-len 64 \
      --num-large-context 1 \
      --large-context-len "$([ "${f}" = "${DATASET_16KB}" ] && echo 16000 || echo 65536)"
  fi
done

# Stop any existing master containers
echo "Stopping existing containers..."
docker rm -f infinilm-svc-master-qwen3-32b infinilm-svc-master-2paged-qwen3-32b 2>/dev/null || true
sleep 2

# Start 2-paged deployment
echo "Starting 2-paged round-robin deployment..."
export IMAGE_NAME QWEN3_32B_DIR
./start-master-2paged-qwen3-32b.sh "${REGISTRY_IP}"

# Wait for router then model (simplified wait)
echo "Waiting for model (max ${MAX_READY_WAIT}s)..."
waited=0
while [ ${waited} -lt ${MAX_READY_WAIT} ]; do
  if curl -sf --connect-timeout 3 "http://${REGISTRY_IP}:8000/health" >/dev/null 2>&1; then
    resp=$(curl -s -X POST "http://${REGISTRY_IP}:8000/v1/chat/completions" \
      -H "Content-Type: application/json" \
      -d "{\"model\": \"${MODEL}\", \"messages\": [{\"role\": \"user\", \"content\": \"hi\"}], \"max_tokens\": 1}" 2>&1)
    if ! echo "${resp}" | grep -q "No healthy services"; then
      echo "✓ Model ready"
      break
    fi
  fi
  sleep 10
  waited=$((waited + 10))
  echo "  ... ${waited}s"
done
if [ ${waited} -ge ${MAX_READY_WAIT} ]; then
  echo "⚠ Model not ready after ${MAX_READY_WAIT}s; continuing anyway."
fi

# 16KB
echo ""
echo "========== 2-Paged Benchmark: 16KB =========="
export MODEL REQUEST_RATE MAX_CONCURRENCY NUM_CONVERSATIONS MESSAGES_PER_CONV
export NUM_LARGE_CONTEXT=1
export DATASET_FILE="${SCRIPT_DIR}/large_context_16000.jsonl"
export TOKENIZER_DIR VLLM_DIR
./bench-2paged.sh "${REGISTRY_IP}"

# 65KB (same container)
echo ""
echo "========== 2-Paged Benchmark: 65KB =========="
export DATASET_FILE="${SCRIPT_DIR}/large_context_65536.jsonl"
./bench-2paged.sh "${REGISTRY_IP}"

echo ""
echo "=========================================="
echo "2-Paged reproduction complete. Results in results/"
echo "=========================================="
ls -la results/2paged-round-robin*.json 2>/dev/null | tail -4
