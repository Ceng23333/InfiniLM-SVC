#!/usr/bin/env bash
# Start Server 2: 2 Babysitters (C, D) registering to Server 1

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment file if it exists (allows easy configuration)
if [ -f "${SCRIPT_DIR}/.env.server2" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/.env.server2"
elif [ -f "${SCRIPT_DIR}/.env" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/.env"
fi

IMAGE_NAME="${IMAGE_NAME:-infinilm-svc:demo}"
USE_HOST_NETWORK="${USE_HOST_NETWORK:-true}"

if [ $# -lt 2 ]; then
    echo "Usage: $0 <SERVER1_IP> <SERVER2_IP>"
    echo ""
    echo "  SERVER1_IP: IP address of Server 1 (where registry/router run)"
    echo "  SERVER2_IP: IP address of this server (Server 2)"
    exit 1
fi

SERVER1_IP="$1"
SERVER2_IP="$2"

echo "=========================================="
echo "Starting InfiniLM-SVC Server 2"
echo "=========================================="
echo "Server 1 IP (Registry/Router): ${SERVER1_IP}"
echo "Server 2 IP (This server): ${SERVER2_IP}"
echo "Components: Babysitter C, Babysitter D"
echo "Docker network: $([ "${USE_HOST_NETWORK}" = "true" ] && echo "host" || echo "bridge (-p ports)")"
echo ""

# Check if container already exists
if docker ps -a --format '{{.Names}}' | grep -q "^infinilm-svc-server2$"; then
    echo "⚠️  Container 'infinilm-svc-server2' already exists"
    read -p "Remove existing container? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker rm -f infinilm-svc-server2
    else
        echo "Aborted."
        exit 1
    fi
fi

# Verify Server 1 is reachable
echo "🔍 Checking connection to Server 1..."
if ! curl -s -f --connect-timeout 5 "http://${SERVER1_IP}:18000/health" > /dev/null 2>&1; then
    echo "❌ Error: Cannot reach Server 1 registry at http://${SERVER1_IP}:18000"
    echo "   Please ensure Server 1 is running and accessible."
    exit 1
fi
echo "✅ Server 1 registry is reachable"

# Start container
echo ""
echo "🚀 Starting Docker container..."
echo "  Setting BABYSITTER_HOST=${SERVER2_IP} for proper registration"
if [ "${USE_HOST_NETWORK}" = "true" ]; then
  docker run -d \
    --network host \
    --name infinilm-svc-server2 \
    -e LAUNCH_COMPONENTS=babysitter \
    -e REGISTRY_URL="http://${SERVER1_IP}:18000" \
    -e ROUTER_URL="http://${SERVER1_IP}:8000" \
    -e BABYSITTER_REGISTRY_URL="http://${SERVER1_IP}:18000" \
    -e BABYSITTER_ROUTER_URL="http://${SERVER1_IP}:8000" \
    -e BABYSITTER_HOST="${SERVER2_IP}" \
    -e BABYSITTER_CONFIGS="babysitter-c.toml babysitter-d.toml" \
    -v "${SCRIPT_DIR}/config:/app/config:ro" \
    -v "${SCRIPT_DIR}/mock_service.py:/app/mock_service.py:ro" \
    "${IMAGE_NAME}"
else
  docker run -d \
    --name infinilm-svc-server2 \
    -e LAUNCH_COMPONENTS=babysitter \
    -e REGISTRY_URL="http://${SERVER1_IP}:18000" \
    -e ROUTER_URL="http://${SERVER1_IP}:8000" \
    -e BABYSITTER_REGISTRY_URL="http://${SERVER1_IP}:18000" \
    -e BABYSITTER_ROUTER_URL="http://${SERVER1_IP}:8000" \
    -e BABYSITTER_HOST="${SERVER2_IP}" \
    -e BABYSITTER_CONFIGS="babysitter-c.toml babysitter-d.toml" \
    -p 8100:8100 -p 8101:8101 \
    -p 8200:8200 -p 8201:8201 \
    -v "${SCRIPT_DIR}/config:/app/config:ro" \
    -v "${SCRIPT_DIR}/mock_service.py:/app/mock_service.py:ro" \
    "${IMAGE_NAME}"
fi

echo ""
echo "✅ Server 2 started!"
echo ""
echo "Container: infinilm-svc-server2"
echo "Registry (remote): http://${SERVER1_IP}:18000"
echo "Router (remote): http://${SERVER1_IP}:8000"
echo ""
echo "View logs: docker logs -f infinilm-svc-server2"
echo "Stop: docker stop infinilm-svc-server2"
echo ""

# Wait a bit for services to start
echo "⏳ Waiting for services to start (15 seconds)..."
sleep 15

echo ""
echo "Server 2 setup complete!"
echo "Babysitters should register with Server 1 registry automatically."
