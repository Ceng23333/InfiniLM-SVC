#!/usr/bin/env bash
# Start Server 1: Registry, Router, and 2 Babysitters (A, B)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER1_IP="${1:-localhost}"
IMAGE_NAME="${IMAGE_NAME:-infinilm-svc:demo}"

echo "=========================================="
echo "Starting InfiniLM-SVC Server 1"
echo "=========================================="
echo "Server IP: ${SERVER1_IP}"
echo "Components: Registry, Router, Babysitter A, Babysitter B"
echo ""

# Check if container already exists
if docker ps -a --format '{{.Names}}' | grep -q "^infinilm-svc-server1$"; then
    echo "⚠️  Container 'infinilm-svc-server1' already exists"
    read -p "Remove existing container? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker rm -f infinilm-svc-server1
    else
        echo "Aborted."
        exit 1
    fi
fi

# Start container
echo "🚀 Starting Docker container..."
docker run -d \
  --name infinilm-svc-server1 \
  -e LAUNCH_COMPONENTS=all \
  -e REGISTRY_PORT=18000 \
  -e ROUTER_PORT=8000 \
  -e BABYSITTER_CONFIGS="config/babysitter-a.toml config/babysitter-b.toml" \
  -p 18000:18000 \
  -p 8000:8000 \
  -p 8100:8100 -p 8101:8101 \
  -p 8200:8200 -p 8201:8201 \
  -v "${SCRIPT_DIR}/config:/app/config:ro" \
  -v "${SCRIPT_DIR}/mock_service.py:/app/mock_service.py:ro" \
  "${IMAGE_NAME}"

echo ""
echo "✅ Server 1 started!"
echo ""
echo "Container: infinilm-svc-server1"
echo "Registry: http://${SERVER1_IP}:18000"
echo "Router: http://${SERVER1_IP}:8000"
echo ""
echo "View logs: docker logs -f infinilm-svc-server1"
echo "Stop: docker stop infinilm-svc-server1"
echo ""

# Wait a bit for services to start
echo "⏳ Waiting for services to start (10 seconds)..."
sleep 10

# Check health
echo ""
echo "Checking service health..."
if curl -s -f "http://${SERVER1_IP}:18000/health" > /dev/null; then
    echo "✅ Registry is healthy"
else
    echo "⚠️  Registry health check failed (may still be starting)"
fi

if curl -s -f "http://${SERVER1_IP}:8000/health" > /dev/null; then
    echo "✅ Router is healthy"
else
    echo "⚠️  Router health check failed (may still be starting)"
fi

echo ""
echo "Server 1 setup complete!"
echo "Use this IP for Server 2: ${SERVER1_IP}"
