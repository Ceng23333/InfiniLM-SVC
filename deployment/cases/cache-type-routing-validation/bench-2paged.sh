#!/usr/bin/env bash
# Benchmark script for 2 paged cache instances (round-robin routing)
# Validation group for comparing with size-based routing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
REGISTRY_IP="${1:-localhost}"
ROUTER_PORT="${ROUTER_PORT:-8000}"
ROUTER_URL="http://${REGISTRY_IP}:${ROUTER_PORT}"

# vLLM bench configuration
VLLM_DIR="${VLLM_DIR:-/home/zenghua/repos/vllm}"
CONDA_ENV_NAME="${CONDA_ENV_NAME:-vllm-bench}"
MODEL="${MODEL:-9g_8b_thinking}"
REQUEST_RATE="${REQUEST_RATE:-1.0}"
NUM_REQUESTS="${NUM_REQUESTS:-64}"

# Large context configuration (same as size-based routing for fair comparison)
NUM_CONVERSATIONS="${NUM_CONVERSATIONS:-4}"      # Number of different conversations
MESSAGES_PER_CONV="${MESSAGES_PER_CONV:-4}"      # Messages per conversation (turns)
NUM_LARGE_CONTEXT="${NUM_LARGE_CONTEXT:-1}"      # Exact number of conversations with large initial context
CONTEXT_LEN="${CONTEXT_LEN:-512}"                 # Context length per message
NEW_MSG_LEN="${NEW_MSG_LEN:-64}"                  # New message length
LARGE_CONTEXT_LEN="${LARGE_CONTEXT_LEN:-20000}"   # Length of large initial context
DATASET_FILE="${DATASET_FILE:-${SCRIPT_DIR}/large_context.jsonl}"
NUM_REQUESTS=$((NUM_CONVERSATIONS * MESSAGES_PER_CONV))
MAX_CONCURRENCY="${MAX_CONCURRENCY:-4}"  # Limit concurrent requests

# Tokenizer path - MODEL1_DIR is required
TOKENIZER_DIR="${TOKENIZER_DIR:-${MODEL1_DIR:-}}"
if [ -z "${TOKENIZER_DIR}" ] || [ ! -d "${TOKENIZER_DIR}" ]; then
  echo "❌ Error: TOKENIZER_DIR or MODEL1_DIR must be set and point to a valid model directory"
  echo ""
  echo "  The benchmark requires a local tokenizer and cannot download from HuggingFace (offline mode)."
  echo "  Please set MODEL1_DIR to point to your model directory:"
  echo ""
  echo "    export MODEL1_DIR=/path/to/9g_8b_thinking_llama"
  echo "    ./bench-2paged.sh 172.22.162.18"
  echo ""
  echo "  Or set TOKENIZER_DIR directly:"
  echo "    export TOKENIZER_DIR=/path/to/model/directory"
  echo ""
  exit 1
fi

TOKENIZER_ARG="--tokenizer ${TOKENIZER_DIR}"
echo "Using tokenizer from: ${TOKENIZER_DIR}"

echo "=========================================="
echo "2 Paged Cache Instances Benchmark (Round-Robin)"
echo "=========================================="
echo "Router URL: ${ROUTER_URL}"
echo "Model: ${MODEL}"
echo "Request Rate: ${REQUEST_RATE} req/s"
echo "Number of Conversations: ${NUM_CONVERSATIONS}"
echo "Messages per Conversation: ${MESSAGES_PER_CONV}"
echo "Total Requests: ${NUM_REQUESTS}"
echo "Max Concurrency: ${MAX_CONCURRENCY}"
echo "Number of Large Context Conversations: ${NUM_LARGE_CONTEXT}"
echo "Context Length per Message: ${CONTEXT_LEN} chars"
echo "New Message Length: ${NEW_MSG_LEN} chars"
echo "Large Context Length: ${LARGE_CONTEXT_LEN} chars"
echo ""
echo "Configuration: Two paged cache instances (8100, 8300)"
echo "Routing: Round-robin (no size-based routing)"
echo "Dataset: Large context with configurable probability"
echo ""

# Check if vLLM directory exists
if [ ! -d "${VLLM_DIR}" ]; then
  echo "Error: VLLM_DIR does not exist: ${VLLM_DIR}"
  echo "  Set VLLM_DIR to point to your vLLM repository"
  exit 1
fi

# Check if benchmark module exists
if [ ! -f "${VLLM_DIR}/vllm/benchmarks/serve.py" ]; then
  echo "Error: vLLM benchmarks module not found at ${VLLM_DIR}/vllm/benchmarks/serve.py"
  exit 1
fi

# Generate large context dataset if it doesn't exist
if [ ! -f "${DATASET_FILE}" ]; then
  echo "Generating large context dataset..."
  python "${SCRIPT_DIR}/gen-large-context.py" \
    --output "${DATASET_FILE}" \
    --num-conversations "${NUM_CONVERSATIONS}" \
    --messages-per-conv "${MESSAGES_PER_CONV}" \
    --context-len "${CONTEXT_LEN}" \
    --new-msg-len "${NEW_MSG_LEN}" \
    --num-large-context "${NUM_LARGE_CONTEXT}" \
    --large-context-len "${LARGE_CONTEXT_LEN}"
  echo ""
fi

# Activate conda environment if available
if command -v conda &> /dev/null; then
  eval "$(conda shell.bash hook)"
  conda activate "${CONDA_ENV_NAME}" 2>/dev/null || {
    echo "Warning: Could not activate conda environment '${CONDA_ENV_NAME}'"
    echo "  Make sure it exists: conda env list"
    echo "  Or create it: ${SCRIPT_DIR}/setup-vllm-env.sh"
  }
fi

# Check if Python is available
if ! command -v python &> /dev/null; then
  echo "Error: Python not found. Please activate the conda environment:"
  echo "  conda activate ${CONDA_ENV_NAME}"
  echo "  Or run: ${SCRIPT_DIR}/setup-vllm-env.sh"
  exit 1
fi

# Check if router is accessible
if ! curl -s -f --connect-timeout 3 "${ROUTER_URL}/health" > /dev/null 2>&1; then
  echo "Error: Router is not accessible at ${ROUTER_URL}"
  echo "  Make sure the deployment is running: ${SCRIPT_DIR}/start-master-2paged.sh"
  exit 1
fi

# Verify both instances are running
if ! curl -s -f --connect-timeout 3 "http://${REGISTRY_IP}:8101/health" > /dev/null 2>&1; then
  echo "Warning: paged-cache-9g_8b_thinking (8101) is not responding"
fi
if ! curl -s -f --connect-timeout 3 "http://${REGISTRY_IP}:8301/health" > /dev/null 2>&1; then
  echo "Warning: paged-cache-9g_8b_thinking-2 (8301) is not responding"
fi

# Test endpoint connectivity before running benchmark
echo "Testing endpoint connectivity..."
TEST_RESPONSE="$(curl -s -X POST "${ROUTER_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "{\"model\": \"${MODEL}\", \"messages\": [{\"role\": \"user\", \"content\": \"test\"}], \"max_tokens\": 5}" \
  2>&1)"
if echo "${TEST_RESPONSE}" | grep -q '"object"'; then
  echo "✓ Endpoint is accessible and responding"
else
  echo "⚠️  Warning: Endpoint test failed. Response: ${TEST_RESPONSE:0:200}"
  echo "Continuing anyway..."
fi
echo ""

# Disable ready check timeout - set to 0 to skip ready check (we already tested above)
READY_CHECK_TIMEOUT="${READY_CHECK_TIMEOUT:-0}"

echo "Running benchmark..."
cd "${VLLM_DIR}"

# Set PYTHONPATH to include vLLM directory so we can import the module directly
export PYTHONPATH="${VLLM_DIR}:${PYTHONPATH:-}"

# Suppress warnings about missing compiled extensions (expected when not building vLLM)
export PYTHONWARNINGS="ignore::UserWarning"

# Force offline mode to use local tokenizer only (no network access)
export HF_HUB_OFFLINE=1

# Run vLLM bench using run_benchmark.py wrapper script
# Use -u for unbuffered output to see progress in real-time
echo "Executing benchmark (full output logged to: ${SCRIPT_DIR}/bench-2paged.log)..."
echo ""

# Run benchmark with output to both log file and stdout
# Use a temporary file to ensure all output is captured
TEMP_LOG="${SCRIPT_DIR}/bench-2paged.tmp.log"

# Convert dataset path to absolute if relative
if [[ "${DATASET_FILE}" != /* ]]; then
  DATASET_FILE="${SCRIPT_DIR}/${DATASET_FILE}"
fi

python -u -W ignore::UserWarning "${SCRIPT_DIR}/run_benchmark.py" "${VLLM_DIR}" \
  --backend openai \
  --host "${REGISTRY_IP}" \
  --port "${ROUTER_PORT}" \
  --endpoint /v1/chat/completions \
  --model "${MODEL}" \
  ${TOKENIZER_ARG} \
  --dataset-name custom \
  --dataset-path "${DATASET_FILE}" \
  --request-rate "${REQUEST_RATE}" \
  --num-prompts "${NUM_REQUESTS}" \
  --max-concurrency "${MAX_CONCURRENCY}" \
  --label "2paged-round-robin" \
  --save-result \
  --result-dir "${SCRIPT_DIR}/results" \
  --ready-check-timeout-sec "${READY_CHECK_TIMEOUT}" \
  2>&1 | tee "${TEMP_LOG}"
BENCHMARK_EXIT_CODE=${PIPESTATUS[0]}

# Move temp log to final location
mv "${TEMP_LOG}" "${SCRIPT_DIR}/bench-2paged.log" 2>/dev/null || true

if [ ${BENCHMARK_EXIT_CODE} -eq 0 ]; then
  echo ""
  echo "✅ Benchmark command completed!"
  # Wait a moment for file to be written
  sleep 2
  if [ -d "${SCRIPT_DIR}/results" ] && [ "$(ls -A ${SCRIPT_DIR}/results 2>/dev/null)" ]; then
    # Find result files matching our label from the last 5 minutes
    RESULT_FILES=$(find "${SCRIPT_DIR}/results" -name "2paged-round-robin-*.json" -type f -mmin -5 2>/dev/null | sort -r)
    if [ -n "${RESULT_FILES}" ]; then
      LATEST_RESULT=$(echo "${RESULT_FILES}" | head -1)
      echo "Results saved to: ${SCRIPT_DIR}/results/"
      echo "Latest result file: $(basename ${LATEST_RESULT})"
      ls -lh "${LATEST_RESULT}"
    else
      # Fallback: show most recent file
      LATEST_RESULT="$(ls -t ${SCRIPT_DIR}/results/*.json 2>/dev/null | head -1)"
      if [ -n "${LATEST_RESULT}" ]; then
        echo "⚠️  Warning: Could not find result file from this run"
        echo "Most recent result file: $(basename ${LATEST_RESULT})"
        ls -lh "${LATEST_RESULT}"
      else
        echo "⚠️  Warning: No results files found in ${SCRIPT_DIR}/results/"
        echo "Check the log file for details: ${SCRIPT_DIR}/bench-2paged.log"
        echo ""
        echo "Last 50 lines of log:"
        tail -50 "${SCRIPT_DIR}/bench-2paged.log" 2>/dev/null || echo "  (log file not found)"
      fi
    fi
  else
    echo "⚠️  Warning: No results files found in ${SCRIPT_DIR}/results/"
    echo "Check the log file for details: ${SCRIPT_DIR}/bench-2paged.log"
    echo ""
    echo "Last 50 lines of log:"
    tail -50 "${SCRIPT_DIR}/bench-2paged.log" 2>/dev/null || echo "  (log file not found)"
  fi
  echo ""
  echo "📊 2 Paged Cache Validation (Round-Robin Routing):"
  echo "  - Tests round-robin routing with 2 paged cache instances"
  echo "  - Requests distributed evenly across instances (8100, 8300)"
  echo "  - No size-based routing - all requests use paged cache"
  echo "  - Same dataset as size-based routing for fair comparison"
  echo ""
  echo "  To compare with size-based routing, run:"
  echo "    python ${SCRIPT_DIR}/compare-routing-strategies.py \\"
  echo "      --size-based results/size-based-routing-*.json \\"
  echo "      --2paged results/2paged-round-robin-*.json"
else
  EXIT_CODE=$?
  echo ""
  echo "❌ Benchmark failed with exit code ${EXIT_CODE}"
  echo "Check the log file for details: ${SCRIPT_DIR}/bench-2paged.log"
  echo ""
  echo "Last 30 lines of log:"
  tail -30 "${SCRIPT_DIR}/bench-2paged.log" 2>/dev/null || echo "  (log file not found)"
  exit 1
fi
