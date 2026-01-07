#!/bin/bash
#
# Quick launch script for InfiniLM Distributed Router
# Edit the configuration variables below to customize the launch
#

# ============================================================================
# CONFIGURATION - Edit these variables as needed
# ============================================================================

# Router port
ROUTER_PORT=8080

# Registry URL (set to empty string to disable registry integration)
REGISTRY_URL="http://localhost:8081"

# Static services JSON file (optional, leave empty to disable)
STATIC_SERVICES_FILE=""

# Health check interval (seconds)
HEALTH_INTERVAL=30

# Health check timeout (seconds)
HEALTH_TIMEOUT=5

# Max errors before marking service unhealthy
MAX_ERRORS=3

# Registry sync interval (seconds)
REGISTRY_SYNC_INTERVAL=10

# Python executable (use python3 if python is not available)
PYTHON_CMD=python3

# Script directory (auto-detected, or set manually)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Log directory
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/router_$(date +%y%m%d%H%M).log"

# ============================================================================
# SCRIPT - Do not edit below unless you know what you're doing
# ============================================================================

# Create log directory if it doesn't exist
mkdir -p "${LOG_DIR}"

# Change to script directory
cd "${SCRIPT_DIR}" || exit 1

# Check if Python script exists
if [ ! -f "distributed_router.py" ]; then
    echo "Error: distributed_router.py not found in ${SCRIPT_DIR}"
    exit 1
fi

# Check if Python is available
if ! command -v "${PYTHON_CMD}" &> /dev/null; then
    echo "Error: ${PYTHON_CMD} not found. Please install Python 3."
    exit 1
fi

# Build command
CMD="${PYTHON_CMD} distributed_router.py \
    --router-port ${ROUTER_PORT} \
    --health-interval ${HEALTH_INTERVAL} \
    --health-timeout ${HEALTH_TIMEOUT} \
    --max-errors ${MAX_ERRORS} \
    --registry-sync-interval ${REGISTRY_SYNC_INTERVAL}"

# Add registry URL if specified
if [ -n "${REGISTRY_URL}" ]; then
    CMD="${CMD} --registry-url ${REGISTRY_URL}"
fi

# Add static services file if specified
if [ -n "${STATIC_SERVICES_FILE}" ] && [ -f "${STATIC_SERVICES_FILE}" ]; then
    CMD="${CMD} --static-services ${STATIC_SERVICES_FILE}"
fi

# Display launch information
echo "=========================================="
echo "Launching InfiniLM Distributed Router"
echo "=========================================="
echo "Router Port: ${ROUTER_PORT}"
echo "Registry URL: ${REGISTRY_URL:-'Not configured'}"
echo "Static Services: ${STATIC_SERVICES_FILE:-'Not configured'}"
echo "Health Interval: ${HEALTH_INTERVAL}s"
echo "Health Timeout: ${HEALTH_TIMEOUT}s"
echo "Max Errors: ${MAX_ERRORS}"
echo "Registry Sync Interval: ${REGISTRY_SYNC_INTERVAL}s"
echo "Log file: ${LOG_FILE}"
echo "=========================================="
echo ""

# Launch with nohup
nohup ${CMD} >> "${LOG_FILE}" 2>&1 &

# Get PID
PID=$!

# Wait a moment to check if process started successfully
sleep 2

# Check if process is still running
if ps -p ${PID} > /dev/null 2>&1; then
    echo "✓ Distributed Router started successfully!"
    echo "  PID: ${PID}"
    echo "  Log: ${LOG_FILE}"
    echo "  URL: http://localhost:${ROUTER_PORT}"
    echo ""
    echo "Management commands:"
    echo "  Stop service:    kill ${PID}"
    echo "  Kill forcefully: kill -9 ${PID}"
    echo "  View logs:       tail -f ${LOG_FILE}"
    echo ""
    echo "Example commands to check status:"
    echo "  curl http://localhost:${ROUTER_PORT}/health"
    echo "  curl http://localhost:${ROUTER_PORT}/services"
    echo "  curl http://localhost:${ROUTER_PORT}/stats"
else
    echo "✗ Failed to start Distributed Router"
    echo "  Check log file for details: ${LOG_FILE}"
    exit 1
fi
