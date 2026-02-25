#!/usr/bin/env bash
# Benchmark script for 2 vLLM instances (round-robin routing)
# Runs both 16KB and 65KB context benchmarks
# Uses openai-chat backend for /v1/chat/completions endpoint

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
REGISTRY_IP="${1:-localhost}"
ROUTER_PORT="${ROUTER_PORT:-8000}"
ROUTER_URL="http://${REGISTRY_IP}:${ROUTER_PORT}"

# vLLM bench configuration
VLLM_DIR="${VLLM_DIR:-/home/zenghua/repos/vllm}"
CONDA_ENV_NAME="${CONDA_ENV_NAME:-vllm-bench}"
MODEL="${MODEL:-/models/Qwen3-32B}"
REQUEST_RATE="${REQUEST_RATE:-1.0}"
NUM_CONVERSATIONS="${NUM_CONVERSATIONS:-4}"
MESSAGES_PER_CONV="${MESSAGES_PER_CONV:-4}"
NUM_REQUESTS=$((NUM_CONVERSATIONS * MESSAGES_PER_CONV))
MAX_CONCURRENCY="${MAX_CONCURRENCY:-4}"

# Datasets (16KB and 65KB context)
# Set CONTEXT=16KB or CONTEXT=65KB to run only that benchmark (default: both)
DATASET_16KB="${SCRIPT_DIR}/large_context_16000.jsonl"
DATASET_65KB="${SCRIPT_DIR}/large_context_65536.jsonl"
CONTEXT="${CONTEXT:-both}"

# Tokenizer path - QWEN3_32B_DIR for vLLM deployment
TOKENIZER_DIR="${TOKENIZER_DIR:-${QWEN3_32B_DIR:-}}"
if [ -z "${TOKENIZER_DIR}" ] || [ ! -d "${TOKENIZER_DIR}" ]; then
  echo "Error: TOKENIZER_DIR or QWEN3_32B_DIR must point to Qwen3-32B model directory"
  echo "  export QWEN3_32B_DIR=/path/to/Qwen3-32B"
  exit 1
fi

echo "=========================================="
echo "2 vLLM Instances Benchmark (Round-Robin)"
echo "=========================================="
echo "Router URL: ${ROUTER_URL}"
echo "Model: ${MODEL}"
echo "Request Rate: ${REQUEST_RATE} req/s"
echo "Total Requests: ${NUM_REQUESTS} per run (context: ${CONTEXT})"
echo "Max Concurrency: ${MAX_CONCURRENCY}"
echo ""

# Check router
if ! curl -s -f --connect-timeout 3 "${ROUTER_URL}/health" > /dev/null 2>&1; then
  echo "Error: Router not accessible at ${ROUTER_URL}"
  echo "  Start vLLM deployment: ./start-master-2vllm-qwen3-32b.sh ${REGISTRY_IP}"
  exit 1
fi

# Ensure datasets exist for requested context(s)
NEED_16KB=false
NEED_65KB=false
case "${CONTEXT}" in
  16KB)  NEED_16KB=true ;;
  65KB)  NEED_65KB=true ;;
  both)  NEED_16KB=true; NEED_65KB=true ;;
  *)
    echo "Error: CONTEXT must be 16KB, 65KB, or both (got: ${CONTEXT})"
    exit 1
    ;;
esac

generate_if_missing() {
  local f="$1"
  local ctx_len="$2"
  if [ ! -f "${f}" ]; then
    echo "Generating dataset: $(basename ${f})..."
    python "${SCRIPT_DIR}/gen-large-context.py" \
      --output "${f}" \
      --num-conversations "${NUM_CONVERSATIONS}" \
      --messages-per-conv "${MESSAGES_PER_CONV}" \
      --context-len 512 \
      --new-msg-len 64 \
      --num-large-context 1 \
      --large-context-len "${ctx_len}"
    echo ""
  fi
}
[ "${NEED_16KB}" = true ] && generate_if_missing "${DATASET_16KB}" 16000
[ "${NEED_65KB}" = true ] && generate_if_missing "${DATASET_65KB}" 65536

# Activate conda
if command -v conda &> /dev/null; then
  eval "$(conda shell.bash hook)"
  conda activate "${CONDA_ENV_NAME}" 2>/dev/null || true
fi

export PYTHONPATH="${VLLM_DIR}:${PYTHONPATH:-}"
export PYTHONWARNINGS="ignore::UserWarning"
export HF_HUB_OFFLINE=1

run_bench() {
  local context_label="$1"
  local dataset_file="$2"
  local log_file="${SCRIPT_DIR}/bench-2vllm-${context_label}.log"

  echo "=========================================="
  echo "Benchmark: ${context_label} context"
  echo "=========================================="
  echo "Dataset: ${dataset_file}"
  echo ""

  python -u -W ignore::UserWarning "${SCRIPT_DIR}/run_benchmark.py" "${VLLM_DIR}" \
    --backend openai-chat \
    --host "${REGISTRY_IP}" \
    --port "${ROUTER_PORT}" \
    --endpoint /v1/chat/completions \
    --model "${MODEL}" \
    --tokenizer "${TOKENIZER_DIR}" \
    --dataset-name custom \
    --dataset-path "${dataset_file}" \
    --request-rate "${REQUEST_RATE}" \
    --num-prompts "${NUM_REQUESTS}" \
    --max-concurrency "${MAX_CONCURRENCY}" \
    --label "2vllm-round-robin" \
    --save-result \
    --result-dir "${SCRIPT_DIR}/results" \
    --ready-check-timeout-sec 0 \
    2>&1 | tee "${log_file}"

  local code=${PIPESTATUS[0]}
  if [ ${code} -ne 0 ]; then
    echo "Benchmark failed for ${context_label} (exit code ${code})"
    return ${code}
  fi
  echo ""
  return 0
}

# Run benchmark(s)
if [ "${NEED_16KB}" = true ]; then
  run_bench "16KB" "${DATASET_16KB}" || exit 1
fi
if [ "${NEED_65KB}" = true ]; then
  run_bench "65KB" "${DATASET_65KB}" || exit 1
fi

# Summary
echo "=========================================="
echo "Benchmark Complete"
echo "=========================================="
echo "Results: ${SCRIPT_DIR}/results/"
ls -la "${SCRIPT_DIR}/results"/2vllm-round-robin-*.json 2>/dev/null || true
