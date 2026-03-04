#!/usr/bin/env bash
# Validate infinilm-metax-deployment-opt (registry, router, master backends, optional slave)

set -e

usage() {
  echo "Usage:"
  echo "  $0 <REGISTRY_IP> [SLAVE_IP] [SLAVE_PRESET] [MASTER_PRESET]"
  echo ""
  echo "SLAVE_PRESET (when SLAVE_IP given): 2static (default), 1static1vllm, or 3vllm"
  echo "MASTER_PRESET (optional): when 3vllm, expect master-3vllm-vllm-1 instead of master-qwen3-32b-paged"
  echo ""
  echo "Examples:"
  echo "  $0 192.168.163.151"
  echo "  $0 192.168.163.151 192.168.163.152"
  echo "  $0 192.168.163.151 192.168.163.152 1static1vllm"
  echo "  $0 192.168.163.151 192.168.163.152 3vllm 3vllm"
}

if [ $# -lt 1 ]; then
  usage
  exit 1
fi

REGISTRY_IP="${1:-localhost}"
SLAVE_IP="${2:-}"
SLAVE_PRESET="${3:-${SLAVE_PRESET:-2static}}"
MASTER_PRESET="${4:-${MASTER_PRESET:-}}"

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
echo "Slave preset:  ${SLAVE_PRESET:-n/a}"
echo "Master preset: ${MASTER_PRESET:-default}"
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

# Expected master services: depend on MASTER_PRESET
if [ "${MASTER_PRESET}" = "3vllm" ]; then
  expected_services=("master-9g_8b_thinking-server" "master-3vllm-vllm-1-server")
else
  expected_services=("master-9g_8b_thinking-server" "master-qwen3-32b-paged-server")
fi
# Optional slave preset services
if [ -n "${SLAVE_IP}" ]; then
  case "${SLAVE_PRESET}" in
    2static)
      expected_services+=("slave-2static-1-server" "slave-2static-2-server")
      ;;
    1static1vllm)
      expected_services+=("slave-1static1vllm-static-1-server" "slave-1static1vllm-vllm-1-server")
      ;;
    3vllm)
      expected_services+=("slave-3vllm-vllm-1-server" "slave-3vllm-vllm-2-server")
      ;;
    *)
      echo "  Warning: Unknown SLAVE_PRESET '${SLAVE_PRESET}'; expecting 2static, 1static1vllm, or 3vllm"
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
# Test all models from step 3 (skip permission-style ids like modelperm-*)
test_models="9g_8b_thinking"
if [ -n "${model_ids}" ] && [ "${model_ids}" != " " ]; then
  test_models=""
  for model_id in ${model_ids}; do
    case "${model_id}" in
      modelperm-*) ;;
      *) test_models="${test_models} ${model_id}" ;;
    esac
  done
  test_models="${test_models# }"
fi
if [ -z "${test_models}" ]; then
  test_models="9g_8b_thinking"
fi
for test_model in ${test_models}; do
  echo -n "  Testing model: ${test_model}... "
  request_data="{\"model\": \"${test_model}\", \"messages\": [{\"role\": \"user\", \"content\": \"Hello\"}], \"stream\": false}"
  resp="$(curl -s -X POST --noproxy "*" "${ROUTER_URL}/v1/chat/completions" -H "Content-Type: application/json" -d "${request_data}" 2>/dev/null || echo '{}')"
  if echo "${resp}" | grep -q '"object"'; then
    echo -e "${GREEN}OK${NC}"
    PASSED=$((PASSED + 1))
  else
    echo -e "${RED}FAIL${NC}"
    FAILED=$((FAILED + 1))
    echo "    Response: ${resp}"
  fi
done
echo ""

echo "=========================================="
echo "Validation complete"
echo "=========================================="
