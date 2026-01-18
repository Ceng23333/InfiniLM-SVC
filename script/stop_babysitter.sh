#!/bin/bash
# Graceful stop script for Enhanced Babysitter

# Configuration
LOG_DIR="${LOG_DIR:-logs}"
PORT="${1:-}"  # Accept port as first argument

SERVICE_NAME="Enhanced Babysitter"
TIMEOUT=10  # Wait up to 10 seconds for graceful shutdown

# Function to stop a specific babysitter instance
stop_babysitter() {
    local pid_file=$1
    local port=$2

    if [ ! -f "${pid_file}" ]; then
        echo "✗ ${SERVICE_NAME} on port ${port} is not running (PID file not found: ${pid_file})"
        return 1
    fi

    local pid=$(cat "${pid_file}")

    if [ -z "${pid}" ]; then
        echo "✗ Invalid PID file: ${pid_file}"
        rm -f "${pid_file}"
        return 1
    fi

    # Check if process is running
    if ! ps -p ${pid} > /dev/null 2>&1; then
        echo "✗ ${SERVICE_NAME} on port ${port} is not running (process ${pid} not found)"
        rm -f "${pid_file}"
        return 1
    fi

    echo "Stopping ${SERVICE_NAME} on port ${port} (PID: ${pid})..."

    # Send SIGTERM for graceful shutdown
    kill ${pid} 2>/dev/null

    # Wait for graceful shutdown
    count=0
    while ps -p ${pid} > /dev/null 2>&1 && [ ${count} -lt ${TIMEOUT} ]; do
        sleep 1
        count=$((count + 1))
        echo -n "."
    done
    echo ""

    # Check if process is still running
    if ps -p ${pid} > /dev/null 2>&1; then
        echo "⚠ Process did not stop gracefully within ${TIMEOUT}s, sending SIGKILL..."
        kill -9 ${pid} 2>/dev/null
        sleep 1

        if ps -p ${pid} > /dev/null 2>&1; then
            echo "✗ Failed to stop ${SERVICE_NAME} on port ${port} (PID: ${pid})"
            return 1
        fi
    fi

    # Clean up PID file
    rm -f "${pid_file}"
    echo "✓ ${SERVICE_NAME} on port ${port} stopped successfully"
    return 0
}

# Main execution
if [ -n "${PORT}" ]; then
    # Stop specific instance
    PID_FILE="${LOG_DIR}/babysitter_${PORT}.pid"
    stop_babysitter "${PID_FILE}" "${PORT}"
    exit $?
else
    # Stop all instances
    echo "Stopping all ${SERVICE_NAME} instances..."

    if [ ! -d "${LOG_DIR}" ]; then
        echo "✗ Log directory not found: ${LOG_DIR}"
        exit 1
    fi

    stopped_count=0
    failed_count=0

    # Find all babysitter PID files
    for pid_file in "${LOG_DIR}"/babysitter_*.pid; do
        if [ -f "${pid_file}" ]; then
            # Extract port from filename (e.g., logs/babysitter_8000.pid -> 8000)
            port=$(basename "${pid_file}" | sed 's/babysitter_\([0-9]*\)\.pid/\1/')

            if stop_babysitter "${pid_file}" "${port}"; then
                stopped_count=$((stopped_count + 1))
            else
                failed_count=$((failed_count + 1))
            fi
            echo ""
        fi
    done

    if [ ${stopped_count} -eq 0 ] && [ ${failed_count} -eq 0 ]; then
        echo "No ${SERVICE_NAME} instances found"
        exit 1
    fi

    echo "Summary: ${stopped_count} stopped, ${failed_count} failed"

    if [ ${failed_count} -gt 0 ]; then
        exit 1
    fi
fi
