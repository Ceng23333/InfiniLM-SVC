#!/usr/bin/env bash
# Benchmark script for cache routing configuration
# Both instances running, with prompt_cache_key (session-aware routing)

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

# Accumulating context configuration (default for cache routing - chatbot scenario)
NUM_CONVERSATIONS="${NUM_CONVERSATIONS:-4}"      # Number of different conversations
MESSAGES_PER_CONV="${MESSAGES_PER_CONV:-8}"      # Messages per conversation
CONTEXT_LEN="${CONTEXT_LEN:-2048}"                # Context length per message
NEW_MSG_LEN="${NEW_MSG_LEN:-128}"                 # New message length
DATASET_FILE="${DATASET_FILE:-${SCRIPT_DIR}/accumulate_context.jsonl}"
NUM_REQUESTS=$((NUM_CONVERSATIONS * MESSAGES_PER_CONV))

# Tokenizer path - MODEL1_DIR is required
TOKENIZER_DIR="${TOKENIZER_DIR:-${MODEL1_DIR:-}}"
if [ -z "${TOKENIZER_DIR}" ] || [ ! -d "${TOKENIZER_DIR}" ]; then
  echo "❌ Error: TOKENIZER_DIR or MODEL1_DIR must be set and point to a valid model directory"
  echo ""
  echo "  The benchmark requires a local tokenizer and cannot download from HuggingFace (offline mode)."
  echo "  Please set MODEL1_DIR to point to your model directory:"
  echo ""
  echo "    export MODEL1_DIR=/path/to/9g_8b_thinking_llama"
  echo "    ./bench-cache-routing.sh 172.22.162.18"
  echo ""
  echo "  Or set TOKENIZER_DIR directly:"
  echo "    export TOKENIZER_DIR=/path/to/model/directory"
  echo ""
  exit 1
fi

TOKENIZER_ARG="--tokenizer ${TOKENIZER_DIR}"
echo "Using tokenizer from: ${TOKENIZER_DIR}"

# Cache routing configuration
# prompt_cache_key is now explicitly included in the JSON dataset
# No need to use --prompt-cache-key CLI argument - it will be read from JSON
# The dataset generator creates prompt_cache_key field in each record

echo "=========================================="
echo "Cache Routing Benchmark"
echo "=========================================="
echo "Router URL: ${ROUTER_URL}"
echo "Model: ${MODEL}"
echo "Request Rate: ${REQUEST_RATE} req/s"
echo "Number of Conversations: ${NUM_CONVERSATIONS}"
echo "Messages per Conversation: ${MESSAGES_PER_CONV}"
echo "Total Requests: ${NUM_REQUESTS}"
echo "Context Length per Message: ${CONTEXT_LEN} chars"
echo "New Message Length: ${NEW_MSG_LEN} chars"
echo "Cache Key Source: From JSON dataset (prompt_cache_key field)"
echo ""
echo "Configuration: Both instances running (master:8100, slave:8200)"
echo "Routing: Cache-aware (with prompt_cache_key)"
echo "Dataset: Accumulating context (chatbot scenario)"
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

# Generate accumulating context dataset if it doesn't exist
if [ ! -f "${DATASET_FILE}" ]; then
  echo "Generating accumulating context dataset..."
  python "${SCRIPT_DIR}/gen-accumulate-context.py" \
    --output "${DATASET_FILE}" \
    --num-conversations "${NUM_CONVERSATIONS}" \
    --messages-per-conv "${MESSAGES_PER_CONV}" \
    --context-len "${CONTEXT_LEN}" \
    --new-msg-len "${NEW_MSG_LEN}"
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
  echo "  Make sure the deployment is running: ${SCRIPT_DIR}/start-master.sh"
  exit 1
fi

# Verify both instances are running
if ! curl -s -f --connect-timeout 3 "http://${REGISTRY_IP}:8101/health" > /dev/null 2>&1; then
  echo "Warning: master-9g_8b_thinking (8101) is not responding"
fi
if ! curl -s -f --connect-timeout 3 "http://${REGISTRY_IP}:8201/health" > /dev/null 2>&1; then
  echo "Warning: slave-9g_8b_thinking (8201) is not responding"
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

# Run vLLM bench with prompt_cache_key (cache-aware routing)
# Use -u for unbuffered output to see progress in real-time
echo "Executing benchmark (full output logged to: ${SCRIPT_DIR}/bench-cache-routing.log)..."
echo ""

# Run benchmark with output to both log file and stdout
# Use a temporary file to ensure all output is captured
TEMP_LOG="${SCRIPT_DIR}/bench-cache-routing.tmp.log"

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
  --label "cache-routing" \
  --save-result \
  --result-dir "${SCRIPT_DIR}/results" \
  --ready-check-timeout-sec "${READY_CHECK_TIMEOUT}" \
  2>&1 | tee "${TEMP_LOG}"
BENCHMARK_EXIT_CODE=${PIPESTATUS[0]}

# Move temp log to final location
mv "${TEMP_LOG}" "${SCRIPT_DIR}/bench-cache-routing.log" 2>/dev/null || true

if [ ${BENCHMARK_EXIT_CODE} -eq 0 ]; then
  echo ""
  echo "✅ Benchmark command completed!"
  # Wait a moment for file to be written
  sleep 2
  if [ -d "${SCRIPT_DIR}/results" ] && [ "$(ls -A ${SCRIPT_DIR}/results 2>/dev/null)" ]; then
    # Find result files matching our label from the last 5 minutes
    RESULT_FILES=$(find "${SCRIPT_DIR}/results" -name "cache-routing-*.json" -type f -mmin -5 2>/dev/null | sort -r)
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
        echo "Check the log file for details: ${SCRIPT_DIR}/bench-cache-routing.log"
        echo ""
        echo "Last 50 lines of log:"
        tail -50 "${SCRIPT_DIR}/bench-cache-routing.log" 2>/dev/null || echo "  (log file not found)"
      fi
    fi
  else
    echo "⚠️  Warning: No results files found in ${SCRIPT_DIR}/results/"
    echo "Check the log file for details: ${SCRIPT_DIR}/bench-cache-routing.log"
    echo ""
    echo "Last 50 lines of log:"
    tail -50 "${SCRIPT_DIR}/bench-cache-routing.log" 2>/dev/null || echo "  (log file not found)"
  fi
  echo ""
  echo "📊 Cache Routing Validation (Accumulating Context):"
  echo "  - Simulates chatbot scenario with accumulating conversation history"
  echo "  - Each request contains full conversation history (shared prefix grows)"
  echo "  - Requests from same conversation route to same instance (cache key: conv_{id})"
  echo "  - Later messages in conversation should show significant TTFT improvement"
  echo ""
  echo "  To compare with round-robin results, run:"
  echo "    python ${SCRIPT_DIR}/compare-results.py \\"
  echo "      ${SCRIPT_DIR}/results/round-robin-*.json \\"
  echo "      ${SCRIPT_DIR}/results/cache-routing-*.json"
else
  EXIT_CODE=$?
  echo ""
  echo "❌ Benchmark failed with exit code ${EXIT_CODE}"
  echo "Check the log file for details: ${SCRIPT_DIR}/bench-cache-routing.log"
  echo ""
  echo "Last 30 lines of log:"
  tail -30 "${SCRIPT_DIR}/bench-cache-routing.log" 2>/dev/null || echo "  (log file not found)"
  exit 1
fi
