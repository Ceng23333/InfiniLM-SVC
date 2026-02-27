#!/usr/bin/env bash
# Run jg_rag benchmark against existing infinilm-metax-deployment-opt deployment
# Uses jg_rag_benchmark.jsonl (generate with bench/gen-jg_rag-benchmark.py)
# Deployment must already be running at ROUTER_HOST:ROUTER_PORT

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_DIR="${SCRIPT_DIR}/bench"
CACHE_VAL_DIR="${SCRIPT_DIR}/../cache-type-routing-validation"

# Configuration - Router endpoint
ROUTER_HOST="${1:-${ROUTER_HOST:-192.168.163.151}}"
ROUTER_PORT="${ROUTER_PORT:-8000}"
ROUTER_URL="http://${ROUTER_HOST}:${ROUTER_PORT}"

# Model and benchmark params
MODEL="${MODEL:-Qwen3-32B}"
REQUEST_RATE="${REQUEST_RATE:-1.0}"
MAX_CONCURRENCY="${MAX_CONCURRENCY:-4}"
LABEL="${LABEL:-jg_rag-baseline}"

# Required: vLLM for run_benchmark.py, Qwen3-32B for tokenizer
VLLM_DIR="${VLLM_DIR:-/home/zenghua/repos/vllm}"
TOKENIZER_DIR="${TOKENIZER_DIR:-${QWEN3_32B_DIR:-}}"
CONDA_ENV_NAME="${CONDA_ENV_NAME:-vllm-bench}"

# jg_rag dataset
DATASET_FILE="${DATASET_FILE:-${BENCH_DIR}/jg_rag_benchmark.jsonl}"

usage() {
  echo "Usage:"
  echo "  $0 [ROUTER_HOST]"
  echo ""
  echo "Run jg_rag benchmark against existing deployment."
  echo "Default ROUTER_HOST: 192.168.163.151, ROUTER_PORT: 8000"
  echo ""
  echo "Required env:"
  echo "  QWEN3_32B_DIR  - Path to Qwen3-32B model (for tokenizer)"
  echo ""
  echo "Optional env:"
  echo "  DATASET_FILE   - Path to jg_rag_benchmark.jsonl (default: bench/jg_rag_benchmark.jsonl)"
  echo "  LABEL          - Result label (default: jg_rag-baseline)"
  echo ""
  echo "Generate dataset: python bench/gen-jg_rag-benchmark.py"
  echo ""
  echo "Example:"
  echo "  export QWEN3_32B_DIR=/path/to/Qwen3-32B"
  echo "  ./run-jg_rag-benchmark.sh"
  echo "  ROUTER_HOST=192.168.163.151 ./run-jg_rag-benchmark.sh"
}

if [ -z "${TOKENIZER_DIR}" ] || [ ! -d "${TOKENIZER_DIR}" ]; then
  echo "Error: QWEN3_32B_DIR or TOKENIZER_DIR must point to the Qwen3-32B model directory"
  usage
  exit 1
fi

if [ ! -f "${DATASET_FILE}" ]; then
  echo "Error: Dataset not found: ${DATASET_FILE}"
  echo "Generate with: python ${BENCH_DIR}/gen-jg_rag-benchmark.py"
  exit 1
fi

if [ ! -d "${VLLM_DIR}" ]; then
  echo "Error: VLLM_DIR does not exist: ${VLLM_DIR}"
  exit 1
fi

if [ ! -f "${VLLM_DIR}/vllm/benchmarks/serve.py" ]; then
  echo "Error: vLLM benchmarks not found at ${VLLM_DIR}/vllm/benchmarks/serve.py"
  exit 1
fi

if [ ! -f "${CACHE_VAL_DIR}/run_benchmark.py" ]; then
  echo "Error: run_benchmark.py not found: ${CACHE_VAL_DIR}/run_benchmark.py"
  exit 1
fi

# Count records in dataset
NUM_REQUESTS=$(wc -l < "${DATASET_FILE}")

# Create results directory
RESULTS_DIR="${SCRIPT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

# Activate conda if available
if command -v conda &> /dev/null; then
  eval "$(conda shell.bash hook)"
  conda activate "${CONDA_ENV_NAME}" 2>/dev/null || true
fi

echo "=========================================="
echo "jg_rag Benchmark (baseline)"
echo "=========================================="
echo "Router URL:     ${ROUTER_URL}"
echo "Model:          ${MODEL}"
echo "Dataset:        ${DATASET_FILE}"
echo "Total Requests: ${NUM_REQUESTS}"
echo "Request Rate:   ${REQUEST_RATE} req/s"
echo "Max Concurrency: ${MAX_CONCURRENCY}"
echo "Result Label:   ${LABEL}"
echo ""

# Check router health
echo "Checking router at ${ROUTER_URL}..."
if ! curl -s -f --connect-timeout 3 --noproxy "*" "${ROUTER_URL}/health" > /dev/null 2>&1; then
  echo "Error: Router is not accessible at ${ROUTER_URL}"
  echo "Ensure deployment is running (e.g. ./start-master.sh <MASTER_IP>)"
  exit 1
fi
echo "Router is reachable."
echo ""

# Environment for benchmark
export PYTHONPATH="${VLLM_DIR}:${PYTHONPATH:-}"
export PYTHONWARNINGS="ignore::UserWarning"
export HF_HUB_OFFLINE=1

cd "${VLLM_DIR}"

LOG_FILE="${SCRIPT_DIR}/bench-jg_rag-${LABEL}.log"
echo "Running benchmark (log: ${LOG_FILE})..."
echo ""

python -u -W ignore::UserWarning "${CACHE_VAL_DIR}/run_benchmark.py" "${VLLM_DIR}" \
  --backend openai-chat \
  --host "${ROUTER_HOST}" \
  --port "${ROUTER_PORT}" \
  --endpoint /v1/chat/completions \
  --model "${MODEL}" \
  --tokenizer "${TOKENIZER_DIR}" \
  --dataset-name custom \
  --dataset-path "${DATASET_FILE}" \
  --request-rate "${REQUEST_RATE}" \
  --num-prompts "${NUM_REQUESTS}" \
  --max-concurrency "${MAX_CONCURRENCY}" \
  --label "${LABEL}" \
  --save-result \
  --result-dir "${RESULTS_DIR}" \
  --ready-check-timeout-sec 0 \
  2>&1 | tee "${LOG_FILE}"

CODE=${PIPESTATUS[0]}
if [ ${CODE} -ne 0 ]; then
  echo "Benchmark failed (exit code ${CODE})"
  exit ${CODE}
fi

# Copy result from VLLM_DIR if written to cwd
for f in "${VLLM_DIR}"/${LABEL}-*.json; do
  if [ -f "${f}" ] && [ ! -f "${RESULTS_DIR}/$(basename "${f}")" ]; then
    cp -v "${f}" "${RESULTS_DIR}/"
  fi
done 2>/dev/null || true

echo ""
echo "=========================================="
echo "Benchmark Complete"
echo "=========================================="
echo "Results: ${RESULTS_DIR}/"
ls -la "${RESULTS_DIR}"/${LABEL}-*.json 2>/dev/null || true
echo ""
