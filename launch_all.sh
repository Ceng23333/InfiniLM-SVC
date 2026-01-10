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
WAIT_TIMEOUT=30  # Maximum wait time for each service to become ready (seconds)

# Change to script directory
cd "${SCRIPT_DIR}" || exit 1

# Function to wait for a service to be ready
wait_for_service() {
    local url=$1
    local service_name=$2
    local max_wait=${WAIT_TIMEOUT}
    local elapsed=0

    echo -n "Waiting for ${service_name} to be ready..."
    while [ ${elapsed} -lt ${max_wait} ]; do
        if curl -s -f "${url}" > /dev/null 2>&1; then
            echo -e " ${GREEN}[ready]${NC}"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
        echo -n "."
    done
    echo -e " ${RED}[timeout]${NC}"
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

# 1. Launch Service Registry
echo -e "${BLUE}[1/4] Launching Service Registry (port ${REGISTRY_PORT})...${NC}"
if check_service_running "${LOG_DIR}/registry.pid" "Service Registry"; then
    echo "  Skipping (already running)"
    success_count=$((success_count + 1))
else
    if ./launch_registry.sh > /dev/null 2>&1; then
        if wait_for_service "http://localhost:${REGISTRY_PORT}/health" "Service Registry"; then
            success_count=$((success_count + 1))
            echo "  ✓ Service Registry started and ready"
        else
            failed_services+=("Service Registry")
            echo -e "  ${RED}✗ Service Registry failed to become ready${NC}"
        fi
    else
        failed_services+=("Service Registry")
        echo -e "  ${RED}✗ Failed to start Service Registry${NC}"
    fi
fi
echo ""

# 2. Launch Distributed Router
echo -e "${BLUE}[2/4] Launching Distributed Router (port ${ROUTER_PORT})...${NC}"
if check_service_running "${LOG_DIR}/router.pid" "Distributed Router"; then
    echo "  Skipping (already running)"
    success_count=$((success_count + 1))
else
    if ./launch_router.sh > /dev/null 2>&1; then
        if wait_for_service "http://localhost:${ROUTER_PORT}/health" "Distributed Router"; then
            success_count=$((success_count + 1))
            echo "  ✓ Distributed Router started and ready"
        else
            failed_services+=("Distributed Router")
            echo -e "  ${RED}✗ Distributed Router failed to become ready${NC}"
        fi
    else
        failed_services+=("Distributed Router")
        echo -e "  ${RED}✗ Failed to start Distributed Router${NC}"
    fi
fi
echo ""

# 3. Launch Babysitter for 9g8b model
echo -e "${BLUE}[3/4] Launching Enhanced Babysitter (9g8b)...${NC}"
if check_service_running "${LOG_DIR}/babysitter_8100.pid" "Babysitter (9g8b)"; then
    echo "  Skipping (already running)"
    success_count=$((success_count + 1))
else
    if ./launch_babysitter_9g8b.sh > /dev/null 2>&1; then
        # Wait a bit longer for babysitter as it needs to start the InfiniLM server
        echo -n "Waiting for Babysitter (9g8b) to be ready..."
        if wait_for_service "http://localhost:8101/health" "Babysitter (9g8b)"; then
            success_count=$((success_count + 1))
            echo "  ✓ Babysitter (9g8b) started and ready"
        else
            failed_services+=("Babysitter (9g8b)")
            echo -e "  ${YELLOW}⚠ Babysitter (9g8b) started but may still be loading model${NC}"
            echo "  (Model loading can take several minutes - check logs if needed)"
            success_count=$((success_count + 1))  # Count as success since it started
        fi
    else
        failed_services+=("Babysitter (9g8b)")
        echo -e "  ${RED}✗ Failed to start Babysitter (9g8b)${NC}"
    fi
fi
echo ""

# 4. Launch Babysitter for Qwen model
echo -e "${BLUE}[4/4] Launching Enhanced Babysitter (Qwen)...${NC}"
if check_service_running "${LOG_DIR}/babysitter_8200.pid" "Babysitter (Qwen)"; then
    echo "  Skipping (already running)"
    success_count=$((success_count + 1))
else
    if ./launch_babysitter_qwen.sh > /dev/null 2>&1; then
        # Wait a bit longer for babysitter as it needs to start the InfiniLM server
        echo -n "Waiting for Babysitter (Qwen) to be ready..."
        if wait_for_service "http://localhost:8201/health" "Babysitter (Qwen)"; then
            success_count=$((success_count + 1))
            echo "  ✓ Babysitter (Qwen) started and ready"
        else
            failed_services+=("Babysitter (Qwen)")
            echo -e "  ${YELLOW}⚠ Babysitter (Qwen) started but may still be loading model${NC}"
            echo "  (Model loading can take several minutes - check logs if needed)"
            success_count=$((success_count + 1))  # Count as success since it started
        fi
    else
        failed_services+=("Babysitter (Qwen)")
        echo -e "  ${RED}✗ Failed to start Babysitter (Qwen)${NC}"
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
echo "  curl http://localhost:8101/health  # Babysitter (9g8b)"
echo "  curl http://localhost:8201/health  # Babysitter (Qwen)"
echo ""
echo "To stop all services:"
echo "  ./stop_all.sh"
echo ""
