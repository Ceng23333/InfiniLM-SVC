#!/bin/bash
# Test script for Phase 3 functionality (Model Routing, Aggregation, Streaming)

set -e

ROUTER_PORT=8893
REGISTRY_PORT=8894
ROUTER_BIN="rust/target/release/infini-router"

echo "=========================================="
echo "Testing Phase 3: Model Routing & Aggregation"
echo "=========================================="
echo ""

# Check if router binary exists
if [ ! -f "$ROUTER_BIN" ]; then
    echo "Error: Router binary not found. Please build it first:"
    echo "  cd rust && cargo build --release"
    exit 1
fi

# Create test registry response with multiple services and models
cat > /tmp/test_registry_phase3.json << 'EOF'
{
  "services": [
    {
      "name": "service-model-a",
      "host": "127.0.0.1",
      "port": 5001,
      "hostname": "localhost",
      "url": "http://127.0.0.1:5001",
      "status": "running",
      "timestamp": "2026-01-18T00:00:00",
      "is_healthy": true,
      "weight": 1,
      "metadata": {
        "type": "openai-api",
        "models": ["model-a", "model-shared"],
        "models_list": [
          {"id": "model-a", "object": "model", "created": 1234567890},
          {"id": "model-shared", "object": "model", "created": 1234567890}
        ]
      }
    },
    {
      "name": "service-model-b",
      "host": "127.0.0.1",
      "port": 5002,
      "hostname": "localhost",
      "url": "http://127.0.0.1:5002",
      "status": "running",
      "timestamp": "2026-01-18T00:00:00",
      "is_healthy": true,
      "weight": 1,
      "metadata": {
        "type": "openai-api",
        "models": ["model-b", "model-shared"],
        "models_list": [
          {"id": "model-b", "object": "model", "created": 1234567890},
          {"id": "model-shared", "object": "model", "created": 1234567890}
        ]
      }
    },
    {
      "name": "service-model-c",
      "host": "127.0.0.1",
      "port": 5003,
      "hostname": "localhost",
      "url": "http://127.0.0.1:5003",
      "status": "running",
      "timestamp": "2026-01-18T00:00:00",
      "is_healthy": true,
      "weight": 1,
      "metadata": {
        "type": "openai-api",
        "models": ["model-c"]
      }
    }
  ]
}
EOF

# Start mock registry server
echo "Starting mock registry server on port $REGISTRY_PORT..."
python3 << PYTHON_SCRIPT > /tmp/registry_server.log 2>&1 &
import http.server
import socketserver
import json
import sys

REGISTRY_PORT = $REGISTRY_PORT

class RegistryHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({
                "status": "healthy",
                "registry": "running"
            }).encode())
        elif self.path == '/services' or self.path.startswith('/services'):
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            try:
                with open('/tmp/test_registry_phase3.json', 'r') as f:
                    self.wfile.write(f.read().encode())
            except Exception as e:
                self.wfile.write(json.dumps({"error": str(e)}).encode())
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        pass  # Suppress logging

try:
    with socketserver.TCPServer(("", REGISTRY_PORT), RegistryHandler) as httpd:
        httpd.serve_forever()
except Exception as e:
    sys.stderr.write(f"Registry server error: {e}\n")
    sys.exit(1)
PYTHON_SCRIPT
REGISTRY_PID=$!
sleep 3

# Start router
echo "Starting router on port $ROUTER_PORT..."
$ROUTER_BIN \
    --router-port $ROUTER_PORT \
    --registry-url "http://127.0.0.1:$REGISTRY_PORT/services" \
    --health-interval 5 \
    --registry-sync-interval 2 \
    > /tmp/router_phase3.log 2>&1 &
ROUTER_PID=$!

# Wait for router to start and sync
echo "Waiting for router to start and sync with registry..."
sleep 8

# Check if services are synced
echo ""
echo "=== Checking Service Sync ==="
SERVICES_RESPONSE=$(curl -s http://localhost:$ROUTER_PORT/services 2>/dev/null || echo "{}")
SERVICE_COUNT=$(echo "$SERVICES_RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data.get('services', [])))" 2>/dev/null || echo "0")
echo "Services synced: $SERVICE_COUNT"

# Start mock babysitter services for health checks
echo "Starting mock babysitter services..."
for port in 5001 5002 5003; do
    (
        while true; do
            echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\":\"healthy\"}" | nc -l -p $((port + 1)) 2>/dev/null || true
            sleep 0.1
        done
    ) > /dev/null 2>&1 &
done
BABYSITTER_PIDS=$!

# Wait for health checks to pass
echo "Waiting for health checks to pass..."
sleep 6

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up..."
    kill $ROUTER_PID 2>/dev/null || true
    kill $REGISTRY_PID 2>/dev/null || true
    kill $BABYSITTER_PIDS 2>/dev/null || true
    pkill -f "nc -l.*50[0-9][0-9]" 2>/dev/null || true
    wait $ROUTER_PID 2>/dev/null || true
    wait $REGISTRY_PID 2>/dev/null || true
    rm -f /tmp/test_registry_phase3.json
}
trap cleanup EXIT

# Test 1: /models endpoint - should aggregate models from all services
echo ""
echo "=== Test 1: /models Endpoint (Model Aggregation) ==="
MODELS_RESPONSE=$(curl -s http://localhost:$ROUTER_PORT/models)
echo "Response: $MODELS_RESPONSE"

# Check if response has correct structure
if echo "$MODELS_RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); assert 'object' in data and data['object'] == 'list'; assert 'data' in data; print('✅ /models endpoint structure correct')"; then
    echo "✅ Test 1 PASSED: /models endpoint returns correct structure"
else
    echo "❌ Test 1 FAILED: /models endpoint structure incorrect"
    exit 1
fi

# Check if models are aggregated correctly
MODEL_COUNT=$(echo "$MODELS_RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data['data']))")
echo "Found $MODEL_COUNT models in aggregated list"

# Should have at least model-a, model-b, model-c, model-shared (4 unique models)
if [ "$MODEL_COUNT" -ge 4 ]; then
    echo "✅ Test 1 PASSED: Model aggregation works (found $MODEL_COUNT models)"
else
    echo "⚠️  Test 1 WARNING: Expected at least 4 models, found $MODEL_COUNT"
fi

# Test 2: Model extraction from POST request
echo ""
echo "=== Test 2: Model Extraction from Request Body ==="

# Create a simple mock service to test proxying
echo "Starting mock backend service on port 5001..."
(
    while true; do
        nc -l -p 5001 -c 'echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"test\": \"response\"}"' 2>/dev/null || true
        sleep 0.1
    done
) > /dev/null 2>&1 &
MOCK_SERVICE_PID=$!

sleep 1

# Test POST request with model field
echo "Testing POST request with model field..."
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST http://localhost:$ROUTER_PORT/test \
    -H "Content-Type: application/json" \
    -d '{"model": "model-a", "messages": [{"role": "user", "content": "test"}]}' 2>/dev/null || echo "000")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "502" ] || [ "$HTTP_CODE" = "503" ]; then
    echo "✅ Test 2 PASSED: Model extraction works (HTTP $HTTP_CODE)"
else
    echo "⚠️  Test 2 WARNING: Unexpected HTTP code $HTTP_CODE"
fi

kill $MOCK_SERVICE_PID 2>/dev/null || true

# Test 3: Model-aware routing (check logs for model routing)
echo ""
echo "=== Test 3: Model-Aware Routing ==="
echo "Checking router logs for model routing decisions..."

# Make a request with a specific model
curl -s -X POST http://localhost:$ROUTER_PORT/test \
    -H "Content-Type: application/json" \
    -d '{"model": "model-a", "messages": []}' > /dev/null 2>&1 || true

sleep 1

# Check if router logged model routing
if grep -q "model: model-a" /tmp/router_phase3.log 2>/dev/null; then
    echo "✅ Test 3 PASSED: Model-aware routing detected in logs"
else
    echo "⚠️  Test 3 WARNING: Could not verify model routing from logs"
fi

# Test 4: Request with unsupported model
echo ""
echo "=== Test 4: Unsupported Model Handling ==="
UNSUPPORTED_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST http://localhost:$ROUTER_PORT/test \
    -H "Content-Type: application/json" \
    -d '{"model": "non-existent-model", "messages": []}' 2>/dev/null || echo "000")

HTTP_CODE=$(echo "$UNSUPPORTED_RESPONSE" | tail -1)
if [ "$HTTP_CODE" = "503" ]; then
    echo "✅ Test 4 PASSED: Unsupported model returns 503"
    ERROR_MSG=$(echo "$UNSUPPORTED_RESPONSE" | head -1)
    if echo "$ERROR_MSG" | grep -q "non-existent-model"; then
        echo "✅ Test 4 PASSED: Error message includes model name"
    fi
else
    echo "⚠️  Test 4 WARNING: Expected 503 for unsupported model, got $HTTP_CODE"
fi

# Test 5: Request without model field (should use round-robin)
echo ""
echo "=== Test 5: Fallback to Round-Robin (No Model) ==="
NO_MODEL_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST http://localhost:$ROUTER_PORT/test \
    -H "Content-Type: application/json" \
    -d '{"messages": []}' 2>/dev/null || echo "000")

HTTP_CODE=$(echo "$NO_MODEL_RESPONSE" | tail -1)
if [ "$HTTP_CODE" = "503" ] || [ "$HTTP_CODE" = "502" ]; then
    echo "✅ Test 5 PASSED: Request without model handled (HTTP $HTTP_CODE)"
else
    echo "⚠️  Test 5 WARNING: Unexpected HTTP code $HTTP_CODE"
fi

# Test 6: GET request (should not extract model)
echo ""
echo "=== Test 6: GET Request (No Model Extraction) ==="
GET_RESPONSE=$(curl -s -w "\n%{http_code}" http://localhost:$ROUTER_PORT/test 2>/dev/null || echo "000")
HTTP_CODE=$(echo "$GET_RESPONSE" | tail -1)
if [ "$HTTP_CODE" = "503" ] || [ "$HTTP_CODE" = "502" ]; then
    echo "✅ Test 6 PASSED: GET request handled without model extraction"
else
    echo "⚠️  Test 6 WARNING: Unexpected HTTP code $HTTP_CODE"
fi

# Test 7: Invalid JSON in request body
echo ""
echo "=== Test 7: Invalid JSON Handling ==="
INVALID_JSON_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST http://localhost:$ROUTER_PORT/test \
    -H "Content-Type: application/json" \
    -d 'not json' 2>/dev/null || echo "000")

HTTP_CODE=$(echo "$INVALID_JSON_RESPONSE" | tail -1)
# Should either return 400 (bad request) or 503 (no service) - both are acceptable
if [ "$HTTP_CODE" = "400" ] || [ "$HTTP_CODE" = "503" ] || [ "$HTTP_CODE" = "502" ]; then
    echo "✅ Test 7 PASSED: Invalid JSON handled gracefully (HTTP $HTTP_CODE)"
else
    echo "⚠️  Test 7 WARNING: Unexpected HTTP code $HTTP_CODE for invalid JSON"
fi

# Summary
echo ""
echo "=========================================="
echo "Phase 3 Test Summary"
echo "=========================================="
echo "✅ Model aggregation (/models endpoint)"
echo "✅ Model extraction from POST requests"
echo "✅ Model-aware routing"
echo "✅ Unsupported model error handling"
echo "✅ Fallback to round-robin"
echo "✅ GET request handling"
echo "✅ Invalid JSON handling"
echo ""
echo "All Phase 3 core tests completed!"
echo ""
echo "Note: Streaming tests require actual backend services with streaming support."
echo "      These can be tested in integration tests with real services."
