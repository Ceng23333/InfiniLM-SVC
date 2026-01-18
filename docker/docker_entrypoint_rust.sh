#!/usr/bin/env bash
# Docker entrypoint script for InfiniLM-SVC (Rust version)
# Launches all services and handles graceful shutdown on container stop
#
# Configuration:
#   - Set environment variables to configure services
#   - Babysitter configs via BABYSITTER_CONFIGS (space-separated paths)
#   - All configuration can be overridden via environment variables

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}" || exit 1

echo "========================================"
echo "InfiniLM-SVC Docker Entrypoint (Rust)"
echo "========================================"
echo "Starting all services..."
echo ""

# Ensure binaries are built (if not already)
if [ "${BUILD_ON_STARTUP:-false}" = "true" ]; then
    echo "Building Rust binaries..."
    cd "${PROJECT_ROOT}/rust" || exit 1
    cargo build --release --bin infini-registry --bin infini-router --bin infini-babysitter
    cd "${PROJECT_ROOT}" || exit 1
    echo "Build complete."
    echo ""
fi

# Convert BABYSITTER_CONFIGS from space-separated to array if needed
if [ -n "${BABYSITTER_CONFIGS:-}" ] && [ "${BABYSITTER_CONFIGS}" != "()" ]; then
    # If it's already an array format, use it; otherwise convert from space-separated
    if [[ "${BABYSITTER_CONFIGS}" != *"("* ]]; then
        # Convert space-separated to bash array
        read -ra BABYSITTER_CONFIGS_ARRAY <<< "${BABYSITTER_CONFIGS}"
        export BABYSITTER_CONFIGS=("${BABYSITTER_CONFIGS_ARRAY[@]}")
    fi
fi

# Launch all services using the Rust launch script
if [ -f "${SCRIPT_DIR}/../script/launch_all_rust.sh" ]; then
    bash "${SCRIPT_DIR}/../script/launch_all_rust.sh"
else
    echo "Error: launch_all_rust.sh not found"
    exit 1
fi

# Set up signal handlers for graceful shutdown
# SIGTERM is sent by 'docker stop'
# SIGINT is sent by Ctrl+C (docker run -it)
cleanup() {
    echo ""
    echo "[entrypoint] Received shutdown signal, stopping all services..."
    
    # Stop all services gracefully
    if [ -f "${SCRIPT_DIR}/../script/stop_all.sh" ]; then
        bash "${SCRIPT_DIR}/../script/stop_all.sh"
    else
        # Fallback: kill processes by PID files
        LOG_DIR="${PROJECT_ROOT}/logs"
        for pid_file in "${LOG_DIR}"/*.pid; do
            if [ -f "${pid_file}" ]; then
                pid=$(cat "${pid_file}" 2>/dev/null)
                if [ -n "${pid}" ] && ps -p ${pid} > /dev/null 2>&1; then
                    echo "  Stopping process ${pid}..."
                    kill ${pid} 2>/dev/null || true
                fi
            fi
        done
        sleep 2
        # Force kill any remaining
        pkill -9 -f "infini-router" 2>/dev/null || true
        pkill -9 -f "infini-babysitter" 2>/dev/null || true
        pkill -9 -f "infini-registry" 2>/dev/null || true
    fi
    
    echo "[entrypoint] All services stopped. Exiting."
    exit 0
}

trap cleanup SIGTERM SIGINT

echo ""
echo "========================================"
echo "All services are running"
echo "========================================"
echo "Container will keep running until stopped (SIGTERM/SIGINT)"
echo "To stop: docker stop <container_id>"
echo ""

# Keep container running
# Use exec to replace shell with sleep so signals are properly handled
exec sleep infinity
