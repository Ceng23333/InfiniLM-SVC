#!/usr/bin/env bash
# Docker entrypoint script for InfiniLM-SVC (Rust version)
# Launches configurable services and handles graceful shutdown on container stop
#
# Configuration via environment variables (docker run -e):
#   - LAUNCH_COMPONENTS: Components to launch (default: "all")
#                        Options: "all", "babysitter", or comma-separated list: "registry,router,babysitter"
#   - REGISTRY_PORT: Port for registry (default: 18000)
#   - ROUTER_PORT: Port for router (default: 8000)
#   - REGISTRY_URL: Remote registry URL (used when registry not launched locally)
#   - ROUTER_URL: Remote router URL (used when router not launched locally)
#   - BABYSITTER_CONFIGS: Space-separated paths to babysitter config files
#   - ROUTER_REGISTRY_URL: Registry URL for router to connect to (default: http://localhost:REGISTRY_PORT)
#                          Use this when router needs to connect to remote registry
#
# Examples:
#   # Launch all components
#   docker run -e LAUNCH_COMPONENTS=all ...
#
#   # Launch only babysitter (connect to remote registry/router)
#   docker run -e LAUNCH_COMPONENTS=babysitter \
#              -e REGISTRY_URL=http://remote-host:18000 \
#              -e ROUTER_URL=http://remote-host:8000 ...
#
#   # Launch registry and router only
#   docker run -e LAUNCH_COMPONENTS=registry,router -e REGISTRY_PORT=18000 -e ROUTER_PORT=8000 ...

set -e

# Optional conda activation (for images that provide /opt/conda)
if [ -f /opt/conda/etc/profile.d/conda.sh ]; then
  # shellcheck disable=SC1091
  source /opt/conda/etc/profile.d/conda.sh
  conda activate base
fi

# Source environment setup if present (prefer project root /app for base-image installs)
if [ -f /app/env-set.sh ]; then
  # shellcheck disable=SC1091
  source /app/env-set.sh
elif [ -f /workspace/env-set.sh ]; then
  # shellcheck disable=SC1091
  source /workspace/env-set.sh
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Determine project root
# If script is at /app/docker_entrypoint.sh, project root is /app
# If script is at /workspace/docker_entrypoint.sh, project root is /workspace
# If script is at docker/docker_entrypoint_rust.sh, project root is parent
if [ -d "${SCRIPT_DIR}/../script" ] && [ -f "${SCRIPT_DIR}/../script/launch_all_rust.sh" ]; then
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
elif [ -d "/app/script" ] && [ -f "/app/script/launch_all_rust.sh" ]; then
    PROJECT_ROOT="/app"
elif [ -d "/workspace/script" ] && [ -f "/workspace/script/launch_all_rust.sh" ]; then
    PROJECT_ROOT="/workspace"
elif [ -d "${SCRIPT_DIR}/script" ] && [ -f "${SCRIPT_DIR}/script/launch_all_rust.sh" ]; then
    # Script is in same directory as entrypoint (e.g., /workspace)
    PROJECT_ROOT="${SCRIPT_DIR}"
else
    echo "Error: Cannot find project root. script/launch_all_rust.sh not found."
    echo "SCRIPT_DIR: ${SCRIPT_DIR}"
    echo "Looking for script in: ${SCRIPT_DIR}/../script/launch_all_rust.sh"
    echo "Looking for script in: ${SCRIPT_DIR}/script/launch_all_rust.sh"
    echo "Looking for script in: /app/script/launch_all_rust.sh"
    echo "Looking for script in: /workspace/script/launch_all_rust.sh"
    exit 1
fi

cd "${PROJECT_ROOT}" || exit 1

echo "========================================"
echo "InfiniLM-SVC Docker Entrypoint (Rust)"
echo "========================================"
echo "PROJECT_ROOT: ${PROJECT_ROOT}"
echo "SCRIPT_DIR: ${SCRIPT_DIR}"
echo ""

# Parse LAUNCH_COMPONENTS (default: "all")
LAUNCH_COMPONENTS="${LAUNCH_COMPONENTS:-all}"
LAUNCH_COMPONENTS=$(echo "${LAUNCH_COMPONENTS}" | tr '[:upper:]' '[:lower:]' | tr -d ' ')

# Determine which components to launch
LAUNCH_REGISTRY=false
LAUNCH_ROUTER=false
LAUNCH_BABYSITTER=false

if [ "${LAUNCH_COMPONENTS}" = "none" ] || [ -z "${LAUNCH_COMPONENTS}" ]; then
    # Launch nothing - useful for daily development where services are started manually
    echo "LAUNCH_COMPONENTS is 'none' or empty - no services will be launched automatically"
    echo "This is useful for daily development where you start services manually"
elif [ "${LAUNCH_COMPONENTS}" = "all" ]; then
    LAUNCH_REGISTRY=true
    LAUNCH_ROUTER=true
    LAUNCH_BABYSITTER=true
elif [ "${LAUNCH_COMPONENTS}" = "babysitter" ]; then
    LAUNCH_BABYSITTER=true
else
    # Parse comma-separated list
    IFS=',' read -ra COMPONENTS <<< "${LAUNCH_COMPONENTS}"
    for component in "${COMPONENTS[@]}"; do
        component=$(echo "${component}" | tr -d ' ')
        case "${component}" in
            registry)
                LAUNCH_REGISTRY=true
                ;;
            router)
                LAUNCH_ROUTER=true
                ;;
            babysitter)
                LAUNCH_BABYSITTER=true
                ;;
            none)
                # Explicitly set to none (already handled above, but allow in comma list)
                echo "Note: 'none' found in component list - no services will be launched"
                ;;
            *)
                echo "Warning: Unknown component '${component}' in LAUNCH_COMPONENTS"
                ;;
        esac
    done
fi

# Set default ports if not provided
export REGISTRY_PORT="${REGISTRY_PORT:-18000}"
export ROUTER_PORT="${ROUTER_PORT:-8000}"

# Determine registry and router URLs
# If launching locally, use localhost; otherwise use provided remote URLs
if [ "${LAUNCH_REGISTRY}" = "true" ]; then
    export ROUTER_REGISTRY_URL="${ROUTER_REGISTRY_URL:-http://localhost:${REGISTRY_PORT}}"
    BABYSITTER_REGISTRY_URL="${BABYSITTER_REGISTRY_URL:-http://localhost:${REGISTRY_PORT}}"
else
    # Registry not launched locally - use remote URL if provided
    if [ -n "${REGISTRY_URL:-}" ]; then
        export ROUTER_REGISTRY_URL="${ROUTER_REGISTRY_URL:-${REGISTRY_URL}}"
        BABYSITTER_REGISTRY_URL="${REGISTRY_URL}"
    else
        # Registry URL not provided - babysitters can work without it (optional)
        export ROUTER_REGISTRY_URL="${ROUTER_REGISTRY_URL:-}"
        BABYSITTER_REGISTRY_URL=""
        if [ "${LAUNCH_ROUTER}" = "true" ]; then
            echo "Warning: LAUNCH_COMPONENTS does not include 'registry' and REGISTRY_URL is not set"
            echo "Router will not be able to connect to registry"
        fi
    fi
fi

if [ "${LAUNCH_ROUTER}" = "true" ]; then
    BABYSITTER_ROUTER_URL="${BABYSITTER_ROUTER_URL:-http://localhost:${ROUTER_PORT}}"
else
    if [ -z "${ROUTER_URL:-}" ]; then
        echo "Warning: LAUNCH_COMPONENTS does not include 'router' and ROUTER_URL is not set"
        echo "Babysitters will not connect to router"
        BABYSITTER_ROUTER_URL=""
    else
        BABYSITTER_ROUTER_URL="${ROUTER_URL}"
    fi
fi

# Display configuration
echo "Configuration:"
echo "  Launch Registry: ${LAUNCH_REGISTRY}"
echo "  Launch Router: ${LAUNCH_ROUTER}"
echo "  Launch Babysitter: ${LAUNCH_BABYSITTER}"
if [ "${LAUNCH_REGISTRY}" = "true" ]; then
    echo "  Registry Port: ${REGISTRY_PORT}"
else
    echo "  Registry URL: ${BABYSITTER_REGISTRY_URL}"
fi
if [ "${LAUNCH_ROUTER}" = "true" ]; then
    echo "  Router Port: ${ROUTER_PORT}"
    echo "  Router Registry URL: ${ROUTER_REGISTRY_URL}"
else
    echo "  Router URL: ${BABYSITTER_ROUTER_URL:-not configured}"
fi
echo ""

# Ensure binaries are built (if not already)
if [ "${BUILD_ON_STARTUP:-false}" = "true" ]; then
    echo "Building Rust binaries..."
    cd "${PROJECT_ROOT}/rust" || exit 1
    BUILD_BINS=()
    [ "${LAUNCH_REGISTRY}" = "true" ] && BUILD_BINS+=("--bin" "infini-registry")
    [ "${LAUNCH_ROUTER}" = "true" ] && BUILD_BINS+=("--bin" "infini-router")
    [ "${LAUNCH_BABYSITTER}" = "true" ] && BUILD_BINS+=("--bin" "infini-babysitter")
    if [ ${#BUILD_BINS[@]} -gt 0 ]; then
        cargo build --release "${BUILD_BINS[@]}"
    fi
    cd "${PROJECT_ROOT}" || exit 1
    echo "Build complete."
    echo ""
fi

# Note about BABYSITTER_CONFIGS:
# In Docker, `-e BABYSITTER_CONFIGS="a b c"` is always a single string.
# Bash arrays cannot be reliably exported across processes.
# The launch script (`script/launch_all_rust.sh`) will parse this string into an array.

# Export babysitter registry/router URLs and host for use in launch script
export BABYSITTER_REGISTRY_URL
export BABYSITTER_ROUTER_URL
# BABYSITTER_HOST can be set to override host for registration (useful for cross-server)
# If not set, config file host will be used
export BABYSITTER_HOST="${BABYSITTER_HOST:-}"

# Export component launch flags
export LAUNCH_REGISTRY
export LAUNCH_ROUTER
export LAUNCH_BABYSITTER

# Launch services using the Rust launch script (only if at least one component should be launched)
if [ "${LAUNCH_REGISTRY}" = "true" ] || [ "${LAUNCH_ROUTER}" = "true" ] || [ "${LAUNCH_BABYSITTER}" = "true" ]; then
    LAUNCH_SCRIPT="${PROJECT_ROOT}/script/launch_all_rust.sh"
    if [ -f "${LAUNCH_SCRIPT}" ]; then
        bash "${LAUNCH_SCRIPT}"
    else
        echo "Error: launch_all_rust.sh not found at ${LAUNCH_SCRIPT}"
        echo "PROJECT_ROOT: ${PROJECT_ROOT}"
        echo "Looking for: ${LAUNCH_SCRIPT}"
        exit 1
    fi
else
    echo ""
    echo "No services configured to launch (LAUNCH_COMPONENTS=${LAUNCH_COMPONENTS})"
    echo "Container will keep running - you can start services manually if needed"
    echo ""
fi

# Set up signal handlers for graceful shutdown
# SIGTERM is sent by 'docker stop'
# SIGINT is sent by Ctrl+C (docker run -it)
cleanup() {
    echo ""
    echo "[entrypoint] Received shutdown signal, stopping all services..."

    # Stop all services gracefully
    if [ -f "${PROJECT_ROOT}/script/stop_all.sh" ]; then
        bash "${PROJECT_ROOT}/script/stop_all.sh"
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
if [ "${LAUNCH_REGISTRY}" = "true" ] || [ "${LAUNCH_ROUTER}" = "true" ] || [ "${LAUNCH_BABYSITTER}" = "true" ]; then
    echo "All services are running"
else
    echo "Container ready (no services auto-launched)"
fi
echo "========================================"
echo "Container will keep running until stopped (SIGTERM/SIGINT)"
echo "To stop: docker stop <container_id>"
if [ "${LAUNCH_REGISTRY}" != "true" ] && [ "${LAUNCH_ROUTER}" != "true" ] && [ "${LAUNCH_BABYSITTER}" != "true" ]; then
    echo ""
    echo "To start services manually, use:"
    echo "  docker exec -it <container_id> bash"
    echo "  # Then run services manually or use script/launch_all_rust.sh"
fi
echo ""

# Keep container running
# Use exec to replace shell with sleep so signals are properly handled
exec sleep infinity
