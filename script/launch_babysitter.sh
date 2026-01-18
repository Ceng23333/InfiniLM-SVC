#!/bin/bash
#
# Quick launch script for InfiniLM Enhanced Babysitter
# Edit the configuration variables below to customize the launch
#

# ============================================================================
# CONFIGURATION - Edit these variables as needed
# ============================================================================

# Service Configuration
HOST="localhost"
PORT=8100
SERVICE_NAME=""  # Leave empty for auto-generated name
SERVICE_TYPE="InfiniLM"  # Options: "InfiniLM" or "InfiniLM-Rust"

# Registry and Router URLs (set to empty string to disable)
REGISTRY_URL="http://localhost:18000"
ROUTER_URL="http://localhost:8000"  # Optional, leave empty if not needed

# Babysitter Configuration
MAX_RESTARTS=10000
RESTART_DELAY=5
HEARTBEAT_INTERVAL=30

# InfiniLM Server Configuration (for SERVICE_TYPE="InfiniLM")
MODEL_PATH="/models/9g_8b_thinking"  # Required for InfiniLM
MODEL_NAME=""  # Model name for /models endpoint (leave empty to use directory name from MODEL_PATH, like vLLM/llama.cpp)
LAUNCH_SCRIPT=""  # Path to launch_server.py (leave empty for auto-detect)
DEV="metax"  # Device type: nvidia, metax, etc.
NDEV=1  # Number of devices
MAX_BATCH=3  # Max batch size
MAX_TOKENS=""  # Optional, leave empty for default
AWQ=false  # Set to true to use AWQ quantized model
REQUEST_TIMEOUT=30  # Request timeout in seconds
MAX_CONCURRENCY="5"  # Max concurrent requests (leave empty for unlimited)

# Environment Variables
HPCC_VISIBLE_DEVICES="1"  # HPCC visible devices (e.g., "0", "0,1", "0,1,2")
# CUDA_VISIBLE_DEVICES="0"  # CUDA visible devices (uncomment for future use, e.g., "0", "0,1", "0,1,2")

# InfiniLM-Rust Configuration (for SERVICE_TYPE="InfiniLM-Rust")
CONFIG_FILE=""  # Required for InfiniLM-Rust, e.g., "/path/to/config.toml"

# Python executable (use python3 if python is not available)
PYTHON_CMD=python3

# Script directory (auto-detected, or set manually)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Log directory
LOG_DIR="${PROJECT_ROOT}/logs"
LOG_FILE="${LOG_DIR}/babysitter_${PORT}_$(date +%y%m%d%H%M).log"
PID_FILE="${LOG_DIR}/babysitter_${PORT}.pid"

# ============================================================================
# SCRIPT - Do not edit below unless you know what you're doing
# ============================================================================

# Create log directory if it doesn't exist
mkdir -p "${LOG_DIR}"

# Change to project root directory
cd "${PROJECT_ROOT}" || exit 1

# Check if Python script exists
if [ ! -f "python/enhanced_babysitter.py" ]; then
    echo "Error: python/enhanced_babysitter.py not found in ${PROJECT_ROOT}"
    exit 1
fi

# Check if Python is available
if ! command -v "${PYTHON_CMD}" &> /dev/null; then
    echo "Error: ${PYTHON_CMD} not found. Please install Python 3."
    exit 1
fi

# Validate configuration based on service type
if [ "${SERVICE_TYPE}" = "InfiniLM" ]; then
    if [ -z "${MODEL_PATH}" ] || [ ! -d "${MODEL_PATH}" ]; then
        echo "Error: MODEL_PATH must be set and exist for SERVICE_TYPE=InfiniLM"
        echo "  Current value: ${MODEL_PATH}"
        exit 1
    fi
    PATH_ARG="${MODEL_PATH}"
elif [ "${SERVICE_TYPE}" = "InfiniLM-Rust" ]; then
    if [ -z "${CONFIG_FILE}" ] || [ ! -f "${CONFIG_FILE}" ]; then
        echo "Error: CONFIG_FILE must be set and exist for SERVICE_TYPE=InfiniLM-Rust"
        echo "  Current value: ${CONFIG_FILE}"
        exit 1
    fi
    PATH_ARG="${CONFIG_FILE}"
else
    echo "Error: Invalid SERVICE_TYPE. Must be 'InfiniLM' or 'InfiniLM-Rust'"
    exit 1
fi

# Build command array to properly handle paths with spaces (no quotes in values)
CMD_ARGS=(
    "${PYTHON_CMD}"
    "python/enhanced_babysitter.py"
    "--host" "${HOST}"
    "--port" "${PORT}"
    "--service-type" "${SERVICE_TYPE}"
    "--path" "${PATH_ARG}"
    "--max-restarts" "${MAX_RESTARTS}"
    "--restart-delay" "${RESTART_DELAY}"
    "--heartbeat-interval" "${HEARTBEAT_INTERVAL}"
)

# Add service name if specified
if [ -n "${SERVICE_NAME}" ]; then
    CMD_ARGS+=("--name" "${SERVICE_NAME}")
fi

# Add registry URL if specified
if [ -n "${REGISTRY_URL}" ]; then
    CMD_ARGS+=("--registry" "${REGISTRY_URL}")
fi

# Add router URL if specified
if [ -n "${ROUTER_URL}" ]; then
    CMD_ARGS+=("--router" "${ROUTER_URL}")
fi

# Add InfiniLM-specific arguments
if [ "${SERVICE_TYPE}" = "InfiniLM" ]; then
    CMD_ARGS+=("--dev" "${DEV}" "--ndev" "${NDEV}" "--max-batch" "${MAX_BATCH}" "--request-timeout" "${REQUEST_TIMEOUT}")

    if [ -n "${MAX_CONCURRENCY}" ]; then
        CMD_ARGS+=("--max-concurrency" "${MAX_CONCURRENCY}")
    fi

    if [ -n "${LAUNCH_SCRIPT}" ]; then
        CMD_ARGS+=("--launch-script" "${LAUNCH_SCRIPT}")
    fi

    if [ -n "${MODEL_NAME}" ]; then
        CMD_ARGS+=("--model-name" "${MODEL_NAME}")
    fi

    if [ -n "${MAX_TOKENS}" ]; then
        CMD_ARGS+=("--max-tokens" "${MAX_TOKENS}")
    fi

    if [ "${AWQ}" = "true" ]; then
        CMD_ARGS+=("--awq")
    fi
fi

# Display launch information
echo "=========================================="
echo "Launching InfiniLM Enhanced Babysitter"
echo "=========================================="
echo "Service Type: ${SERVICE_TYPE}"
echo "Host: ${HOST}"
echo "Port: ${PORT}"
echo "Service Name: ${SERVICE_NAME:-'Auto-generated'}"
echo "Registry URL: ${REGISTRY_URL:-'Not configured'}"
echo "Router URL: ${ROUTER_URL:-'Not configured'}"
echo "Max Restarts: ${MAX_RESTARTS}"
echo "Restart Delay: ${RESTART_DELAY}s"
echo "Heartbeat Interval: ${HEARTBEAT_INTERVAL}s"
if [ "${SERVICE_TYPE}" = "InfiniLM" ]; then
    echo "Model Path: ${MODEL_PATH}"
    echo "Model Name: ${MODEL_NAME:-'Auto-detect'}"
    echo "Launch Script: ${LAUNCH_SCRIPT:-'Auto-detect'}"
    echo "Device: ${DEV}"
    echo "Number of Devices: ${NDEV}"
    echo "Max Batch: ${MAX_BATCH}"
    echo "Request Timeout: ${REQUEST_TIMEOUT}s"
    echo "Max Concurrency: ${MAX_CONCURRENCY:-'Unlimited'}"
elif [ "${SERVICE_TYPE}" = "InfiniLM-Rust" ]; then
    echo "Config File: ${CONFIG_FILE}"
fi
echo "Log file: ${LOG_FILE}"
echo "Environment Variables:"
echo "  HPCC_VISIBLE_DEVICES: ${HPCC_VISIBLE_DEVICES}"
if [ -n "${CUDA_VISIBLE_DEVICES:-}" ]; then
    echo "  CUDA_VISIBLE_DEVICES: ${CUDA_VISIBLE_DEVICES}"
fi
echo "=========================================="
echo ""

# Export environment variables
export HPCC_VISIBLE_DEVICES
# Uncomment the following line when CUDA_VISIBLE_DEVICES is needed
# export CUDA_VISIBLE_DEVICES

# Launch with nohup - use array to properly handle arguments
# Environment variables are inherited by the nohup process
nohup "${CMD_ARGS[@]}" >> "${LOG_FILE}" 2>&1 &

# Get PID
PID=$!

# Wait a moment to check if process started successfully
sleep 2

# Check if process is still running
if ps -p ${PID} > /dev/null 2>&1; then
    # Write PID to file
    echo ${PID} > "${PID_FILE}"
    echo "✓ Enhanced Babysitter started successfully!"
    echo "  PID: ${PID}"
    echo "  PID file: ${PID_FILE}"
    echo "  Log: ${LOG_FILE}"
    echo "  Service URL: http://${HOST}:${PORT}"
    echo "  Babysitter URL: http://${HOST}:$((PORT + 1))"
    echo ""
    echo "Management commands:"
    echo "  Stop service:    kill \$(cat ${PID_FILE})"
    echo "  Kill forcefully: kill -9 \$(cat ${PID_FILE})"
    echo "  View logs:       tail -f ${LOG_FILE}"
    echo ""
    echo "Example commands to check status:"
    echo "  # Check babysitter health"
    echo "  curl http://${HOST}:$((PORT + 1))/health"
    echo "  curl http://${HOST}:$((PORT + 1))/info"
    echo "  # Check InfiniLM server (if running)"
    echo "  curl http://${HOST}:${PORT}/models"
    echo "  # Test OpenAI API endpoint"
    echo "  curl -X POST http://${HOST}:${PORT}/chat/completions \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"model\":\"test\",\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}'"
else
    echo "✗ Failed to start Enhanced Babysitter"
    echo "  Check log file for details: ${LOG_FILE}"
    # Remove PID file if process failed to start
    rm -f "${PID_FILE}"
    exit 1
fi
