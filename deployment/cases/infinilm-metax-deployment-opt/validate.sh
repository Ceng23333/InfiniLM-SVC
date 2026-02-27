#!/usr/bin/env bash
# Validate infinilm-metax-deployment-opt (registry, router, master backends, optional slave)

set -e

usage() {
  echo "Usage:"
  echo "  $0 <REGISTRY_IP> [SLAVE_IP] [SLAVE_PRESET]"
  echo ""
  echo "SLAVE_PRESET (when SLAVE_IP given): 4static (default) or 2static1vllm"
  echo ""
  echo "Examples:"
  echo "  $0 192.168.163.151"
  echo "  $0 192.168.163.151 192.168.163.152"
  echo "  $0 192.168.163.151 192.168.163.152 2static1vllm"
}

if [ $# -lt 1 ]; then
  usage
  exit 1
fi

REGISTRY_IP="${1:-localhost}"
SLAVE_IP="${2:-}"
SLAVE_PRESET="${3:-${SLAVE_PRESET:-4static}}"

REGISTRY_PORT="${REGISTRY_PORT:-18000}"
ROUTER_PORT="${ROUTER_PORT:-8000}"
EMBEDDING_PORT="${EMBEDDING_PORT:-20002}"
REGISTRY_URL="http://${REGISTRY_IP}:${REGISTRY_PORT}"
ROUTER_URL="http://${REGISTRY_IP}:${ROUTER_PORT}"
EMBEDDING_URL="http://${REGISTRY_IP}:${EMBEDDING_PORT}"

CONTAINER_NAME="${CONTAINER_NAME:-infinilm-svc-master-opt}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0

echo "=========================================="
echo "InfiniLM-SVC infinilm-metax-deployment-opt Validation"
echo "=========================================="
echo "Registry IP:  ${REGISTRY_IP}"
echo "Slave IP:     ${SLAVE_IP:-none}"
echo "Slave preset: ${SLAVE_PRESET:-n/a}"
echo "Registry:     ${REGISTRY_URL}"
echo "Router:      ${ROUTER_URL}"
echo ""

check() {
  local url=$1
  local name=$2
  echo -n "  Checking ${name}... "
  if curl -s -f --connect-timeout 3 --noproxy "*" "${url}" > /dev/null 2>&1; then
    echo -e "${GREEN}OK${NC}"
    PASSED=$((PASSED + 1))
    return 0
  else
    echo -e "${RED}FAIL${NC}"
    FAILED=$((FAILED + 1))
    return 1
  fi
}

echo -e "${BLUE}[1] Core health${NC}"
check "${REGISTRY_URL}/health" "Registry /health"
check "${ROUTER_URL}/health" "Router /health"
echo ""

echo -e "${BLUE}[2] Service discovery${NC}"
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  services_json="$(docker exec "${CONTAINER_NAME}" curl -s --noproxy "*" "http://127.0.0.1:${REGISTRY_PORT}/services" 2>/dev/null || curl -s --noproxy "*" "${REGISTRY_URL}/services" 2>/dev/null || echo '{}')"
else
  services_json="$(curl -s --noproxy "*" "${REGISTRY_URL}/services" 2>/dev/null || echo '{}')"
fi
service_count="$(echo "${services_json}" | grep -o '"name"' | wc -l || echo "0")"
echo "  Found ${service_count} services"

# Expected: master-9g_8b_thinking-server, master-qwen3-32b-paged-server; optional slave preset services
expected_services=("master-9g_8b_thinking-server" "master-qwen3-32b-paged-server")
if [ -n "${SLAVE_IP}" ]; then
  case "${SLAVE_PRESET}" in
    4static)
      expected_services+=("slave-4static-1-server" "slave-4static-2-server" "slave-4static-3-server" "slave-4static-4-server")
      ;;
    2static1vllm)
      expected_services+=("slave-2static1vllm-static-1-server" "slave-2static1vllm-static-2-server" "slave-2static1vllm-vllm-1-server")
      ;;
    *)
      echo "  Warning: Unknown SLAVE_PRESET '${SLAVE_PRESET}'; expecting 4static or 2static1vllm"
      ;;
  esac
fi
for svc in "${expected_services[@]}"; do
  if echo "${services_json}" | grep -q "\"name\":\"${svc}\""; then
    echo -e "    ${GREEN}OK${NC} ${svc}"
  else
    echo -e "    ${YELLOW}missing${NC} ${svc}"
  fi
done
echo ""

echo -e "${BLUE}[3] Model aggregation${NC}"
models_json="$(curl -s --noproxy "*" "${ROUTER_URL}/models" 2>/dev/null || echo '{}')"
model_ids="$(echo "${models_json}" | grep -o '"id":"[^"]*"' | sed 's/"id":"\([^"]*\)"/\1/' | tr '\n' ' ' || echo '')"
if [ -z "${model_ids}" ] || [ "${model_ids}" = " " ]; then
  echo -e "  ${RED}No models found${NC}"
else
  for model_id in ${model_ids}; do
    echo "  Found model: ${model_id}"
  done
fi
echo ""

echo -e "${BLUE}[4] Chat completions via router${NC}"
test_model="9g_8b_thinking"
if [ -n "${model_ids}" ] && [ "${model_ids}" != " " ]; then
  test_model="$(echo "${model_ids}" | awk '{print $1}')"
fi
echo "  Testing model: ${test_model}"
request_data="{\"model\": \"${test_model}\", \"messages\": [{\"role\": \"user\", \"content\": \"Hello\"}], \"stream\": false}"
resp="$(curl -s -X POST --noproxy "*" "${ROUTER_URL}/v1/chat/completions" -H "Content-Type: application/json" -d "${request_data}" 2>/dev/null || echo '{}')"
if echo "${resp}" | grep -q '"object"'; then
  echo -e "  ${GREEN}OK${NC} Router returned response"
else
  echo -e "  ${RED}FAIL${NC} Router response invalid"
  echo "  Response: ${resp}"
fi
echo ""

echo "=========================================="
echo "Validation complete"
echo "=========================================="
