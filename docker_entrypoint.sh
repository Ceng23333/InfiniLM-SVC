#!/usr/bin/env bash
set -e

source /opt/conda/etc/profile.d/conda.sh
conda activate base

source /workspace/env-set.sh


# Docker entrypoint script for InfiniLM-SVC
# Launches all services and handles graceful shutdown on container stop

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" || exit 1

echo "========================================"
echo "InfiniLM-SVC Docker Entrypoint"
echo "========================================"
echo "Starting all services..."
echo ""

# Launch all services
./launch_all.sh

# Set up signal handlers for graceful shutdown
# SIGTERM is sent by 'docker stop'
# SIGINT is sent by Ctrl+C (docker run -it)
trap 'echo ""; echo "[entrypoint] Received shutdown signal, stopping all services..."; ./stop_all.sh; echo "[entrypoint] All services stopped. Exiting."; exit 0' SIGTERM SIGINT

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
