#!/bin/bash
# Graceful stop script for Service Registry

# Configuration (should match launch_registry.sh)
LOG_DIR="${LOG_DIR:-logs}"

PID_FILE="${LOG_DIR}/registry.pid"
SERVICE_NAME="Service Registry"
TIMEOUT=10  # Wait up to 10 seconds for graceful shutdown

# Function to stop the service
stop_service() {
    if [ ! -f "${PID_FILE}" ]; then
        echo "✗ ${SERVICE_NAME} is not running (PID file not found: ${PID_FILE})"
        exit 1
    fi

    PID=$(cat "${PID_FILE}")

    if [ -z "${PID}" ]; then
        echo "✗ Invalid PID file: ${PID_FILE}"
        rm -f "${PID_FILE}"
        exit 1
    fi

    # Check if process is running
    if ! ps -p ${PID} > /dev/null 2>&1; then
        echo "✗ ${SERVICE_NAME} is not running (process ${PID} not found)"
        rm -f "${PID_FILE}"
        exit 1
    fi

    echo "Stopping ${SERVICE_NAME} (PID: ${PID})..."

    # Send SIGTERM for graceful shutdown
    kill ${PID} 2>/dev/null

    # Wait for graceful shutdown
    count=0
    while ps -p ${PID} > /dev/null 2>&1 && [ ${count} -lt ${TIMEOUT} ]; do
        sleep 1
        count=$((count + 1))
        echo -n "."
    done
    echo ""

    # Check if process is still running
    if ps -p ${PID} > /dev/null 2>&1; then
        echo "⚠ Process did not stop gracefully within ${TIMEOUT}s, sending SIGKILL..."
        kill -9 ${PID} 2>/dev/null
        sleep 1

        if ps -p ${PID} > /dev/null 2>&1; then
            echo "✗ Failed to stop ${SERVICE_NAME} (PID: ${PID})"
            exit 1
        fi
    fi

    # Clean up PID file
    rm -f "${PID_FILE}"
    echo "✓ ${SERVICE_NAME} stopped successfully"
}

# Main execution
stop_service
