#!/usr/bin/env bash
# Validate the 2-server deployment (registry/router + InfiniLM backends)

set -e

SERVER1_IP="${1:-localhost}"
REGISTRY_URL="http://${SERVER1_IP}:18000"
ROUTER_URL="http://${SERVER1_IP}:8000"

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "InfiniLM-SVC (Rust) + InfiniLM Backend Validation"
echo "=========================================="
echo "Server 1: ${SERVER1_IP}"
echo "Registry: ${REGISTRY_URL}"
echo "Router:   ${ROUTER_URL}"
echo ""

check() {
  local url=$1
  local name=$2
  echo -n "  Checking ${name}... "
  if curl -s -f --connect-timeout 3 "${url}" > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
  else
    echo -e "${RED}✗${NC}"
    echo "    URL: ${url}"
    exit 1
  fi
}

echo -e "${BLUE}[1] Core health${NC}"
check "${REGISTRY_URL}/health" "Registry /health"
check "${ROUTER_URL}/health" "Router /health"
echo ""

echo -e "${BLUE}[2] Service discovery${NC}"
services_json="$(curl -s "${REGISTRY_URL}/services" 2>/dev/null || echo '{}')"
service_count="$(echo "${services_json}" | grep -o '"name"' | wc -l || echo "0")"
echo "  Found ${service_count} services"
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
echo "  Using model: ${test_model}"
request_data="{
  \"model\": \"${test_model}\",
  \"messages\": [{\"role\": \"user\", \"content\": \"Hello\"}],
  \"stream\": false
}"

resp="$(curl -s -X POST "${ROUTER_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "${request_data}" 2>/dev/null || echo '{}')"

echo "${resp}" | grep -q '"object"' && echo -e "  ${GREEN}✓${NC} Router returned response" || \
  (echo -e "  ${RED}✗${NC} Router response invalid"; echo "${resp}"; exit 1)

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
  else
    echo -e "  ${RED}✗${NC} Qwen3-32B model test failed"
    echo "${qwen_resp}"
    exit 1
  fi
  echo ""
else
  echo -e "${BLUE}[5] Qwen3-32B model test${NC}"
  echo -e "  ${YELLOW}⚠${NC} Qwen3-32B model not found, skipping test"
  echo ""
fi

echo -e "${GREEN}✅ Validation complete${NC}"
