#!/bin/bash
# Launch all InfiniLM-SVC services in sequence
# Order: Registry -> Router -> Babysitter_9g8b -> Babysitter_qwen

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
REGISTRY_WAIT_TIMEOUT=60  # Maximum wait time for Registry to become ready (seconds)
ROUTER_WAIT_TIMEOUT=60    # Maximum wait time for Router to become ready (seconds)
BABYSITTER_WAIT_TIMEOUT=300  # Maximum wait time for Babysitter to become ready (seconds) - longer for model loading

# Change to script directory
cd "${SCRIPT_DIR}" || exit 1

# Function to wait for a service to be ready
wait_for_service() {
    local url=$1
    local service_name=$2
    local max_wait=$3  # Timeout as parameter
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

# Main execution
echo "========================================"
echo "Launching All InfiniLM-SVC Services"
echo "========================================"
echo ""

# Track results
success_count=0
failed_services=()

# Read ports from launch scripts
REGISTRY_PORT=$(grep "^REGISTRY_PORT=" launch_registry.sh 2>/dev/null | head -1 | cut -d'=' -f2 | tr -d ' ' || echo "18000")
ROUTER_PORT=$(grep "^ROUTER_PORT=" launch_router.sh 2>/dev/null | head -1 | cut -d'=' -f2 | tr -d ' ' || echo "8000")

# 1. Launch Service Registry (CRITICAL - required for other services)
echo -e "${BLUE}[1/4] Launching Service Registry (port ${REGISTRY_PORT})...${NC}"
if check_service_running "${LOG_DIR}/registry.pid" "Service Registry"; then
    echo "  Skipping (already running)"
    success_count=$((success_count + 1))
    # Verify it's actually responding
    if ! wait_for_service "http://localhost:${REGISTRY_PORT}/health" "Service Registry" 5; then
        echo -e "  ${YELLOW}⚠ Warning: Service Registry PID exists but health check failed${NC}"
    fi
else
    echo "  Starting Service Registry..."
    if ./launch_registry.sh > /dev/null 2>&1; then
        # Check if process started
        sleep 2
        if check_process_started "${LOG_DIR}/registry.pid"; then
            echo "  Process started, waiting for health check..."
            if wait_for_service "http://localhost:${REGISTRY_PORT}/health" "Service Registry" ${REGISTRY_WAIT_TIMEOUT}; then
                success_count=$((success_count + 1))
                echo "  ✓ Service Registry started and ready"
            else
                failed_services+=("Service Registry")
                echo -e "  ${RED}✗ Service Registry failed to become ready${NC}"
                echo "  Check logs: ${LOG_DIR}/registry_*.log"
                echo -e "  ${YELLOW}⚠ Cannot proceed without Registry - aborting${NC}"
                exit 1
            fi
        else
            failed_services+=("Service Registry")
            echo -e "  ${RED}✗ Failed to start Service Registry (process did not start)${NC}"
            echo "  Check logs: ${LOG_DIR}/registry_*.log"
            echo -e "  ${YELLOW}⚠ Cannot proceed without Registry - aborting${NC}"
            exit 1
        fi
    else
        failed_services+=("Service Registry")
        echo -e "  ${RED}✗ Failed to launch Service Registry${NC}"
        echo "  Check logs: ${LOG_DIR}/registry_*.log"
        echo -e "  ${YELLOW}⚠ Cannot proceed without Registry - aborting${NC}"
        exit 1
    fi
fi
echo ""

# 2. Launch Distributed Router
echo -e "${BLUE}[2/4] Launching Distributed Router (port ${ROUTER_PORT})...${NC}"
if check_service_running "${LOG_DIR}/router.pid" "Distributed Router"; then
    echo "  Skipping (already running)"
    success_count=$((success_count + 1))
    # Verify it's actually responding
    if ! wait_for_service "http://localhost:${ROUTER_PORT}/health" "Distributed Router" 5; then
        echo -e "  ${YELLOW}⚠ Warning: Distributed Router PID exists but health check failed${NC}"
    fi
else
    echo "  Starting Distributed Router..."
    if ./launch_router.sh > /dev/null 2>&1; then
        # Check if process started
        sleep 2
        if check_process_started "${LOG_DIR}/router.pid"; then
            echo "  Process started, waiting for health check..."
            if wait_for_service "http://localhost:${ROUTER_PORT}/health" "Distributed Router" ${ROUTER_WAIT_TIMEOUT}; then
                success_count=$((success_count + 1))
                echo "  ✓ Distributed Router started and ready"
            else
                failed_services+=("Distributed Router")
                echo -e "  ${RED}✗ Distributed Router failed to become ready${NC}"
                echo "  Check logs: ${LOG_DIR}/router_*.log"
            fi
        else
            failed_services+=("Distributed Router")
            echo -e "  ${RED}✗ Failed to start Distributed Router (process did not start)${NC}"
            echo "  Check logs: ${LOG_DIR}/router_*.log"
        fi
    else
        failed_services+=("Distributed Router")
        echo -e "  ${RED}✗ Failed to launch Distributed Router${NC}"
        echo "  Check logs: ${LOG_DIR}/router_*.log"
    fi
fi
echo ""

# 3. Launch Babysitter for 9g8b model
echo -e "${BLUE}[3/4] Launching Enhanced Babysitter (9g8b)...${NC}"
if check_service_running "${LOG_DIR}/babysitter_8100.pid" "Babysitter (9g8b)"; then
    echo "  Skipping (already running)"
    success_count=$((success_count + 1))
else
    echo "  Starting Babysitter (9g8b)..."
    if ./launch_babysitter_9g8b.sh > /dev/null 2>&1; then
        # Check if process started
        sleep 2
        if check_process_started "${LOG_DIR}/babysitter_8100.pid"; then
            success_count=$((success_count + 1))
            echo "  ✓ Babysitter (9g8b) process started (model may still be loading)"
            echo "  (Health check will be verified at the end - model loading can take several minutes)"
        else
            failed_services+=("Babysitter (9g8b)")
            echo -e "  ${RED}✗ Failed to start Babysitter (9g8b) (process did not start)${NC}"
            echo "  Check logs: ${LOG_DIR}/babysitter_8100_*.log"
        fi
    else
        failed_services+=("Babysitter (9g8b)")
        echo -e "  ${RED}✗ Failed to launch Babysitter (9g8b)${NC}"
        echo "  Check logs: ${LOG_DIR}/babysitter_8100_*.log"
    fi
fi
echo ""

# 4. Launch Babysitter for Qwen model (non-blocking - starts immediately after 9g8b launch)
echo -e "${BLUE}[4/4] Launching Enhanced Babysitter (Qwen)...${NC}"
if check_service_running "${LOG_DIR}/babysitter_8200.pid" "Babysitter (Qwen)"; then
    echo "  Skipping (already running)"
    success_count=$((success_count + 1))
else
    echo "  Starting Babysitter (Qwen)..."
    if ./launch_babysitter_qwen.sh > /dev/null 2>&1; then
        # Check if process started
        sleep 2
        if check_process_started "${LOG_DIR}/babysitter_8200.pid"; then
            success_count=$((success_count + 1))
            echo "  ✓ Babysitter (Qwen) process started (model may still be loading)"
            echo "  (Health check will be verified at the end - model loading can take several minutes)"
        else
            failed_services+=("Babysitter (Qwen)")
            echo -e "  ${RED}✗ Failed to start Babysitter (Qwen) (process did not start)${NC}"
            echo "  Check logs: ${LOG_DIR}/babysitter_8200_*.log"
        fi
    else
        failed_services+=("Babysitter (Qwen)")
        echo -e "  ${RED}✗ Failed to launch Babysitter (Qwen)${NC}"
        echo "  Check logs: ${LOG_DIR}/babysitter_8200_*.log"
    fi
fi
echo ""

# Verify babysitter health checks (non-blocking quick verification)
echo -e "${BLUE}Quick Health Status Check (non-blocking)...${NC}"

# Check 9g8b babysitter health (quick check, don't wait long)
if [ -f "${LOG_DIR}/babysitter_8100.pid" ]; then
    pid=$(cat "${LOG_DIR}/babysitter_8100.pid" 2>/dev/null)
    if [ -n "${pid}" ] && ps -p ${pid} > /dev/null 2>&1; then
        echo -n "  Babysitter (9g8b): "
        if curl -s -f "http://localhost:8101/health" > /dev/null 2>&1; then
            echo -e "${GREEN}[ready]${NC}"
        else
            echo -e "${YELLOW}[loading model - normal if just started]${NC}"
        fi
    fi
fi

# Check Qwen babysitter health (quick check, don't wait long)
if [ -f "${LOG_DIR}/babysitter_8200.pid" ]; then
    pid=$(cat "${LOG_DIR}/babysitter_8200.pid" 2>/dev/null)
    if [ -n "${pid}" ] && ps -p ${pid} > /dev/null 2>&1; then
        echo -n "  Babysitter (Qwen): "
        if curl -s -f "http://localhost:8201/health" > /dev/null 2>&1; then
            echo -e "${GREEN}[ready]${NC}"
        else
            echo -e "${YELLOW}[loading model - normal if just started]${NC}"
        fi
    fi
fi
echo ""

# Summary
echo "========================================"
echo "Launch Summary"
echo "========================================"
echo -e "${GREEN}✓ Successfully launched/verified: ${success_count}/4 services${NC}"
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
echo "  curl http://localhost:${REGISTRY_PORT}/health  # Registry"
echo "  curl http://localhost:${ROUTER_PORT}/health  # Router"
echo "  curl http://localhost:${ROUTER_PORT}/models  # Router - aggregated models"
echo "  curl http://localhost:8101/health  # Babysitter (9g8b)"
echo "  curl http://localhost:8201/health  # Babysitter (Qwen)"
echo "  curl http://localhost:8100/models  # InfiniLM server (9g8b)"
echo "  curl http://localhost:8200/models  # InfiniLM server (Qwen)"
echo ""
echo "Registry services:"
echo "  curl http://localhost:${REGISTRY_PORT}/services  # List all registered services"
echo ""
echo "Note: If models are still loading, they may not appear in the router's /models endpoint yet."
echo "      Check babysitter logs to verify model loading progress."
echo ""
echo "To stop all services:"
echo "  ./stop_all.sh"
echo ""
