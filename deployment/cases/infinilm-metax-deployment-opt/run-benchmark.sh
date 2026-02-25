#!/usr/bin/env bash
# Run cache-type-routing-validation benchmark against existing infinilm-metax-deployment-opt
# Reuses benchmark tools and datasets from cache-type-routing-validation.
# Deployment must already be running at ROUTER_HOST:ROUTER_PORT.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_VAL_DIR="${SCRIPT_DIR}/../cache-type-routing-validation"

# Configuration - Router endpoint (deployment already running)
ROUTER_HOST="${1:-${ROUTER_HOST:-192.168.163.151}}"
ROUTER_PORT="${ROUTER_PORT:-8000}"
ROUTER_URL="http://${ROUTER_HOST}:${ROUTER_PORT}"

# Model and benchmark params (aligned with cache-type-routing-validation RESULTS_SUMMARY.md)
MODEL="${MODEL:-Qwen3-32B}"
REQUEST_RATE="${REQUEST_RATE:-1.0}"
MAX_CONCURRENCY="${MAX_CONCURRENCY:-4}"
NUM_CONVERSATIONS="${NUM_CONVERSATIONS:-4}"
MESSAGES_PER_CONV="${MESSAGES_PER_CONV:-4}"
NUM_REQUESTS=$((NUM_CONVERSATIONS * MESSAGES_PER_CONV))

# Required: vLLM for run_benchmark.py, Qwen3-32B for tokenizer
VLLM_DIR="${VLLM_DIR:-/home/zenghua/repos/vllm}"
TOKENIZER_DIR="${TOKENIZER_DIR:-${QWEN3_32B_DIR:-}}"
CONDA_ENV_NAME="${CONDA_ENV_NAME:-vllm-bench}"

usage() {
  echo "Usage:"
  echo "  $0 [ROUTER_HOST]"
  echo ""
  echo "Run cache-type-routing-validation benchmark against existing deployment."
  echo "Default ROUTER_HOST: 192.168.163.151, ROUTER_PORT: 8000"
  echo ""
  echo "Required env:"
  echo "  QWEN3_32B_DIR  - Path to Qwen3-32B model (for tokenizer)"
  echo "  VLLM_DIR       - Path to vLLM repo (default: /home/zenghua/repos/vllm)"
  echo ""
  echo "Example:"
  echo "  export QWEN3_32B_DIR=/path/to/Qwen3-32B"
  echo "  ./run-benchmark.sh"
  echo "  ROUTER_HOST=10.0.0.1 ROUTER_PORT=8000 ./run-benchmark.sh"
}

# Prerequisite checks
if [ -z "${TOKENIZER_DIR}" ] || [ ! -d "${TOKENIZER_DIR}" ]; then
  echo "Error: QWEN3_32B_DIR or TOKENIZER_DIR must point to the Qwen3-32B model directory"
  usage
  exit 1
fi

if [ ! -d "${VLLM_DIR}" ]; then
  echo "Error: VLLM_DIR does not exist: ${VLLM_DIR}"
  usage
  exit 1
fi

if [ ! -f "${VLLM_DIR}/vllm/benchmarks/serve.py" ]; then
  echo "Error: vLLM benchmarks not found at ${VLLM_DIR}/vllm/benchmarks/serve.py"
  exit 1
fi

if [ ! -f "${CACHE_VAL_DIR}/run_benchmark.py" ]; then
  echo "Error: cache-type-routing-validation run_benchmark.py not found: ${CACHE_VAL_DIR}/run_benchmark.py"
  exit 1
fi

if [ ! -f "${CACHE_VAL_DIR}/gen-large-context.py" ]; then
  echo "Error: cache-type-routing-validation gen-large-context.py not found: ${CACHE_VAL_DIR}/gen-large-context.py"
  exit 1
fi

# Create results directory
mkdir -p "${SCRIPT_DIR}/results"

# Activate conda if available
if command -v conda &> /dev/null; then
  eval "$(conda shell.bash hook)"
  conda activate "${CONDA_ENV_NAME}" 2>/dev/null || true
fi

echo "=========================================="
echo "infinilm-metax-deployment-opt Benchmark"
echo "=========================================="
echo "Router URL:     ${ROUTER_URL}"
echo "Model:          ${MODEL}"
echo "Request Rate:   ${REQUEST_RATE} req/s"
echo "Max Concurrency: ${MAX_CONCURRENCY}"
echo "Total Requests: ${NUM_REQUESTS}"
echo "Tokenizer:      ${TOKENIZER_DIR}"
echo ""

# Check router health
echo "Checking router at ${ROUTER_URL}..."
if ! curl -s -f --connect-timeout 3 --noproxy "*" "${ROUTER_URL}/health" > /dev/null 2>&1; then
  echo "Error: Router is not accessible at ${ROUTER_URL}"
  echo "Ensure infinilm-metax-deployment-opt is running (e.g. ./start-master.sh <MASTER_IP>)"
  exit 1
fi
echo "Router is reachable."
echo ""

# Ensure datasets exist (use absolute paths since we cd to VLLM_DIR)
DATASET_16KB="$(cd "${CACHE_VAL_DIR}" && pwd)/large_context_16000.jsonl"
DATASET_65KB="$(cd "${CACHE_VAL_DIR}" && pwd)/large_context_65536.jsonl"

for f in "${DATASET_16KB}" "${DATASET_65KB}"; do
  if [ ! -f "${f}" ]; then
    ctx_len=16000
    [ "${f}" = "${DATASET_65KB}" ] && ctx_len=65536
    echo "Generating dataset: $(basename ${f})..."
    python "${CACHE_VAL_DIR}/gen-large-context.py" \
      --output "${f}" \
      --num-conversations "${NUM_CONVERSATIONS}" \
      --messages-per-conv "${MESSAGES_PER_CONV}" \
      --context-len 512 \
      --new-msg-len 64 \
      --num-large-context 1 \
      --large-context-len "${ctx_len}"
    echo ""
  fi
done

# Environment for benchmark
export PYTHONPATH="${VLLM_DIR}:${PYTHONPATH:-}"
export PYTHONWARNINGS="ignore::UserWarning"
export HF_HUB_OFFLINE=1

# Use absolute path for result dir (vLLM may use cwd otherwise)
RESULT_DIR="$(cd "${SCRIPT_DIR}" && pwd)/results"
mkdir -p "${RESULT_DIR}"

# Run from VLLM_DIR to match cache-type-routing-validation bench behavior
cd "${VLLM_DIR}"

run_bench() {
  local context_label="$1"
  local dataset_file="$2"
  local log_file="${SCRIPT_DIR}/bench-metax-opt-${context_label}.log"

  echo "=========================================="
  echo "Benchmark: ${context_label} context"
  echo "=========================================="
  echo "Dataset: ${dataset_file}"
  echo ""

  python -u -W ignore::UserWarning "${CACHE_VAL_DIR}/run_benchmark.py" "${VLLM_DIR}" \
    --backend openai \
    --host "${ROUTER_HOST}" \
    --port "${ROUTER_PORT}" \
    --endpoint /v1/chat/completions \
    --model "${MODEL}" \
    --tokenizer "${TOKENIZER_DIR}" \
    --dataset-name custom \
    --dataset-path "${dataset_file}" \
    --request-rate "${REQUEST_RATE}" \
    --num-prompts "${NUM_REQUESTS}" \
    --max-concurrency "${MAX_CONCURRENCY}" \
    --label "metax-opt" \
    --save-result \
    --result-dir "${RESULT_DIR}" \
    --ready-check-timeout-sec 0 \
    2>&1 | tee "${log_file}"

  local code=${PIPESTATUS[0]}
  if [ ${code} -ne 0 ]; then
    echo "Benchmark failed for ${context_label} (exit code ${code})"
    return ${code}
  fi
  # Copy result from VLLM_DIR if vLLM wrote to cwd instead of result-dir
  for f in "${VLLM_DIR}"/metax-opt-*.json; do
    if [ -f "${f}" ] && [ ! -f "${RESULT_DIR}/$(basename "${f}")" ]; then
      echo "Copying result from cwd to ${RESULT_DIR}/"
      cp -v "${f}" "${RESULT_DIR}/"
    fi
  done 2>/dev/null || true
  echo ""
  return 0
}

# Run 16KB benchmark
run_bench "16KB" "${DATASET_16KB}" || exit 1

# Run 65KB benchmark
run_bench "65KB" "${DATASET_65KB}" || exit 1

# Summary
echo "=========================================="
echo "Benchmark Complete"
echo "=========================================="
echo "Results saved to: ${RESULT_DIR}/"
if ls "${RESULT_DIR}"/metax-opt-*.json 1>/dev/null 2>&1; then
  ls -la "${RESULT_DIR}"/metax-opt-*.json
else
  echo "No metax-opt result files found."
  echo "Checking VLLM cwd (${VLLM_DIR}) for results..."
  ls -la "${VLLM_DIR}"/metax-opt-*.json 2>/dev/null || true
fi
echo ""
echo "To compare with cache-type-routing-validation:"
echo "  cd ${CACHE_VAL_DIR}"
echo "  python compare-routing-strategies.py \\"
echo "    --size-based results/size-based-routing-*.json \\"
echo "    --2paged ${RESULT_DIR}/metax-opt-*.json"
echo ""
