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
echo "${models_json}" | grep -q '"id":"jiuge"' && \
  echo -e "  ${GREEN}✓${NC} Found model id: jiuge" || \
  (echo -e "  ${RED}✗${NC} Missing model id: jiuge"; echo "${models_json}"; exit 1)
echo ""

echo -e "${BLUE}[4] Chat completions via router${NC}"
request_data='{
  "model": "jiuge",
  "messages": [{"role": "user", "content": "Hello"}],
  "stream": false
}'

resp="$(curl -s -X POST "${ROUTER_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "${request_data}" 2>/dev/null || echo '{}')"

echo "${resp}" | grep -q '"object"' && echo -e "  ${GREEN}✓${NC} Router returned response" || \
  (echo -e "  ${RED}✗${NC} Router response invalid"; echo "${resp}"; exit 1)

echo ""
echo -e "${GREEN}✅ Validation complete${NC}"
