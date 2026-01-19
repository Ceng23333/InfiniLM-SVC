#!/bin/bash
# Launch all InfiniLM-SVC services (Rust version) in sequence
# Order: Registry -> Router -> Babysitters (configurable)
#
# Configuration:
#   - Set environment variables or edit the CONFIGURATION section below
#   - Babysitters are configured via TOML files in config/ directory
#   - Supports multiple babysitters via BABYSITTER_CONFIGS array

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# CONFIGURATION - Edit these variables or set via environment variables
# ============================================================================

# Project paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUST_DIR="${PROJECT_ROOT}/rust"
CONFIG_DIR="${PROJECT_ROOT}/config"
LOG_DIR="${PROJECT_ROOT}/logs"

# Rust binary paths (defaults to release builds, can be overridden)
RUST_TARGET="${RUST_TARGET:-release}"
REGISTRY_BIN="${REGISTRY_BIN:-${RUST_DIR}/target/${RUST_TARGET}/infini-registry}"
ROUTER_BIN="${ROUTER_BIN:-${RUST_DIR}/target/${RUST_TARGET}/infini-router}"
BABYSITTER_BIN="${BABYSITTER_BIN:-${RUST_DIR}/target/${RUST_TARGET}/infini-babysitter}"

# Service ports (can be overridden via environment variables)
REGISTRY_PORT="${REGISTRY_PORT:-18000}"
ROUTER_PORT="${ROUTER_PORT:-8000}"

# Registry configuration
REGISTRY_HEALTH_INTERVAL="${REGISTRY_HEALTH_INTERVAL:-30}"
REGISTRY_HEALTH_TIMEOUT="${REGISTRY_HEALTH_TIMEOUT:-5}"
REGISTRY_CLEANUP_INTERVAL="${REGISTRY_CLEANUP_INTERVAL:-60}"

# Router configuration
ROUTER_REGISTRY_URL="${ROUTER_REGISTRY_URL:-http://localhost:${REGISTRY_PORT}}"
ROUTER_HEALTH_INTERVAL="${ROUTER_HEALTH_INTERVAL:-30}"
ROUTER_HEALTH_TIMEOUT="${ROUTER_HEALTH_TIMEOUT:-5}"
ROUTER_REGISTRY_SYNC_INTERVAL="${ROUTER_REGISTRY_SYNC_INTERVAL:-10}"

# Babysitter configurations (TOML config files)
# Add multiple babysitters by adding more config files to this array
# Example: BABYSITTER_CONFIGS=("config/babysitter1.toml" "config/babysitter2.toml")
BABYSITTER_CONFIGS=("${BABYSITTER_CONFIGS[@]:-}")

# Timeouts (seconds)
REGISTRY_WAIT_TIMEOUT="${REGISTRY_WAIT_TIMEOUT:-60}"
ROUTER_WAIT_TIMEOUT="${ROUTER_WAIT_TIMEOUT:-60}"
BABYSITTER_WAIT_TIMEOUT="${BABYSITTER_WAIT_TIMEOUT:-300}"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Function to wait for a service to be ready
wait_for_service() {
    local url=$1
    local service_name=$2
    local max_wait=$3
    local elapsed=0

    echo -n "Waiting for ${service_name} to be ready..."
    while [ ${elapsed} -lt ${max_wait} ]; do
        if curl -s -f "${url}" > /dev/null 2>&1; then
            echo -e " ${GREEN}[ready]${NC}"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
        if [ $((elapsed % 5)) -eq 0 ]; then
            echo -n "."
        fi
    done
    echo -e " ${RED}[timeout after ${max_wait}s]${NC}"
    return 1
}

# Function to check if process started successfully (by PID file)
check_process_started() {
    local pid_file=$1
    local max_wait=5
    local elapsed=0

    while [ ${elapsed} -lt ${max_wait} ]; do
        if [ -f "${pid_file}" ]; then
            local pid=$(cat "${pid_file}" 2>/dev/null)
            if [ -n "${pid}" ] && ps -p ${pid} > /dev/null 2>&1; then
                return 0
            fi
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}

# Function to check if a service is already running
check_service_running() {
    local pid_file=$1
    local service_name=$2

    if [ -f "${pid_file}" ]; then
        local pid=$(cat "${pid_file}" 2>/dev/null)
        if [ -n "${pid}" ] && ps -p ${pid} > /dev/null 2>&1; then
            echo -e "${YELLOW}⚠ ${service_name} is already running (PID: ${pid})${NC}"
            return 0
        else
            # Stale PID file
            rm -f "${pid_file}"
        fi
    fi
    return 1
}

# Function to launch registry
launch_registry() {
    local pid_file="${LOG_DIR}/registry.pid"
    local log_file="${LOG_DIR}/registry_$(date +%y%m%d%H%M).log"

    if check_service_running "${pid_file}" "Service Registry"; then
        if ! wait_for_service "http://localhost:${REGISTRY_PORT}/health" "Service Registry" 5; then
            echo -e "  ${YELLOW}⚠ Warning: Service Registry PID exists but health check failed${NC}"
        fi
        return 0
    fi

    echo "  Starting Service Registry..."
    mkdir -p "${LOG_DIR}"

    nohup "${REGISTRY_BIN}" \
        --port "${REGISTRY_PORT}" \
        --health-interval "${REGISTRY_HEALTH_INTERVAL}" \
        --health-timeout "${REGISTRY_HEALTH_TIMEOUT}" \
        --cleanup-interval "${REGISTRY_CLEANUP_INTERVAL}" \
        >> "${log_file}" 2>&1 &

    local pid=$!
    echo ${pid} > "${pid_file}"

    sleep 2
    if check_process_started "${pid_file}"; then
        if wait_for_service "http://localhost:${REGISTRY_PORT}/health" "Service Registry" ${REGISTRY_WAIT_TIMEOUT}; then
            echo "  ✓ Service Registry started and ready"
            return 0
        else
            echo -e "  ${RED}✗ Service Registry failed to become ready${NC}"
            return 1
        fi
    else
        echo -e "  ${RED}✗ Failed to start Service Registry${NC}"
        return 1
    fi
}

# Function to launch router
launch_router() {
    local pid_file="${LOG_DIR}/router.pid"
    local log_file="${LOG_DIR}/router_$(date +%y%m%d%H%M).log"

    if check_service_running "${pid_file}" "Distributed Router"; then
        if ! wait_for_service "http://localhost:${ROUTER_PORT}/health" "Distributed Router" 5; then
            echo -e "  ${YELLOW}⚠ Warning: Distributed Router PID exists but health check failed${NC}"
        fi
        return 0
    fi

    echo "  Starting Distributed Router..."
    mkdir -p "${LOG_DIR}"

    nohup "${ROUTER_BIN}" \
        --router-port "${ROUTER_PORT}" \
        --registry-url "${ROUTER_REGISTRY_URL}" \
        --health-interval "${ROUTER_HEALTH_INTERVAL}" \
        --health-timeout "${ROUTER_HEALTH_TIMEOUT}" \
        --registry-sync-interval "${ROUTER_REGISTRY_SYNC_INTERVAL}" \
        >> "${log_file}" 2>&1 &

    local pid=$!
    echo ${pid} > "${pid_file}"

    sleep 2
    if check_process_started "${pid_file}"; then
        if wait_for_service "http://localhost:${ROUTER_PORT}/health" "Distributed Router" ${ROUTER_WAIT_TIMEOUT}; then
            echo "  ✓ Distributed Router started and ready"
            return 0
        else
            echo -e "  ${RED}✗ Distributed Router failed to become ready${NC}"
            return 1
        fi
    else
        echo -e "  ${RED}✗ Failed to start Distributed Router${NC}"
        return 1
    fi
}

# Function to launch babysitter from config file
launch_babysitter() {
    local config_file=$1
    local config_name=$(basename "${config_file}" .toml)
    local pid_file="${LOG_DIR}/babysitter_${config_name}.pid"
    local log_file="${LOG_DIR}/babysitter_${config_name}_$(date +%y%m%d%H%M).log"

    if check_service_running "${pid_file}" "Babysitter (${config_name})"; then
        return 0
    fi

    if [ ! -f "${config_file}" ]; then
        echo -e "  ${RED}✗ Config file not found: ${config_file}${NC}"
        return 1
    fi

    echo "  Starting Babysitter (${config_name})..."
    mkdir -p "${LOG_DIR}"

    # Build command with optional registry and router URLs
    local cmd_args=("${BABYSITTER_BIN}" "--config-file" "${config_file}")

    # Add host override if provided (from entrypoint or environment)
    # This is important for cross-server registration - host in config may be "0.0.0.0" for binding
    # but we need the actual IP for registration
    # Only override if BABYSITTER_HOST is explicitly set (not empty)
    if [ -n "${BABYSITTER_HOST:-}" ]; then
        cmd_args+=("--host" "${BABYSITTER_HOST}")
        echo "    Host (override for registration): ${BABYSITTER_HOST}"
        echo "    Note: Service still binds on 0.0.0.0, but registers with ${BABYSITTER_HOST}"
    fi

    # Add registry URL if provided (from entrypoint or environment)
    if [ -n "${BABYSITTER_REGISTRY_URL:-}" ]; then
        cmd_args+=("--registry-url" "${BABYSITTER_REGISTRY_URL}")
        echo "    Registry URL: ${BABYSITTER_REGISTRY_URL}"
    fi

    # Add router URL if provided (from entrypoint or environment)
    if [ -n "${BABYSITTER_ROUTER_URL:-}" ]; then
        cmd_args+=("--router-url" "${BABYSITTER_ROUTER_URL}")
        echo "    Router URL: ${BABYSITTER_ROUTER_URL}"
    fi

    nohup "${cmd_args[@]}" >> "${log_file}" 2>&1 &

    local pid=$!
    echo ${pid} > "${pid_file}"

    sleep 2
    if check_process_started "${pid_file}"; then
        echo "  ✓ Babysitter (${config_name}) process started"
        return 0
    else
        echo -e "  ${RED}✗ Failed to start Babysitter (${config_name})${NC}"
        return 1
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

echo "========================================"
echo "Launching InfiniLM-SVC Services (Rust)"
echo "========================================"
echo ""

# Check which components to launch (default to all if not set)
LAUNCH_REGISTRY="${LAUNCH_REGISTRY:-true}"
LAUNCH_ROUTER="${LAUNCH_ROUTER:-true}"
LAUNCH_BABYSITTER="${LAUNCH_BABYSITTER:-true}"

# Verify binaries exist only for components that will be launched
if [ "${LAUNCH_REGISTRY}" = "true" ]; then
    if [ ! -f "${REGISTRY_BIN}" ]; then
        echo -e "${RED}Error: Registry binary not found: ${REGISTRY_BIN}${NC}"
        echo "  Build with: cd ${RUST_DIR} && cargo build --release --bin infini-registry"
        exit 1
    fi
fi

if [ "${LAUNCH_ROUTER}" = "true" ]; then
    if [ ! -f "${ROUTER_BIN}" ]; then
        echo -e "${RED}Error: Router binary not found: ${ROUTER_BIN}${NC}"
        echo "  Build with: cd ${RUST_DIR} && cargo build --release --bin infini-router"
        exit 1
    fi
fi

if [ "${LAUNCH_BABYSITTER}" = "true" ]; then
    if [ ! -f "${BABYSITTER_BIN}" ]; then
        echo -e "${RED}Error: Babysitter binary not found: ${BABYSITTER_BIN}${NC}"
        echo "  Build with: cd ${RUST_DIR} && cargo build --release --bin infini-babysitter"
        exit 1
    fi
fi

# Track results
success_count=0
failed_services=()
total_services=0

# Count services that will be launched
[ "${LAUNCH_REGISTRY}" = "true" ] && total_services=$((total_services + 1))
[ "${LAUNCH_ROUTER}" = "true" ] && total_services=$((total_services + 1))
if [ "${LAUNCH_BABYSITTER}" = "true" ] && [ ${#BABYSITTER_CONFIGS[@]} -gt 0 ]; then
    total_services=$((total_services + ${#BABYSITTER_CONFIGS[@]}))
fi

service_idx=1

# 1. Launch Service Registry (if enabled)
if [ "${LAUNCH_REGISTRY}" = "true" ]; then
    echo -e "${BLUE}[${service_idx}/${total_services}] Launching Service Registry (port ${REGISTRY_PORT})...${NC}"
    if launch_registry; then
        success_count=$((success_count + 1))
    else
        failed_services+=("Service Registry")
        echo -e "  ${YELLOW}⚠ Cannot proceed without Registry - aborting${NC}"
        exit 1
    fi
    echo ""
    service_idx=$((service_idx + 1))
fi

# 2. Launch Distributed Router (if enabled)
if [ "${LAUNCH_ROUTER}" = "true" ]; then
    echo -e "${BLUE}[${service_idx}/${total_services}] Launching Distributed Router (port ${ROUTER_PORT})...${NC}"
    if launch_router; then
        success_count=$((success_count + 1))
    else
        failed_services+=("Distributed Router")
    fi
    echo ""
    service_idx=$((service_idx + 1))
fi

# 3. Launch Babysitters (if enabled)
if [ "${LAUNCH_BABYSITTER}" = "true" ]; then
    if [ ${#BABYSITTER_CONFIGS[@]} -gt 0 ]; then
        for config_file in "${BABYSITTER_CONFIGS[@]}"; do
            # Resolve relative paths
            if [[ ! "${config_file}" = /* ]]; then
                config_file="${CONFIG_DIR}/${config_file}"
            fi

            echo -e "${BLUE}[${service_idx}/${total_services}] Launching Babysitter (${config_file})...${NC}"
            if launch_babysitter "${config_file}"; then
                success_count=$((success_count + 1))
            else
                failed_services+=("Babysitter ($(basename ${config_file}))")
            fi
            echo ""
            service_idx=$((service_idx + 1))
        done
    else
        echo -e "${YELLOW}⚠ No babysitter configs specified (BABYSITTER_CONFIGS is empty)${NC}"
        echo "  Set BABYSITTER_CONFIGS environment variable or edit this script"
        echo "  Example: export BABYSITTER_CONFIGS=('config/babysitter1.toml' 'config/babysitter2.toml')"
        echo ""
    fi
fi

# Summary
echo "========================================"
echo "Launch Summary"
echo "========================================"
echo -e "${GREEN}✓ Successfully launched/verified: ${success_count}/${total_services} services${NC}"
if [ ${#failed_services[@]} -gt 0 ]; then
    echo -e "${RED}✗ Failed services:${NC}"
    for service in "${failed_services[@]}"; do
        echo -e "  ${RED}  - ${service}${NC}"
    done
    echo ""
    echo "Check log files in ${LOG_DIR}/ for details"
    exit 1
fi
echo ""
echo "All services launched successfully!"
echo ""
echo "Quick status checks:"
if [ "${LAUNCH_REGISTRY}" = "true" ]; then
    echo "  curl http://localhost:${REGISTRY_PORT}/health  # Registry"
    echo "  curl http://localhost:${REGISTRY_PORT}/services  # List all registered services"
fi
if [ "${LAUNCH_ROUTER}" = "true" ]; then
    echo "  curl http://localhost:${ROUTER_PORT}/health  # Router"
    echo "  curl http://localhost:${ROUTER_PORT}/models  # Router - aggregated models"
    echo "  curl http://localhost:${ROUTER_PORT}/services  # Router - list services"
fi
echo ""
echo "To stop all services:"
echo "  ./stop_all.sh"
echo ""
