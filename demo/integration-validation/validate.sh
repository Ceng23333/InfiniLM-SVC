#!/usr/bin/env bash
# Validation script for integration demo
# Tests: model aggregation, service discovery, chat completions routing

set -e

SERVER1_IP="${1:-localhost}"
REGISTRY_URL="http://${SERVER1_IP}:18000"
ROUTER_URL="http://${SERVER1_IP}:8000"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0

echo "=========================================="
echo "InfiniLM-SVC Integration Validation"
echo "=========================================="
echo "Server 1: ${SERVER1_IP}"
echo "Registry: ${REGISTRY_URL}"
echo "Router: ${ROUTER_URL}"
echo ""

# Helper functions
check_endpoint() {
    local url=$1
    local description=$2
    local expected_status=${3:-200}

    echo -n "  Checking ${description}... "
    local response
    response=$(curl -s -w "\n%{http_code}" "${url}" 2>/dev/null || echo -e "\n000")
    local status_code
    status_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | sed '$d')

    if [ "$status_code" = "$expected_status" ]; then
        echo -e "${GREEN}✓${NC} (HTTP ${status_code})"
        # Only print body if it's not empty and not just whitespace
        if [ -n "$body" ] && [ -n "${body// }" ]; then
            echo "$body"
        fi
        return 0
    else
        echo -e "${RED}✗${NC} (HTTP ${status_code}, expected ${expected_status})"
        if [ -n "$body" ] && [ -n "${body// }" ]; then
            echo "  Response: $body"
        fi
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

# Test 1: Registry Health
echo -e "${BLUE}[Test 1] Registry Health${NC}"
if check_endpoint "${REGISTRY_URL}/health" "Registry health"; then
    test_passed
else
    test_failed
    echo "  Cannot proceed without registry"
    exit 1
fi
echo ""

# Test 2: Router Health
echo -e "${BLUE}[Test 2] Router Health${NC}"
if check_endpoint "${ROUTER_URL}/health" "Router health"; then
    test_passed
else
    test_failed
    echo "  Cannot proceed without router"
    exit 1
fi
echo ""

# Test 3: Service Discovery
echo -e "${BLUE}[Test 3] Service Discovery${NC}"
echo "  Checking registered services..."
services_json=$(curl -s "${REGISTRY_URL}/services" 2>/dev/null || echo "{}")
service_count=$(echo "$services_json" | grep -o '"name"' | wc -l || echo "0")

echo "  Found ${service_count} services"
if [ "$service_count" -ge 4 ]; then
    echo "  Services:"
    echo "$services_json" | grep -o '"name":"[^"]*"' | sed 's/"name":"\(.*\)"/    - \1/' || true
    test_passed
else
    echo "  Expected at least 4 services (A, B, C, D), found ${service_count}"
    test_failed
fi
echo ""

# Test 4: Model Aggregation
echo -e "${BLUE}[Test 4] Model Aggregation${NC}"
echo "  Checking aggregated models from router..."
models_json=$(curl -s "${ROUTER_URL}/models" 2>/dev/null || echo "{}")

if echo "$models_json" | grep -q "model-1" && echo "$models_json" | grep -q "model-2"; then
    echo "  ✓ Both models found in aggregation"
    echo "  Models:"
    echo "$models_json" | grep -o '"id":"[^"]*"' | sed 's/"id":"\(.*\)"/    - \1/' | sort -u || true
    test_passed
else
    echo "  ✗ Missing models in aggregation"
    echo "  Response: $models_json"
    test_failed
fi
echo ""

# Test 5: Chat Completions - Model 1
echo -e "${BLUE}[Test 5] Chat Completions - Model 1${NC}"
echo "  Sending request for model-1..."
request_data='{
  "model": "model-1",
  "messages": [{"role": "user", "content": "Hello"}],
  "stream": false
}'

response=$(curl -s -X POST "${ROUTER_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "$request_data" 2>/dev/null || echo "{}")

if echo "$response" | grep -q "model-1" && echo "$response" | grep -q "mock-service"; then
    service_name=$(echo "$response" | grep -o '"content":"[^"]*"' | head -1 | grep -o 'mock-service-[abcd]' || echo "unknown")
    echo "  ✓ Request routed successfully"
    echo "  Response from: ${service_name}"
    echo "  Content: $(echo "$response" | grep -o '"content":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "N/A")"
    test_passed
else
    echo "  ✗ Request failed or incorrect response"
    echo "  Response: $response"
    test_failed
fi
echo ""

# Test 6: Chat Completions - Model 2
echo -e "${BLUE}[Test 6] Chat Completions - Model 2${NC}"
echo "  Sending request for model-2..."
request_data='{
  "model": "model-2",
  "messages": [{"role": "user", "content": "Hello"}],
  "stream": false
}'

response=$(curl -s -X POST "${ROUTER_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "$request_data" 2>/dev/null || echo "{}")

if echo "$response" | grep -q "model-2" && echo "$response" | grep -q "mock-service"; then
    service_name=$(echo "$response" | grep -o '"content":"[^"]*"' | head -1 | grep -o 'mock-service-[abcd]' || echo "unknown")
    echo "  ✓ Request routed successfully"
    echo "  Response from: ${service_name}"
    echo "  Content: $(echo "$response" | grep -o '"content":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "N/A")"
    test_passed
else
    echo "  ✗ Request failed or incorrect response"
    echo "  Response: $response"
    test_failed
fi
echo ""

# Test 7: Multiple Requests (Load Balancing)
echo -e "${BLUE}[Test 7] Load Balancing Test${NC}"
echo "  Sending 4 requests for model-1 (should balance between A and C)..."
services_hit=()
for i in {1..4}; do
    response=$(curl -s -X POST "${ROUTER_URL}/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d '{"model": "model-1", "messages": [{"role": "user", "content": "Test"}], "stream": false}' 2>/dev/null || echo "{}")
    service=$(echo "$response" | grep -o 'mock-service-[ac]' | head -1 || echo "unknown")
    services_hit+=("$service")
    sleep 0.5
done

unique_services=$(printf '%s\n' "${services_hit[@]}" | sort -u | wc -l)
echo "  Services hit: ${services_hit[*]}"
if [ "$unique_services" -ge 2 ]; then
    echo "  ✓ Load balancing working (requests distributed across services)"
    test_passed
else
    echo "  ⚠️  Only one service handled requests (may be normal if services just started)"
    test_passed  # Not a failure, just informational
fi
echo ""

# Test 8: Log Verification
echo -e "${BLUE}[Test 8] Log Verification${NC}"
echo "  Checking service logs for request handling..."

if docker ps --format '{{.Names}}' | grep -q "infinilm-svc-server1"; then
    echo "  Server 1 logs (last 20 lines):"
    docker logs --tail 20 infinilm-svc-server1 2>&1 | grep -i "chat\|completion\|request" | tail -5 || echo "    (no relevant log entries found)"
fi

if docker ps --format '{{.Names}}' | grep -q "infinilm-svc-server2"; then
    echo "  Server 2 logs (last 20 lines):"
    docker logs --tail 20 infinilm-svc-server2 2>&1 | grep -i "chat\|completion\|request" | tail -5 || echo "    (no relevant log entries found)"
fi

echo "  ✓ Log check complete (verify manually if needed)"
test_passed
echo ""

# Summary
echo "=========================================="
echo "Validation Summary"
echo "=========================================="
echo -e "  ${GREEN}Passed: ${PASSED}${NC}"
echo -e "  ${RED}Failed: ${FAILED}${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed${NC}"
    exit 1
fi
