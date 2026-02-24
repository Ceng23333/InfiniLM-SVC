#!/usr/bin/env bash
# Reproduce benchmark results from RESULTS_SUMMARY.md
# Uses Docker image: infinilm-svc:runtime-cache-type-routing-validation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# Configuration from RESULTS_SUMMARY.md
REGISTRY_IP="${1:-localhost}"
# Use the specified Docker image
IMAGE_NAME="${IMAGE_NAME:-infinilm-svc:runtime-cache-type-routing-validation}"
MODEL="${MODEL:-Qwen3-32B}"
REQUEST_RATE="${REQUEST_RATE:-1.0}"
MAX_CONCURRENCY="${MAX_CONCURRENCY:-4}"
NUM_CONVERSATIONS="${NUM_CONVERSATIONS:-4}"
MESSAGES_PER_CONV="${MESSAGES_PER_CONV:-4}"
NUM_REQUESTS=$((NUM_CONVERSATIONS * MESSAGES_PER_CONV))
ROUTING_THRESHOLD="${CACHE_TYPE_ROUTING_THRESHOLD:-10000}"  # 10KB as per RESULTS_SUMMARY.md

# Required environment variables
QWEN3_32B_DIR="${QWEN3_32B_DIR:-}"
VLLM_DIR="${VLLM_DIR:-/home/zenghua/repos/vllm}"
TOKENIZER_DIR="${TOKENIZER_DIR:-${QWEN3_32B_DIR}}"

# Check prerequisites
if [ -z "${QWEN3_32B_DIR}" ] || [ ! -d "${QWEN3_32B_DIR}" ]; then
  echo "❌ Error: QWEN3_32B_DIR must point to the Qwen3-32B model directory"
  echo "  Example: export QWEN3_32B_DIR=/path/to/Qwen3-32B"
  exit 1
fi

if [ ! -d "${VLLM_DIR}" ]; then
  echo "❌ Error: VLLM_DIR does not exist: ${VLLM_DIR}"
  echo "  Set VLLM_DIR to point to your vLLM repository"
  exit 1
fi

# Check Docker image
if ! docker images "${IMAGE_NAME}" 2>/dev/null | tail -n +2 | grep -q .; then
  echo "❌ Error: Docker image ${IMAGE_NAME} not found"
  echo "  Available images:"
  docker images | grep infinilm-svc | head -5
  exit 1
fi

echo "=========================================="
echo "Reproducing Cache Type Routing Benchmarks"
echo "=========================================="
echo "Docker Image: ${IMAGE_NAME}"
echo "Model: ${MODEL}"
echo "QWEN3_32B_DIR: ${QWEN3_32B_DIR}"
echo "VLLM_DIR: ${VLLM_DIR}"
echo "Routing Threshold: ${ROUTING_THRESHOLD} bytes (10KB)"
echo ""

# Test configurations from RESULTS_SUMMARY.md
# Test 2: 16KB context
# Test 3: 65KB context

# Container names used by start scripts
SIZE_BASED_CONTAINER="${SIZE_BASED_CONTAINER:-infinilm-svc-master-qwen3-32b}"
PAGED_2_CONTAINER="${PAGED_2_CONTAINER:-infinilm-svc-master-2paged-qwen3-32b}"

# Function to stop existing containers
stop_containers() {
  echo "Stopping existing containers..."
  docker rm -f "${SIZE_BASED_CONTAINER}" "${PAGED_2_CONTAINER}" 2>/dev/null || true
  sleep 2
}

# Show container status and recent logs (for debugging "waiting for ready")
show_container_status() {
  local name="${1:-${SIZE_BASED_CONTAINER}}"
  echo "  --- Container: ${name} ---"
  docker ps -a --filter "name=${name}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${name}$"; then
    echo "  Last 20 log lines:"
    docker logs "${name}" --tail 20 2>&1 | sed 's/^/    /'
  else
    echo "  (container not found)"
  fi
  echo ""
}

# Function to check if model is ready
check_model_ready() {
  local router_url="http://${REGISTRY_IP}:8000"
  local registry_url="http://${REGISTRY_IP}:18000"

  # Check router health first
  if ! curl -s -f --connect-timeout 3 "${router_url}/health" > /dev/null 2>&1; then
    return 1
  fi

  # Try a test request - if it succeeds (even with error), model is registered
  local response=$(curl -s -X POST "${router_url}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"${MODEL}\", \"messages\": [{\"role\": \"user\", \"content\": \"test\"}], \"max_tokens\": 1}" \
    2>&1)

  # Check if we get "No healthy services" error
  if echo "${response}" | grep -q "No healthy services"; then
    return 1
  fi

  # If we get any other response (including actual errors from the model), it means instances are registered
  # A successful response or a model-specific error means instances are ready
  return 0
}

# Function to wait for services to be ready
# Set MAX_READY_WAIT to override default (seconds); e.g. export MAX_READY_WAIT=300
wait_for_services() {
  local max_wait="${MAX_READY_WAIT:-600}"  # 10 minutes default; override for faster fail
  local waited=0
  local registry_url="http://${REGISTRY_IP}:18000"
  local router_url="http://${REGISTRY_IP}:8000"

  echo "Waiting for services to be ready (max ${max_wait}s, override with MAX_READY_WAIT)..."

  # Wait for router
  while [ ${waited} -lt ${max_wait} ]; do
    if curl -s -f --connect-timeout 3 "${router_url}/health" > /dev/null 2>&1; then
      echo "✓ Router is ready"
      break
    fi
    sleep 5
    waited=$((waited + 5))
    echo "  Waiting for router... (${waited}s/${max_wait}s)"
  done

  # Wait for model to be available (instances registered and healthy)
  echo "Waiting for model '${MODEL}' to be available..."
  local model_ready=false
  local check_interval=10
  local status_interval=30

  while [ ${waited} -lt ${max_wait} ]; do
    if check_model_ready; then
      echo "✓ Model '${MODEL}' is available and ready"
      model_ready=true
      break
    fi

    # Check registry for model registration
    local registry_models=$(curl -s "${registry_url}/v1/models" 2>/dev/null || echo "")
    if echo "${registry_models}" | grep -q "\"id\":\"${MODEL}\""; then
      echo "  Model '${MODEL}' found in registry, waiting for health checks..."
    fi

    sleep ${check_interval}
    waited=$((waited + check_interval))

    if [ $((waited % status_interval)) -eq 0 ]; then
      echo "  Waiting for model '${MODEL}'... (${waited}s/${max_wait}s)"
      # Show instance status from registry
      if [ -n "${registry_models}" ]; then
        echo "    Registered models:"
        echo "${registry_models}" | grep -o "\"id\":\"[^\"]*\"" | head -5 | sed 's/^/      /' || true
      fi
      # Show container status and recent logs so user can see why ready is slow
      for c in "${SIZE_BASED_CONTAINER}" "${PAGED_2_CONTAINER}"; do
        if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${c}$"; then
          show_container_status "${c}"
          break
        fi
      done
    fi
  done

  if [ "${model_ready}" != "true" ]; then
    echo ""
    echo "⚠️  Warning: Model '${MODEL}' may not be fully ready after ${waited}s"
    echo "  Registry status:"
    curl -s "${registry_url}/v1/models" 2>/dev/null | python -m json.tool 2>/dev/null | head -30 || \
      curl -s "${registry_url}/v1/models" 2>/dev/null | head -20 || \
      echo "  (Could not query registry)"
    echo ""
    echo "  Router status:"
    curl -s "${router_url}/health" 2>/dev/null || echo "  (Could not query router)"
    echo ""
    echo "  Container status (check logs if model loading is slow or failing):"
    show_container_status "${SIZE_BASED_CONTAINER}"
    show_container_status "${PAGED_2_CONTAINER}"
    echo "  Continuing anyway - benchmarks may fail if instances aren't ready"
    return 1
  fi

  return 0
}

# Function to run size-based routing benchmark
run_size_based_benchmark() {
  local context_size=$1
  local dataset_file=$2

  echo ""
  echo "=========================================="
  echo "Size-Based Routing Benchmark - ${context_size}"
  echo "=========================================="

  # Stop existing container
  stop_containers

  # Start size-based routing deployment
  echo "Starting size-based routing deployment..."
  echo "  Using Docker image: ${IMAGE_NAME}"
  export IMAGE_NAME="${IMAGE_NAME}"
  export QWEN3_32B_DIR="${QWEN3_32B_DIR}"
  export CACHE_TYPE_ROUTING_THRESHOLD="${ROUTING_THRESHOLD}"
  ./start-master-qwen3-32b.sh "${REGISTRY_IP}"

  # Wait for services
  wait_for_services

  # Run benchmark
  echo ""
  echo "Running benchmark with dataset: ${dataset_file}"
  export MODEL="${MODEL}"
  export REQUEST_RATE="${REQUEST_RATE}"
  export MAX_CONCURRENCY="${MAX_CONCURRENCY}"
  export NUM_CONVERSATIONS="${NUM_CONVERSATIONS}"
  export MESSAGES_PER_CONV="${MESSAGES_PER_CONV}"
  export NUM_LARGE_CONTEXT=1
  export DATASET_FILE="${dataset_file}"
  export TOKENIZER_DIR="${TOKENIZER_DIR}"
  export VLLM_DIR="${VLLM_DIR}"

  ./bench-size-based-routing.sh "${REGISTRY_IP}" || {
    echo "❌ Benchmark failed, check logs"
    return 1
  }

  echo "✅ Size-based routing benchmark completed for ${context_size}"
}

# Function to run 2-paged round-robin benchmark
run_2paged_benchmark() {
  local context_size=$1
  local dataset_file=$2

  echo ""
  echo "=========================================="
  echo "2-Paged Round-Robin Benchmark - ${context_size}"
  echo "=========================================="

  # Stop existing container
  stop_containers

  # Start 2-paged deployment
  echo "Starting 2-paged round-robin deployment..."
  echo "  Using Docker image: ${IMAGE_NAME}"
  export IMAGE_NAME="${IMAGE_NAME}"
  export QWEN3_32B_DIR="${QWEN3_32B_DIR}"
  ./start-master-2paged-qwen3-32b.sh "${REGISTRY_IP}"

  # Wait for services and verify model is ready
  if ! wait_for_services; then
    echo "❌ Model readiness check failed. Aborting benchmark."
    return 1
  fi

  # Double-check model is ready before running benchmark
  echo ""
  echo "Verifying model '${MODEL}' is ready before benchmark..."
  if ! check_model_ready; then
    echo "❌ Model '${MODEL}' is not ready. Aborting benchmark."
    echo "  Check container logs: docker logs ${PAGED_2_CONTAINER}"
    return 1
  fi
  echo "✓ Model '${MODEL}' verified ready"

  # Run benchmark
  echo ""
  echo "Running benchmark with dataset: ${dataset_file}"
  export MODEL="${MODEL}"
  export REQUEST_RATE="${REQUEST_RATE}"
  export MAX_CONCURRENCY="${MAX_CONCURRENCY}"
  export NUM_CONVERSATIONS="${NUM_CONVERSATIONS}"
  export MESSAGES_PER_CONV="${MESSAGES_PER_CONV}"
  export NUM_LARGE_CONTEXT=1
  export DATASET_FILE="${dataset_file}"
  export TOKENIZER_DIR="${TOKENIZER_DIR}"
  export VLLM_DIR="${VLLM_DIR}"

  ./bench-2paged.sh "${REGISTRY_IP}" || {
    echo "❌ Benchmark failed, check logs"
    return 1
  }

  echo "✅ 2-paged round-robin benchmark completed for ${context_size}"
}

# Main execution
echo "Starting benchmark reproduction..."
echo ""

# Test 2: 16KB context
DATASET_16KB="${SCRIPT_DIR}/large_context_16000.jsonl"
if [ ! -f "${DATASET_16KB}" ]; then
  echo "⚠️  Warning: Dataset ${DATASET_16KB} not found, generating..."
  python gen-large-context.py \
    --output "${DATASET_16KB}" \
    --num-conversations "${NUM_CONVERSATIONS}" \
    --messages-per-conv "${MESSAGES_PER_CONV}" \
    --context-len 512 \
    --new-msg-len 64 \
    --num-large-context 1 \
    --large-context-len 16000
fi

# Test 3: 65KB context
DATASET_65KB="${SCRIPT_DIR}/large_context_65536.jsonl"
if [ ! -f "${DATASET_65KB}" ]; then
  echo "⚠️  Warning: Dataset ${DATASET_65KB} not found, generating..."
  python gen-large-context.py \
    --output "${DATASET_65KB}" \
    --num-conversations "${NUM_CONVERSATIONS}" \
    --messages-per-conv "${MESSAGES_PER_CONV}" \
    --context-len 512 \
    --new-msg-len 64 \
    --num-large-context 1 \
    --large-context-len 65536
fi

# Run benchmarks
echo ""
echo "Running Test 2: 16KB context"
run_size_based_benchmark "16KB" "${DATASET_16KB}"
run_2paged_benchmark "16KB" "${DATASET_16KB}"

echo ""
echo "Running Test 3: 65KB context"
run_size_based_benchmark "65KB" "${DATASET_65KB}"
run_2paged_benchmark "65KB" "${DATASET_65KB}"

# Compare results
echo ""
echo "=========================================="
echo "Comparing Results"
echo "=========================================="
echo ""
echo "For 16KB context:"
python compare-routing-strategies.py --auto-detect || echo "Comparison failed, check results manually"

echo ""
echo "=========================================="
echo "Benchmark Reproduction Complete"
echo "=========================================="
echo ""
echo "Results are saved in: ${SCRIPT_DIR}/results/"
echo ""
echo "To compare results manually:"
echo "  python compare-routing-strategies.py --auto-detect"
echo ""
echo "To view specific comparisons:"
echo "  python compare-routing-strategies.py \\"
echo "    --size-based results/size-based-routing-*.json \\"
echo "    --2paged results/2paged-round-robin-*.json"
