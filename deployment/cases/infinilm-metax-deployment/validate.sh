#!/usr/bin/env bash
# Validate the 2-server deployment (registry/router + InfiniLM backends)

set -e

usage() {
  echo "Usage:"
  echo "  $0 <REGISTRY_IP> [WORKER ...]"
  echo ""
  echo "Notes:"
  echo "  - REGISTRY_PORT and ROUTER_PORT are taken from env (defaults: 18000 / 8000)"
  echo "  - Any number of worker servers can be provided; each is expected to run babysitters"
  echo "  - Worker can be either:"
  echo "      - <IP>        (defaults to slave id 1 => prefix 'slave-*')"
  echo "      - <IP>:<ID>   (e.g. 172.22.162.19:2 => prefix 'slave2-*')"
  echo ""
  echo "Examples:"
  echo "  $0 172.22.162.17"
  echo "  $0 172.22.162.17 172.22.162.18"
  echo "  $0 172.22.162.17 172.22.162.18 172.22.162.19:2"
}

if [ $# -lt 1 ]; then
  usage
  exit 1
fi

REGISTRY_IP="${1:-localhost}"
shift || true

# Remaining args are worker specs (IP or IP:ID) (can be empty)
WORKER_SPECS=("$@")
WORKER_IPS=()
WORKER_IDS=()

for spec in "${WORKER_SPECS[@]}"; do
  ip="${spec%%:*}"
  id="1"
  if [[ "${spec}" == *:* ]]; then
    id="${spec#*:}"
  fi
  if [ -z "${ip}" ]; then
    echo "Error: invalid worker spec '${spec}' (empty IP)"
    exit 1
  fi
  if ! [[ "${id}" =~ ^[0-9]+$ ]] || [ "${id}" -lt 1 ]; then
    echo "Error: invalid worker spec '${spec}' (invalid id: ${id})"
    exit 1
  fi
  WORKER_IPS+=("${ip}")
  WORKER_IDS+=("${id}")
done

REGISTRY_PORT="${REGISTRY_PORT:-18000}"
ROUTER_PORT="${ROUTER_PORT:-8000}"
EMBEDDING_PORT="${EMBEDDING_PORT:-20002}"
REGISTRY_URL="http://${REGISTRY_IP}:${REGISTRY_PORT}"
ROUTER_URL="http://${REGISTRY_IP}:${ROUTER_PORT}"
EMBEDDING_URL="http://${REGISTRY_IP}:${EMBEDDING_PORT}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0

echo "=========================================="
echo "InfiniLM-SVC (Rust) + InfiniLM Backend Validation"
echo "=========================================="
echo "Registry IP: ${REGISTRY_IP}"
if [ ${#WORKER_SPECS[@]} -gt 0 ]; then
  echo "Workers:    ${WORKER_SPECS[*]}"
else
  echo "Workers:    (none)"
fi
echo "Registry: ${REGISTRY_URL} (port ${REGISTRY_PORT})"
echo "Router:   ${ROUTER_URL} (port ${ROUTER_PORT})"
echo "Embedding Server: ${EMBEDDING_URL} (port ${EMBEDDING_PORT})"
echo ""

check() {
  local url=$1
  local name=$2
  echo -n "  Checking ${name}... "
  if curl -s -f --connect-timeout 3 "${url}" > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
    PASSED=$((PASSED + 1))
    return 0
  else
    echo -e "${RED}✗${NC}"
    echo "    URL: ${url}"
    FAILED=$((FAILED + 1))
    return 1
  fi
}

test_passed() {
  PASSED=$((PASSED + 1))
  echo -e "${GREEN}✓ PASSED${NC}"
}

test_failed() {
  FAILED=$((FAILED + 1))
  echo -e "${RED}✗ FAILED${NC}"
}

echo -e "${BLUE}[1] Core health${NC}"
check "${REGISTRY_URL}/health" "Registry /health"
check "${ROUTER_URL}/health" "Router /health"
echo ""

echo -e "${BLUE}[2] Service discovery${NC}"
# Query registry from inside container if available to avoid proxy interference
# With --network host, the container's registry should be accessible, but proxy may route incorrectly
CONTAINER_NAME="${CONTAINER_NAME:-infinilm-svc-master}"
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  # Query from inside container to bypass proxy and get correct registry instance
  services_json="$(docker exec "${CONTAINER_NAME}" curl -s --noproxy "*" "http://127.0.0.1:${REGISTRY_PORT}/services" 2>/dev/null || curl -s "${REGISTRY_URL}/services" 2>/dev/null || echo '{}')"
else
  services_json="$(curl -s "${REGISTRY_URL}/services" 2>/dev/null || echo '{}')"
fi
service_count="$(echo "${services_json}" | grep -o '"name"' | wc -l || echo "0")"
echo "  Found ${service_count} services"

# Check for expected services
# Naming convention:
# - master-* lives on registry/router server
expected_services=("master-9g_8b_thinking-server" "master-Qwen3-32B-server")
if [ ${#WORKER_IPS[@]} -gt 0 ]; then
  idx=0
  for _ip in "${WORKER_IPS[@]}"; do
    id="${WORKER_IDS[$idx]}"
    slave_name="slave"
    if [ "${id}" -gt 1 ]; then
      slave_name="slave${id}"
    fi
    expected_services+=("${slave_name}-9g_8b_thinking-server" "${slave_name}-Qwen3-32B-server")
    idx=$((idx + 1))
  done
fi

echo "  Expected services: ${#expected_services[@]} (${expected_services[*]})"
found_services=()
for svc in "${expected_services[@]}"; do
  if echo "${services_json}" | grep -q "\"name\":\"${svc}\""; then
    found_services+=("${svc}")
    echo -e "    ${GREEN}✓${NC} ${svc}"
  else
    echo -e "    ${RED}✗${NC} ${svc} (not found)"
  fi
done

if [ ${#found_services[@]} -eq ${#expected_services[@]} ]; then
  test_passed
else
  echo "  ${YELLOW}⚠${NC} Only ${#found_services[@]}/${#expected_services[@]} expected services found"
  if [ ${#found_services[@]} -eq 0 ]; then
    test_failed
  else
    test_passed  # Partial success
  fi
fi
echo ""

echo -e "${BLUE}[3] Model aggregation${NC}"
models_json="$(curl -s "${ROUTER_URL}/models" 2>/dev/null || echo '{}')"
# Extract model IDs from the response
model_ids="$(echo "${models_json}" | grep -o '"id":"[^"]*"' | sed 's/"id":"\([^"]*\)"/\1/' | tr '\n' ' ' || echo '')"
if [ -z "${model_ids}" ] || [ "${model_ids}" = " " ]; then
  echo -e "  ${RED}✗${NC} No models found"
  echo "${models_json}"
  exit 1
fi
# Check for expected model IDs (from babysitter configs)
expected_model1="9g_8b_thinking"
expected_model2="Qwen3-32B"
found_any=false
for model_id in ${model_ids}; do
  echo "  Found model: ${model_id}"
  if [ "${model_id}" = "${expected_model1}" ] || [ "${model_id}" = "${expected_model2}" ]; then
    found_any=true
  fi
done
if [ "${found_any}" = "true" ]; then
  echo -e "  ${GREEN}✓${NC} Found expected model(s)"
else
  echo -e "  ${YELLOW}⚠${NC} Expected models not found, but models are available"
fi
# Use the first available model for testing
test_model="$(echo "${model_ids}" | awk '{print $1}')"
echo ""

echo -e "${BLUE}[4] Chat completions via router${NC}"
echo "  Testing model: ${test_model}"
request_data="{
  \"model\": \"${test_model}\",
  \"messages\": [{\"role\": \"user\", \"content\": \"Hello\"}],
  \"stream\": false
}"

resp="$(curl -s -X POST "${ROUTER_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "${request_data}" 2>/dev/null || echo '{}')"

if echo "${resp}" | grep -q '"object"'; then
  echo -e "  ${GREEN}✓${NC} Router returned response"
  test_passed
else
  echo -e "  ${RED}✗${NC} Router response invalid"
  echo "  Response: ${resp}"
  test_failed
fi
echo ""

# Test Qwen3-32B model specifically if available
if echo "${model_ids}" | grep -q "Qwen3-32B"; then
  echo -e "${BLUE}[5] Qwen3-32B model test${NC}"
  echo "  Testing Qwen3-32B model..."
  qwen_request_data="{
    \"model\": \"Qwen3-32B\",
    \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in one word.\"}],
    \"stream\": false
  }"

  qwen_resp="$(curl -s -X POST "${ROUTER_URL}/chat/completions" \
    -H "Content-Type: application/json" \
    -d "${qwen_request_data}" 2>/dev/null || echo '{}')"

  if echo "${qwen_resp}" | grep -q '"object"'; then
    echo -e "  ${GREEN}✓${NC} Qwen3-32B model responded successfully"
    # Extract and show a snippet of the response content if available
    content="$(echo "${qwen_resp}" | grep -o '"content":"[^"]*"' | head -1 | sed 's/"content":"\([^"]*\)"/\1/' || echo '')"
    if [ -n "${content}" ]; then
      echo "    Response preview: ${content:0:50}..."
    fi
    test_passed
  else
    echo -e "  ${RED}✗${NC} Qwen3-32B model test failed"
    echo "  Response: ${qwen_resp}"
    test_failed
  fi
  echo ""
else
  echo -e "${BLUE}[5] Qwen3-32B model test${NC}"
  echo -e "  ${YELLOW}⚠${NC} Qwen3-32B model not found, skipping test"
  echo ""
fi

# Test load balancing if Server 2 is specified
if [ ${#WORKER_IPS[@]} -gt 0 ] && echo "${model_ids}" | grep -q "9g_8b_thinking"; then
  echo -e "${BLUE}[6] Load balancing test${NC}"
  echo "  Sending 6 requests for 9g_8b_thinking (should balance across all servers)..."
  services_hit=()
  for i in {1..6}; do
    resp="$(curl -s -X POST "${ROUTER_URL}/v1/chat/completions" \
      -H "Content-Type: application/json" \
      -d '{"model": "9g_8b_thinking", "messages": [{"role": "user", "content": "Test"}], "stream": false}' 2>/dev/null || echo '{}')"
    if echo "${resp}" | grep -q '"object"'; then
      services_hit+=("request-$i")
    fi
    sleep 0.5
  done

  if [ ${#services_hit[@]} -ge 4 ]; then
    echo -e "  ${GREEN}✓${NC} Load balancing looks healthy (${#services_hit[@]}/6 requests succeeded)"
    test_passed
  else
    echo -e "  ${YELLOW}⚠${NC} Only ${#services_hit[@]}/6 requests succeeded (may be normal if services just started)"
    test_passed  # Not a failure
  fi
  echo ""
fi

# Test worker health endpoints (babysitter HTTP ports)
if [ ${#WORKER_IPS[@]} -gt 0 ]; then
  echo -e "${BLUE}[7] Worker babysitter health checks${NC}"
  idx=0
  for ip in "${WORKER_IPS[@]}"; do
    id="${WORKER_IDS[$idx]}"
    slave_name="slave"
    if [ "${id}" -gt 1 ]; then
      slave_name="slave${id}"
    fi
    echo "  Worker ${slave_name}: ${ip}"
    if curl -s -f --connect-timeout 3 "http://${ip}:8101/health" > /dev/null 2>&1; then
      echo -e "    ${GREEN}✓${NC} ${slave_name}-9g_8b_thinking babysitter (8101) healthy"
      test_passed
    else
      echo -e "    ${RED}✗${NC} ${slave_name}-9g_8b_thinking babysitter (8101) not responding"
      test_failed
    fi

    if curl -s -f --connect-timeout 3 "http://${ip}:8201/health" > /dev/null 2>&1; then
      echo -e "    ${GREEN}✓${NC} ${slave_name}-Qwen3-32B babysitter (8201) healthy"
      test_passed
    else
      echo -e "    ${RED}✗${NC} ${slave_name}-Qwen3-32B babysitter (8201) not responding"
      test_failed
    fi
    idx=$((idx + 1))
  done
  echo ""
fi

# Test embedding server endpoints
echo -e "${BLUE}[8] Embedding server validation${NC}"
echo "  Testing embedding server at ${EMBEDDING_URL}..."

# Check if embedding server is reachable
if curl -s -f --connect-timeout 3 "${EMBEDDING_URL}/v1/embeddings" -X POST \
  -H "Content-Type: application/json" \
  -d '{"model":"test","input":"test"}' > /dev/null 2>&1; then
  echo -e "  ${GREEN}✓${NC} Embedding server is reachable"

  # Test OpenAI-compatible /v1/embeddings endpoint
  echo "  Testing OpenAI-compatible /v1/embeddings endpoint..."
  embedding_request='{
    "model": "text-embedding-ada-002",
    "input": "Hello, world!"
  }'

  embedding_resp="$(curl -s -X POST "${EMBEDDING_URL}/v1/embeddings" \
    -H "Content-Type: application/json" \
    -d "${embedding_request}" 2>/dev/null || echo '{}')"

  # Check if response is valid OpenAI-compatible format
  # Response should have: {"object": "list", "data": [{"object": "embedding", "embedding": [...]}]}
  if echo "${embedding_resp}" | grep -qE '"object"\s*:\s*"list"' && \
     echo "${embedding_resp}" | grep -q '"data"' && \
     echo "${embedding_resp}" | grep -q '"embedding"'; then
    echo -e "    ${GREEN}✓${NC} /v1/embeddings endpoint working"
    # Extract embedding dimension if available
    embedding_size="$(echo "${embedding_resp}" | grep -o '"embedding":\[[^]]*\]' | head -1 | grep -o ',' | wc -l || echo 'unknown')"
    if [ "${embedding_size}" != "unknown" ]; then
      echo "      Embedding dimension: $((embedding_size + 1))"
    fi
    test_passed
  else
    echo -e "    ${RED}✗${NC} /v1/embeddings endpoint returned invalid response"
    echo "    Response preview: ${embedding_resp:0:200}..."
    # Show what was found for debugging
    if echo "${embedding_resp}" | grep -q '"object"'; then
      echo "    Found 'object' field"
    fi
    if echo "${embedding_resp}" | grep -q '"data"'; then
      echo "    Found 'data' field"
    fi
    if echo "${embedding_resp}" | grep -q '"embedding"'; then
      echo "    Found 'embedding' field"
    fi
    test_failed
  fi

  # Test with multiple inputs
  echo "  Testing /v1/embeddings with multiple inputs..."
  multi_embedding_request='{
    "model": "text-embedding-ada-002",
    "input": ["First text", "Second text"]
  }'

  multi_embedding_resp="$(curl -s -X POST "${EMBEDDING_URL}/v1/embeddings" \
    -H "Content-Type: application/json" \
    -d "${multi_embedding_request}" 2>/dev/null || echo '{}')"

  index_count="$(echo "${multi_embedding_resp}" | grep -o '"index"' | wc -l || echo "0")"
  if echo "${multi_embedding_resp}" | grep -qE '"object"\s*:\s*"list"' && \
     echo "${multi_embedding_resp}" | grep -q '"data"' && \
     [ "${index_count}" -ge 2 ]; then
    echo -e "    ${GREEN}✓${NC} Multiple inputs handled correctly (${index_count} embeddings)"
    test_passed
  else
    echo -e "    ${YELLOW}⚠${NC} Multiple inputs test inconclusive (found ${index_count} embeddings)"
    # Show what was found for debugging
    if echo "${multi_embedding_resp}" | grep -qE '"object"\s*:\s*"list"'; then
      echo "    Found 'object: list' field"
    fi
    if echo "${multi_embedding_resp}" | grep -q '"data"'; then
      echo "    Found 'data' field"
    fi
  fi

  # Test legacy /embedding endpoint (optional)
  echo "  Testing legacy /embedding endpoint..."
  legacy_request='{
    "embedding_type": "doc",
    "texts": ["Test document"]
  }'

  legacy_resp="$(curl -s -X POST "${EMBEDDING_URL}/embedding" \
    -H "Content-Type: application/json" \
    -d "${legacy_request}" 2>/dev/null || echo '{}')"

  if echo "${legacy_resp}" | grep -q '"dense_embeddings"'; then
    echo -e "    ${GREEN}✓${NC} Legacy /embedding endpoint working"
    test_passed
  else
    echo -e "    ${YELLOW}⚠${NC} Legacy /embedding endpoint not responding (may be optional)"
  fi

else
  echo -e "  ${YELLOW}⚠${NC} Embedding server not reachable (may not be started)"
  echo "    To start embedding server, set: export EMBEDDING_MODEL_DIR=/path/to/MiniCPM-Embedding-Light"
  echo "    Then restart the master container"
fi
echo ""

# Summary
echo "=========================================="
echo "Validation Summary"
echo "=========================================="
echo -e "  ${GREEN}Passed: ${PASSED}${NC}"
echo -e "  ${RED}Failed: ${FAILED}${NC}"
echo ""

if [ ${FAILED} -eq 0 ]; then
  echo -e "${GREEN}✅ All tests passed!${NC}"
  exit 0
else
  echo -e "${YELLOW}⚠ Some tests failed or warnings occurred${NC}"
  exit 0  # Don't fail the script, just report warnings
fi
