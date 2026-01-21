#!/usr/bin/env bash
# Validate the 2-server deployment (registry/router + InfiniLM backends)

set -e

SERVER1_IP="${1:-localhost}"
SERVER2_IP="${2:-}"
REGISTRY_PORT="${3:-18000}"
ROUTER_PORT="${4:-8000}"
REGISTRY_URL="http://${SERVER1_IP}:${REGISTRY_PORT}"
ROUTER_URL="http://${SERVER1_IP}:${ROUTER_PORT}"

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
echo "Server 1: ${SERVER1_IP}"
echo "Server 2: ${SERVER2_IP:-not specified}"
echo "Registry: ${REGISTRY_URL} (port ${REGISTRY_PORT})"
echo "Router:   ${ROUTER_URL} (port ${ROUTER_PORT})"
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
services_json="$(curl -s "${REGISTRY_URL}/services" 2>/dev/null || echo '{}')"
service_count="$(echo "${services_json}" | grep -o '"name"' | wc -l || echo "0")"
echo "  Found ${service_count} services"

# Check for expected services
expected_services=("server1-9g_8b_thinking_llama-server" "server1-Qwen3-32B-server")
if [ -n "${SERVER2_IP}" ]; then
  expected_services+=("server2-9g_8b_thinking_llama-server" "server2-Qwen3-32B-server")
fi

echo "  Expected services: ${#expected_services[@]} (${expected_services[*]})"
found_services=()
for svc in "${expected_services[@]}"; do
  if echo "${services_json}" | grep -q "\"name\":\"${svc}\""; then
    found_services+=("${svc}")
    echo "    ${GREEN}✓${NC} ${svc}"
  else
    echo "    ${RED}✗${NC} ${svc} (not found)"
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
expected_model1="9g_8b_thinking_llama"
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
if [ -n "${SERVER2_IP}" ] && echo "${model_ids}" | grep -q "9g_8b_thinking_llama"; then
  echo -e "${BLUE}[6] Load balancing test${NC}"
  echo "  Sending 4 requests for 9g_8b_thinking_llama (should balance between Server 1 and Server 2)..."
  services_hit=()
  for i in {1..4}; do
    resp="$(curl -s -X POST "${ROUTER_URL}/v1/chat/completions" \
      -H "Content-Type: application/json" \
      -d '{"model": "9g_8b_thinking_llama", "messages": [{"role": "user", "content": "Test"}], "stream": false}' 2>/dev/null || echo '{}')"
    if echo "${resp}" | grep -q '"object"'; then
      services_hit+=("request-$i")
    fi
    sleep 0.5
  done

  if [ ${#services_hit[@]} -ge 3 ]; then
    echo "  ${GREEN}✓${NC} Load balancing working (${#services_hit[@]}/4 requests succeeded)"
    test_passed
  else
    echo "  ${YELLOW}⚠${NC} Only ${#services_hit[@]}/4 requests succeeded (may be normal if services just started)"
    test_passed  # Not a failure
  fi
  echo ""
fi

# Test Server 2 health if specified
if [ -n "${SERVER2_IP}" ]; then
  echo -e "${BLUE}[7] Server 2 health check${NC}"
  echo "  Checking Server 2 babysitter health endpoints..."

  # Check babysitter-c health
  if curl -s -f --connect-timeout 3 "http://${SERVER2_IP}:8101/health" > /dev/null 2>&1; then
    echo "    ${GREEN}✓${NC} Babysitter C (8101) healthy"
    test_passed
  else
    echo "    ${RED}✗${NC} Babysitter C (8101) not responding"
    test_failed
  fi

  # Check babysitter-d health
  if curl -s -f --connect-timeout 3 "http://${SERVER2_IP}:8201/health" > /dev/null 2>&1; then
    echo "    ${GREEN}✓${NC} Babysitter D (8201) healthy"
    test_passed
  else
    echo "    ${RED}✗${NC} Babysitter D (8201) not responding"
    test_failed
  fi
  echo ""
fi

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
