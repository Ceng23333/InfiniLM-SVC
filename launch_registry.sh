#!/bin/bash
#
# Quick launch script for InfiniLM Service Registry
# Edit the configuration variables below to customize the launch
#

# ============================================================================
# CONFIGURATION - Edit these variables as needed
# ============================================================================

# Registry port
REGISTRY_PORT=8081

# Health check interval (seconds)
HEALTH_INTERVAL=30

# Health check timeout (seconds)
HEALTH_TIMEOUT=5

# Cleanup interval (seconds)
CLEANUP_INTERVAL=60

# Python executable (use python3 if python is not available)
PYTHON_CMD=python3

# Script directory (auto-detected, or set manually)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Log directory
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/registry_$(date +%y%m%d%H%M).log"

# ============================================================================
# SCRIPT - Do not edit below unless you know what you're doing
# ============================================================================

# Create log directory if it doesn't exist
mkdir -p "${LOG_DIR}"

# Change to script directory
cd "${SCRIPT_DIR}" || exit 1

# Check if Python script exists
if [ ! -f "service_registry.py" ]; then
    echo "Error: service_registry.py not found in ${SCRIPT_DIR}"
    exit 1
fi

# Check if Python is available
if ! command -v "${PYTHON_CMD}" &> /dev/null; then
    echo "Error: ${PYTHON_CMD} not found. Please install Python 3."
    exit 1
fi

# Build command
CMD="${PYTHON_CMD} service_registry.py \
    --port ${REGISTRY_PORT} \
    --health-interval ${HEALTH_INTERVAL} \
    --health-timeout ${HEALTH_TIMEOUT} \
    --cleanup-interval ${CLEANUP_INTERVAL}"

# Display launch information
echo "=========================================="
echo "Launching InfiniLM Service Registry"
echo "=========================================="
echo "Port: ${REGISTRY_PORT}"
echo "Health Interval: ${HEALTH_INTERVAL}s"
echo "Health Timeout: ${HEALTH_TIMEOUT}s"
echo "Cleanup Interval: ${CLEANUP_INTERVAL}s"
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
    echo "✓ Service Registry started successfully!"
    echo "  PID: ${PID}"
    echo "  Log: ${LOG_FILE}"
    echo "  URL: http://localhost:${REGISTRY_PORT}"
    echo ""
    echo "Management commands:"
    echo "  Stop service:    kill ${PID}"
    echo "  Kill forcefully: kill -9 ${PID}"
    echo "  View logs:       tail -f ${LOG_FILE}"
    echo ""
    echo "Example commands to check status:"
    echo "  curl http://localhost:${REGISTRY_PORT}/health"
    echo "  curl http://localhost:${REGISTRY_PORT}/services"
    echo "  curl http://localhost:${REGISTRY_PORT}/stats"
else
    echo "✗ Failed to start Service Registry"
    echo "  Check log file for details: ${LOG_FILE}"
    exit 1
fi
