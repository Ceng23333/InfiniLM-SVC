#!/bin/bash
# Test script for proxy functionality

set -e

ROUTER_PORT=8888
TEST_CONFIG="config/deployment_configs/router_config.json"
ROUTER_BIN="rust/target/release/infini-router"

echo "=========================================="
echo "Testing Rust Router Proxy Functionality"
echo "=========================================="
echo ""

# Check if router binary exists
if [ ! -f "$ROUTER_BIN" ]; then
    echo "Error: Router binary not found. Please build it first:"
    echo "  cd rust && cargo build --release"
    exit 1
fi

# Start router in background
echo "Starting router on port $ROUTER_PORT..."
$ROUTER_BIN \
    --router-port $ROUTER_PORT \
    --static-services $TEST_CONFIG \
    > /tmp/router_test.log 2>&1 &
ROUTER_PID=$!

# Wait for router to start
sleep 2

# Check if router is running
if ! ps -p $ROUTER_PID > /dev/null; then
    echo "Error: Router failed to start"
    cat /tmp/router_test.log
    exit 1
fi

echo "✓ Router started (PID: $ROUTER_PID)"
echo ""

# Test 1: Health endpoint
echo "Test 1: Health endpoint"
echo "----------------------"
HEALTH_RESPONSE=$(curl -s http://localhost:$ROUTER_PORT/health)
echo "Response: $HEALTH_RESPONSE"
if echo "$HEALTH_RESPONSE" | grep -q "healthy"; then
    echo "✓ Health check passed"
else
    echo "✗ Health check failed"
fi
echo ""

# Test 2: Services endpoint
echo "Test 2: Services endpoint"
echo "-------------------------"
SERVICES_RESPONSE=$(curl -s http://localhost:$ROUTER_PORT/services)
echo "Response: $SERVICES_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$SERVICES_RESPONSE"
if echo "$SERVICES_RESPONSE" | grep -q "infinilm-backup1"; then
    echo "✓ Services endpoint passed"
else
    echo "✗ Services endpoint failed"
fi
echo ""

# Test 3: Stats endpoint
echo "Test 3: Stats endpoint"
echo "---------------------"
STATS_RESPONSE=$(curl -s http://localhost:$ROUTER_PORT/stats)
echo "Response: $STATS_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$STATS_RESPONSE"
if echo "$STATS_RESPONSE" | grep -q "total_services"; then
    echo "✓ Stats endpoint passed"
else
    echo "✗ Stats endpoint failed"
fi
echo ""

# Test 4: Proxy to non-existent service (should return 503)
echo "Test 4: Proxy to unavailable service"
echo "-------------------------------------"
PROXY_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" http://localhost:$ROUTER_PORT/v1/chat/completions 2>&1)
HTTP_CODE=$(echo "$PROXY_RESPONSE" | grep "HTTP_CODE" | cut -d: -f2)
BODY=$(echo "$PROXY_RESPONSE" | grep -v "HTTP_CODE")
echo "Response body: $BODY"
echo "HTTP status: $HTTP_CODE"
if [ "$HTTP_CODE" = "503" ]; then
    echo "✓ Proxy error handling passed (correctly returned 503)"
else
    echo "✗ Proxy error handling failed (expected 503, got $HTTP_CODE)"
fi
echo ""

# Test 5: Proxy with POST request
echo "Test 5: Proxy POST request"
echo "---------------------------"
POST_RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d '{"test": "data"}' \
    -w "\nHTTP_CODE:%{http_code}" \
    http://localhost:$ROUTER_PORT/v1/test 2>&1)
POST_HTTP_CODE=$(echo "$POST_RESPONSE" | grep "HTTP_CODE" | cut -d: -f2)
POST_BODY=$(echo "$POST_RESPONSE" | grep -v "HTTP_CODE")
echo "Response body: $POST_BODY"
echo "HTTP status: $POST_HTTP_CODE"
if [ "$POST_HTTP_CODE" = "503" ]; then
    echo "✓ POST proxy error handling passed"
else
    echo "✗ POST proxy error handling failed (expected 503, got $POST_HTTP_CODE)"
fi
echo ""

# Test 6: Check router logs for proxy attempts
echo "Test 6: Router logs"
echo "-------------------"
if grep -q "Proxying" /tmp/router_test.log; then
    echo "✓ Router logged proxy attempts"
    echo "Sample log entries:"
    grep "Proxying" /tmp/router_test.log | tail -3
else
    echo "⚠ No proxy log entries found"
fi
echo ""

# Cleanup
echo "Stopping router..."
kill $ROUTER_PID 2>/dev/null || true
wait $ROUTER_PID 2>/dev/null || true
sleep 1

echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "All basic functionality tests completed."
echo "Note: Full proxy testing requires a running backend service."
echo ""
