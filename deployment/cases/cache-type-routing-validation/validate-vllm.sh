#!/usr/bin/env bash
# Validate vLLM backend deployment (2 vLLM instances under babysitter)
# Run after start-master-2vllm-qwen3-32b.sh

set -e

usage() {
  echo "Usage:"
  echo "  $0 <REGISTRY_IP>"
  echo ""
  echo "Notes:"
  echo "  - REGISTRY_PORT and ROUTER_PORT are taken from env (defaults: 18000 / 8000)"
  echo "  - Run after start-master-2vllm-qwen3-32b.sh"
  echo "  - Wait for vLLM model loading to complete (can take several minutes) before validating"
  echo ""
  echo "Examples:"
  echo "  $0 localhost"
  echo "  $0 172.22.162.17"
}

if [ $# -lt 1 ]; then
  usage
  exit 1
fi

REGISTRY_IP="${1:-localhost}"

REGISTRY_PORT="${REGISTRY_PORT:-18000}"
ROUTER_PORT="${ROUTER_PORT:-8000}"
REGISTRY_URL="http://${REGISTRY_IP}:${REGISTRY_PORT}"
ROUTER_URL="http://${REGISTRY_IP}:${ROUTER_PORT}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0

echo "=========================================="
echo "vLLM Backend Validation"
echo "=========================================="
echo "Registry IP: ${REGISTRY_IP}"
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

echo -e "${BLUE}[2] Babysitter health (vLLM instances)${NC}"
if curl -s -f --connect-timeout 3 "http://${REGISTRY_IP}:8401/health" > /dev/null 2>&1; then
  echo -e "  ${GREEN}✓${NC} vllm-qwen3-32b-1 babysitter (8401) healthy"
  test_passed
else
  echo -e "  ${RED}✗${NC} vllm-qwen3-32b-1 babysitter (8401) not responding"
  test_failed
fi

if curl -s -f --connect-timeout 3 "http://${REGISTRY_IP}:8501/health" > /dev/null 2>&1; then
  echo -e "  ${GREEN}✓${NC} vllm-qwen3-32b-2 babysitter (8501) healthy"
  test_passed
else
  echo -e "  ${RED}✗${NC} vllm-qwen3-32b-2 babysitter (8501) not responding"
  test_failed
fi
echo ""

echo -e "${BLUE}[3] vLLM service health${NC}"
# vLLM OpenAI API exposes /v1/models
if curl -s -f --connect-timeout 5 "http://${REGISTRY_IP}:8400/v1/models" > /dev/null 2>&1; then
  echo -e "  ${GREEN}✓${NC} vLLM instance 1 (8400) responding"
  test_passed
else
  echo -e "  ${RED}✗${NC} vLLM instance 1 (8400) not responding (model may still be loading)"
  test_failed
fi

if curl -s -f --connect-timeout 5 "http://${REGISTRY_IP}:8500/v1/models" > /dev/null 2>&1; then
  echo -e "  ${GREEN}✓${NC} vLLM instance 2 (8500) responding"
  test_passed
else
  echo -e "  ${RED}✗${NC} vLLM instance 2 (8500) not responding (model may still be loading)"
  test_failed
fi
echo ""

echo -e "${BLUE}[4] Service discovery${NC}"
CONTAINER_NAME="${CONTAINER_NAME:-infinilm-svc-master-2vllm-qwen3-32b}"
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  services_json="$(docker exec "${CONTAINER_NAME}" curl -s --noproxy "*" "http://127.0.0.1:${REGISTRY_PORT}/services" 2>/dev/null || curl -s "${REGISTRY_URL}/services" 2>/dev/null || echo '{}')"
else
  services_json="$(curl -s "${REGISTRY_URL}/services" 2>/dev/null || echo '{}')"
fi

expected_services=("vllm-qwen3-32b-1" "vllm-qwen3-32b-2")
echo "  Expected services: ${expected_services[*]}"
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
    test_passed
  fi
fi
echo ""

echo -e "${BLUE}[5] Model aggregation${NC}"
models_json="$(curl -s "${ROUTER_URL}/models" 2>/dev/null || echo '{}')"
model_ids="$(echo "${models_json}" | grep -o '"id":"[^"]*"' | sed 's/"id":"\([^"]*\)"/\1/' | tr '\n' ' ' || echo '')"
if [ -z "${model_ids}" ] || [ "${model_ids}" = " " ]; then
  echo -e "  ${RED}✗${NC} No models found"
  test_failed
  test_model="Qwen3-32B"
else
  echo "  Found models: ${model_ids}"
  # vLLM may expose Qwen3-32B or similar (path-based or HuggingFace ID)
  if echo "${model_ids}" | grep -q "Qwen3-32B\|Qwen3_32B\|qwen3-32b"; then
    test_model="$(echo "${model_ids}" | tr ' ' '\n' | grep -i qwen3 | head -1)"
    echo -e "  ${GREEN}✓${NC} Qwen3-32B model found"
    test_passed
  else
    test_model="$(echo "${model_ids}" | tr ' ' '\n' | head -1)"
    echo -e "  ${YELLOW}⚠${NC} Using first available model: ${test_model}"
    test_passed
  fi
fi
echo ""

echo -e "${BLUE}[6] Chat completions via router${NC}"
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
  echo -e "  ${GREEN}✓${NC} Router returned valid response"
  test_passed
else
  echo -e "  ${RED}✗${NC} Router response invalid"
  echo "  Response: ${resp:0:500}..."
  echo ""
  test_failed
fi
echo ""

# Summary
echo "=========================================="
echo "Validation Summary"
echo "=========================================="
echo -e "  ${GREEN}Passed: ${PASSED}${NC}"
echo -e "  ${RED}Failed: ${FAILED}${NC}"
echo ""
echo "If tests failed, check logs: ./check-container.sh 2vllm"
echo ""

if [ ${FAILED} -eq 0 ]; then
  echo -e "${GREEN}✅ All vLLM backend tests passed!${NC}"
  exit 0
else
  echo -e "${YELLOW}⚠ Some tests failed. Ensure vLLM has finished loading the model.${NC}"
  exit 1
fi
