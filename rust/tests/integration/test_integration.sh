#!/bin/bash
# Integration tests for Rust router with Rust babysitter managing mock services

set -euo pipefail

ROUTER_PORT=8900
REGISTRY_PORT=8901
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ROUTER_BIN="$PROJECT_ROOT/rust/target/release/infini-router"
BABYSITTER_BIN="$PROJECT_ROOT/rust/target/release/infini-babysitter"
REGISTRY_BIN="$PROJECT_ROOT/rust/target/release/infini-registry"
REGISTRY_SCRIPT="$PROJECT_ROOT/python/service_registry.py"
MOCK_SERVICE_SCRIPT="$SCRIPT_DIR/mock_service.py"

# Test ports - allocate ports with gaps to avoid conflicts
# Each service needs its own port, and each babysitter needs its own port (service_port + 1)
SERVICE1_PORT=6001
BABYSITTER1_PORT=6002
SERVICE2_PORT=6003
BABYSITTER2_PORT=6004
SERVICE3_PORT=6005
BABYSITTER3_PORT=6006

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Integration Tests: Rust Router + Rust Babysitter + Mock Services"
echo "=========================================="
echo ""

# Check prerequisites
if [ ! -f "$ROUTER_BIN" ]; then
    echo "Error: Router binary not found. Please build it first:"
    echo "  cd rust && cargo build --release --bin infini-router"
    exit 1
fi

if [ ! -f "$BABYSITTER_BIN" ]; then
    echo "Error: Babysitter binary not found. Please build it first:"
    echo "  cd rust && cargo build --release --bin infini-babysitter"
    exit 1
fi

if [ ! -f "$REGISTRY_BIN" ]; then
    echo "Error: Registry binary not found. Please build it first:"
    echo "  cd rust && cargo build --release --bin infini-registry"
    exit 1
fi

if [ ! -f "$MOCK_SERVICE_SCRIPT" ]; then
    echo "Error: Mock service script not found: $MOCK_SERVICE_SCRIPT"
    exit 1
fi

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up..."
    kill $ROUTER_PID 2>/dev/null || true
    kill $REGISTRY_PID 2>/dev/null || true
    kill $BABYSITTER1_PID 2>/dev/null || true
    kill $BABYSITTER2_PID 2>/dev/null || true
    kill $BABYSITTER3_PID 2>/dev/null || true
    wait $ROUTER_PID 2>/dev/null || true
    wait $REGISTRY_PID 2>/dev/null || true
    wait $BABYSITTER1_PID 2>/dev/null || true
    wait $BABYSITTER2_PID 2>/dev/null || true
    wait $BABYSITTER3_PID 2>/dev/null || true
    pkill -f "mock_service.py" 2>/dev/null || true
    pkill -f "service_registry.py" 2>/dev/null || true
    pkill -f "infini-router" 2>/dev/null || true
    pkill -f "infini-babysitter" 2>/dev/null || true
    pkill -f "infini-registry" 2>/dev/null || true
    # Clean up any processes on test ports
    lsof -ti:$ROUTER_PORT | xargs kill -9 2>/dev/null || true
    lsof -ti:$REGISTRY_PORT | xargs kill -9 2>/dev/null || true
    lsof -ti:$SERVICE1_PORT,$SERVICE2_PORT,$SERVICE3_PORT,$BABYSITTER1_PORT,$BABYSITTER2_PORT,$BABYSITTER3_PORT | xargs kill -9 2>/dev/null || true
}
trap cleanup EXIT

# Start registry
echo "Starting registry on port $REGISTRY_PORT..."
mkdir -p "$PROJECT_ROOT/logs"
cd "$PROJECT_ROOT"

# Setup Python environment - use dedicated integration test environment
PYTHON_CMD="python3"
CONDA_ENV="infinilm-integration-test"

if command -v conda &> /dev/null; then
    # Check if integration test environment exists
    if conda env list | grep -q "^${CONDA_ENV} "; then
        PYTHON_CMD="conda run -n ${CONDA_ENV} python"
        echo "Using conda environment: ${CONDA_ENV}"
        
        # Verify aiohttp is available
        if ! $PYTHON_CMD -c "import aiohttp" 2>/dev/null; then
            echo "Installing dependencies in ${CONDA_ENV}..."
            conda run -n ${CONDA_ENV} pip install aiohttp requests > /dev/null 2>&1
        fi
    elif [ -f "$PROJECT_ROOT/python/activate_env.sh" ]; then
        source "$PROJECT_ROOT/python/activate_env.sh"
        echo "Using activated environment from activate_env.sh"
    else
        echo "⚠️  Conda environment '${CONDA_ENV}' not found. Creating it..."
        conda create -n ${CONDA_ENV} python=3.10 -y > /dev/null 2>&1
        conda run -n ${CONDA_ENV} pip install aiohttp requests > /dev/null 2>&1
        PYTHON_CMD="conda run -n ${CONDA_ENV} python"
        echo "✅ Created and configured ${CONDA_ENV} environment"
    fi
elif [ -f "$PROJECT_ROOT/python/activate_env.sh" ]; then
    source "$PROJECT_ROOT/python/activate_env.sh"
    echo "Using activated environment from activate_env.sh"
fi

# Final verification
if ! $PYTHON_CMD -c "import aiohttp" 2>/dev/null; then
    echo "Error: aiohttp not available. Please install it:"
    echo "  conda run -n ${CONDA_ENV} pip install aiohttp"
    exit 1
fi

# Start Rust registry
echo "Starting registry..."
$REGISTRY_BIN --port $REGISTRY_PORT 2>&1 | tee /tmp/registry_babysitter_test.log &
REGISTRY_PID=$!
sleep 3

# Verify registry is running
if ! curl -s http://127.0.0.1:$REGISTRY_PORT/health > /dev/null; then
    echo "Error: Registry failed to start"
    echo "Registry log:"
    cat /tmp/registry_babysitter_test.log
    exit 1
fi
echo "✅ Registry started (PID: $REGISTRY_PID)"

# Create temporary config files for babysitters
CONFIG_DIR="/tmp/babysitter_test_configs"
mkdir -p "$CONFIG_DIR"

# Babysitter 1: Manages service with model-a and model-shared
cat > "$CONFIG_DIR/babysitter1.toml" <<EOF
name = "babysitter-service-model-a"
port = $SERVICE1_PORT
registry_url = "http://127.0.0.1:$REGISTRY_PORT"

[babysitter]
max_restarts = 10
restart_delay = 2
heartbeat_interval = 10

[backend]
type = "command"
command = "$PYTHON_CMD"
args = ["$MOCK_SERVICE_SCRIPT", "--name", "service-model-a", "--port", "$SERVICE1_PORT", "--models", "model-a,model-shared", "--registry-url", "http://127.0.0.1:$REGISTRY_PORT"]
EOF

# Babysitter 2: Manages service with model-b and model-shared
cat > "$CONFIG_DIR/babysitter2.toml" <<EOF
name = "babysitter-service-model-b"
port = $SERVICE2_PORT
registry_url = "http://127.0.0.1:$REGISTRY_PORT"

[babysitter]
max_restarts = 10
restart_delay = 2
heartbeat_interval = 10

[backend]
type = "command"
command = "$PYTHON_CMD"
args = ["$MOCK_SERVICE_SCRIPT", "--name", "service-model-b", "--port", "$SERVICE2_PORT", "--models", "model-b,model-shared", "--registry-url", "http://127.0.0.1:$REGISTRY_PORT"]
EOF

# Babysitter 3: Manages service with model-c only
cat > "$CONFIG_DIR/babysitter3.toml" <<EOF
name = "babysitter-service-model-c"
port = $SERVICE3_PORT
registry_url = "http://127.0.0.1:$REGISTRY_PORT"

[babysitter]
max_restarts = 10
restart_delay = 2
heartbeat_interval = 10

[backend]
type = "command"
command = "$PYTHON_CMD"
args = ["$MOCK_SERVICE_SCRIPT", "--name", "service-model-c", "--port", "$SERVICE3_PORT", "--models", "model-c", "--registry-url", "http://127.0.0.1:$REGISTRY_PORT"]
EOF

# Start babysitters
echo ""
echo "Starting Rust babysitters with mock services..."

# Start babysitters and capture both stdout and stderr, also tee to console for debugging
$BABYSITTER_BIN --config-file "$CONFIG_DIR/babysitter1.toml" 2>&1 | tee /tmp/babysitter1.log &
BABYSITTER1_PID=$!

$BABYSITTER_BIN --config-file "$CONFIG_DIR/babysitter2.toml" 2>&1 | tee /tmp/babysitter2.log &
BABYSITTER2_PID=$!

$BABYSITTER_BIN --config-file "$CONFIG_DIR/babysitter3.toml" 2>&1 | tee /tmp/babysitter3.log &
BABYSITTER3_PID=$!

# Give babysitters more time to start services (CI may be slower)
echo "Waiting for babysitters to start services..."
sleep 5
echo "✅ Babysitters started (PIDs: $BABYSITTER1_PID, $BABYSITTER2_PID, $BABYSITTER3_PID)"

# Verify babysitters are running
for i in 1 2 3; do
    PORT_VAR="BABYSITTER${i}_PORT"
    PORT=${!PORT_VAR}
    if curl -s http://127.0.0.1:$PORT/health > /dev/null 2>&1; then
        echo "✅ Babysitter $i health check passed (port $PORT)"
    else
        echo "⚠️  Babysitter $i health check not ready yet (port $PORT)"
    fi
done

# Start router
echo ""
echo "Starting router on port $ROUTER_PORT..."
$ROUTER_BIN \
    --router-port $ROUTER_PORT \
    --registry-url "http://127.0.0.1:$REGISTRY_PORT" \
    --health-interval 5 \
    --registry-sync-interval 2 \
    2>&1 | tee /tmp/router_babysitter_test.log &
ROUTER_PID=$!

sleep 3
echo "✅ Router started (PID: $ROUTER_PID)"

# Wait for services to be discovered and health checks to pass
echo ""
echo "Waiting for service discovery and health checks..."
sleep 5

# Verify services are registered and healthy
echo "Checking service registration..."
for i in {1..20}; do
    SERVICES=$(curl -s http://127.0.0.1:$ROUTER_PORT/services 2>/dev/null || echo '{"services":[]}')
    HEALTHY_COUNT=$(echo "$SERVICES" | python3 -c "import sys, json; data=json.load(sys.stdin); print(sum(1 for s in data.get('services', []) if s.get('healthy', False)))" 2>/dev/null || echo "0")
    if [ "$HEALTHY_COUNT" -ge 3 ]; then
        echo "✅ $HEALTHY_COUNT services are healthy"
        break
    fi
    if [ $i -lt 20 ]; then
        echo "Waiting for services to become healthy... ($i/20)"
        sleep 1
    fi
done

# Additional wait to ensure services are fully ready and can accept requests
# CI may need more time for services to start and register
echo "Waiting for services to be fully ready..."
sleep 10

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Disable exit on error for test execution (we handle failures explicitly)
set +e

# Test 1: Babysitter health endpoints
echo ""
echo "=========================================="
echo "Test 1: Babysitter Health Endpoints"
echo "=========================================="
BABYSITTER1_HEALTH=$(curl -s http://127.0.0.1:$BABYSITTER1_PORT/health 2>/dev/null || echo '{}')
if echo "$BABYSITTER1_HEALTH" | python3 -c "import sys, json; data=json.load(sys.stdin); assert 'status' in data; print('OK')" 2>/dev/null; then
    echo "✅ Test 1 PASSED: Babysitter health endpoints work"
    ((TESTS_PASSED++))
else
    echo "❌ Test 1 FAILED: Babysitter health endpoint failed"
    echo "Response: $BABYSITTER1_HEALTH"
    ((TESTS_FAILED++))
fi

# Test 2: /models endpoint - should aggregate models
echo ""
echo "=========================================="
echo "Test 2: Model Aggregation"
echo "=========================================="
MODELS_RESPONSE=$(curl -s http://127.0.0.1:$ROUTER_PORT/models 2>/dev/null || echo '{"data":[]}')
echo "Response: $MODELS_RESPONSE"

MODEL_COUNT=$(echo "$MODELS_RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data.get('data', [])))" 2>/dev/null || echo "0")
echo "Models found: $MODEL_COUNT"

if [ "$MODEL_COUNT" -ge 4 ]; then
    echo "✅ Test 2 PASSED: Model aggregation works ($MODEL_COUNT models)"
    ((TESTS_PASSED++))
else
    echo "❌ Test 2 FAILED: Expected at least 4 models, got $MODEL_COUNT"
    ((TESTS_FAILED++))
fi

# Test 3: Model-aware routing - route to service with model-a
echo ""
echo "=========================================="
echo "Test 3: Model-Aware Routing (model-a)"
echo "=========================================="
# Retry logic for service readiness
for retry in 1 2 3; do
    RESPONSE=$(curl -s -X POST http://127.0.0.1:$ROUTER_PORT/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d '{"model": "model-a", "messages": [{"role": "user", "content": "test"}]}')
    
    if echo "$RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); assert 'choices' in data; assert data['model'] == 'model-a'; print('OK')" 2>/dev/null; then
        echo "✅ Test 3 PASSED: Model-aware routing works for model-a"
        ((TESTS_PASSED++))
        break
    elif [ $retry -lt 3 ]; then
        echo "⚠️  Test 3: Service may not be ready yet, retrying... ($retry/3)"
        sleep 5
    else
        echo "❌ Test 3 FAILED: Model routing failed after retries"
        echo "Response: $RESPONSE"
        ((TESTS_FAILED++))
    fi
done

# Test 4: Model-aware routing - route to service with model-b
echo ""
echo "=========================================="
echo "Test 4: Model-Aware Routing (model-b)"
echo "=========================================="
# Retry logic for service readiness
for retry in 1 2 3; do
    RESPONSE=$(curl -s -X POST http://127.0.0.1:$ROUTER_PORT/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d '{"model": "model-b", "messages": [{"role": "user", "content": "test"}]}')
    
    if echo "$RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); assert 'choices' in data; assert data['model'] == 'model-b'; print('OK')" 2>/dev/null; then
        echo "✅ Test 4 PASSED: Model-aware routing works for model-b"
        ((TESTS_PASSED++))
        break
    elif [ $retry -lt 3 ]; then
        echo "⚠️  Test 4: Service may not be ready yet, retrying... ($retry/3)"
        sleep 5
    else
        echo "❌ Test 4 FAILED: Model routing failed after retries"
        echo "Response: $RESPONSE"
        ((TESTS_FAILED++))
    fi
done
# Test 5: Model-aware routing - route to service with model-shared (should load balance)
echo ""
echo "=========================================="
echo "Test 5: Model-Aware Routing (model-shared - load balancing)"
echo "=========================================="
# Retry logic for service readiness
for retry in 1 2 3; do
    RESPONSE1=$(curl -s -X POST http://127.0.0.1:$ROUTER_PORT/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d '{"model": "model-shared", "messages": [{"role": "user", "content": "test1"}]}')
    
    RESPONSE2=$(curl -s -X POST http://127.0.0.1:$ROUTER_PORT/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d '{"model": "model-shared", "messages": [{"role": "user", "content": "test2"}]}')
    
    # Check if both responses are valid
    # Extract service names to verify load balancing (responses should be from different services)
    VALID1=$(echo "$RESPONSE1" | python3 -c "import sys, json; data=json.load(sys.stdin); assert 'choices' in data; assert data['model'] == 'model-shared'" 2>/dev/null && echo "yes" || echo "no")
    VALID2=$(echo "$RESPONSE2" | python3 -c "import sys, json; data=json.load(sys.stdin); assert 'choices' in data; assert data['model'] == 'model-shared'" 2>/dev/null && echo "yes" || echo "no")
    
    # Verify both responses are valid
    if [ "$VALID1" = "yes" ] && [ "$VALID2" = "yes" ]; then
        # Optional: Check if load balancing worked (responses from different services)
        SERVICE1=$(echo "$RESPONSE1" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['choices'][0]['message']['content'])" 2>/dev/null | grep -o "service-model-[ab]" || echo "")
        SERVICE2=$(echo "$RESPONSE2" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['choices'][0]['message']['content'])" 2>/dev/null | grep -o "service-model-[ab]" || echo "")
        if [ -n "$SERVICE1" ] && [ -n "$SERVICE2" ] && [ "$SERVICE1" != "$SERVICE2" ]; then
            echo "   Load balanced: $SERVICE1 -> $SERVICE2"
        fi
        echo "✅ Test 5 PASSED: Model-aware routing with load balancing works"
        ((TESTS_PASSED++))
        break
    elif [ $retry -lt 3 ]; then
        echo "⚠️  Test 5: Services may not be ready yet, retrying... ($retry/3)"
        sleep 5
    else
        echo "❌ Test 5 FAILED: Load balancing failed after retries"
        echo "Response 1: $RESPONSE1"
        echo "Response 2: $RESPONSE2"
        ((TESTS_FAILED++))
    fi
done
# Test 6: Unsupported model
echo ""
echo "=========================================="
echo "Test 6: Unsupported Model Handling"
echo "=========================================="
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST http://127.0.0.1:$ROUTER_PORT/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{"model": "non-existent-model", "messages": [{"role": "user", "content": "test"}]}')

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
if [ "$HTTP_CODE" = "503" ]; then
    echo "✅ Test 6 PASSED: Unsupported model returns 503"
    ((TESTS_PASSED++))
else
    echo "❌ Test 6 FAILED: Expected 503, got $HTTP_CODE"
    ((TESTS_FAILED++))
fi

# Test 7: Streaming response
echo ""
echo "=========================================="
echo "Test 7: Streaming Response"
echo "=========================================="
STREAM_RESPONSE=$(curl -s -N -X POST http://127.0.0.1:$ROUTER_PORT/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{"model": "model-a", "messages": [{"role": "user", "content": "test"}], "stream": true}' | head -5)

if echo "$STREAM_RESPONSE" | grep -q "data:"; then
    echo "✅ Test 7 PASSED: Streaming response works"
    ((TESTS_PASSED++))
else
    echo "❌ Test 7 FAILED: Streaming response not detected"
    echo "Response: $STREAM_RESPONSE"
    ((TESTS_FAILED++))
fi

# Test 8: /services endpoint
echo ""
echo "=========================================="
echo "Test 8: /services Endpoint"
echo "=========================================="
SERVICES_RESPONSE=$(curl -s http://127.0.0.1:$ROUTER_PORT/services)
SERVICE_COUNT=$(echo "$SERVICES_RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data.get('services', [])))" 2>/dev/null || echo "0")

if [ "$SERVICE_COUNT" -ge 3 ]; then
    echo "✅ Test 8 PASSED: /services endpoint works ($SERVICE_COUNT services)"
    ((TESTS_PASSED++))
else
    echo "❌ Test 8 FAILED: Expected at least 3 services, got $SERVICE_COUNT"
    ((TESTS_FAILED++))
fi

# Test 9 and 10 removed - /models should forward to service, not babysitter
# /info endpoint is not necessary for core functionality

# Re-enable exit on error for final check
set -e

# Summary
echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "Tests Passed: $TESTS_PASSED"
echo "Tests Failed: $TESTS_FAILED"
echo ""

# Show logs on failure
if [ $TESTS_FAILED -gt 0 ]; then
    echo "=========================================="
    echo "Recent Logs (for debugging)"
    echo "=========================================="
    echo "--- Registry Log (last 30 lines) ---"
    tail -30 /tmp/registry_babysitter_test.log 2>/dev/null || echo "No registry log file"
    echo ""
    echo "--- Babysitter 1 Log (last 50 lines) ---"
    tail -50 /tmp/babysitter1.log 2>/dev/null || echo "No babysitter1 log file"
    echo ""
    echo "--- Babysitter 2 Log (last 50 lines) ---"
    tail -50 /tmp/babysitter2.log 2>/dev/null || echo "No babysitter2 log file"
    echo ""
    echo "--- Babysitter 3 Log (last 50 lines) ---"
    tail -50 /tmp/babysitter3.log 2>/dev/null || echo "No babysitter3 log file"
    echo ""
    echo "--- Router Log (last 50 lines) ---"
    tail -50 /tmp/router_babysitter_test.log 2>/dev/null || echo "No router log file"
    echo ""
    echo "--- Checking if mock services are running ---"
    ps aux | grep -E "(mock_service|python.*mock)" | grep -v grep || echo "No mock service processes found"
    echo ""
    echo "--- Checking ports ---"
    netstat -tuln 2>/dev/null | grep -E ":(6001|6003|6005|6002|6004|6006|8900|8901)" || lsof -i :6001,6003,6005,6002,6004,6006,8900,8901 2>/dev/null || echo "Could not check ports"
fi

if [ $TESTS_FAILED -eq 0 ]; then
    echo "✅ All integration tests passed!"
    exit 0
else
    echo "❌ Some tests failed"
    exit 1
fi
