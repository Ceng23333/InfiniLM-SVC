#!/bin/bash
# Graceful stop script for all InfiniLM-SVC services
# Stops Registry, Router, and all Babysitter instances

# Configuration
LOG_DIR="${LOG_DIR:-logs}"
TIMEOUT=10  # Wait up to 10 seconds for graceful shutdown per service

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to stop a service by PID file
stop_service() {
    local service_name=$1
    local pid_file=$2
    local extra_info=$3  # Optional extra info (e.g., port number)

    if [ ! -f "${pid_file}" ]; then
        if [ -n "${extra_info}" ]; then
            echo -e "${YELLOW}⚠ ${service_name}${extra_info} is not running (PID file not found)${NC}"
        else
            echo -e "${YELLOW}⚠ ${service_name} is not running (PID file not found)${NC}"
        fi
        return 1
    fi

    local pid=$(cat "${pid_file}")

    if [ -z "${pid}" ]; then
        echo -e "${RED}✗ Invalid PID file: ${pid_file}${NC}"
        rm -f "${pid_file}"
        return 1
    fi

    # Check if process is running
    if ! ps -p ${pid} > /dev/null 2>&1; then
        if [ -n "${extra_info}" ]; then
            echo -e "${YELLOW}⚠ ${service_name}${extra_info} is not running (process ${pid} not found)${NC}"
        else
            echo -e "${YELLOW}⚠ ${service_name} is not running (process ${pid} not found)${NC}"
        fi
        rm -f "${pid_file}"
        return 1
    fi

    if [ -n "${extra_info}" ]; then
        echo -n "Stopping ${service_name}${extra_info} (PID: ${pid})..."
    else
        echo -n "Stopping ${service_name} (PID: ${pid})..."
    fi

    # Send SIGTERM for graceful shutdown
    kill ${pid} 2>/dev/null

    # Wait for graceful shutdown
    count=0
    while ps -p ${pid} > /dev/null 2>&1 && [ ${count} -lt ${TIMEOUT} ]; do
        sleep 1
        count=$((count + 1))
        echo -n "."
    done

    # Check if process is still running
    if ps -p ${pid} > /dev/null 2>&1; then
        echo -e " ${YELLOW}[force kill]${NC}"
        kill -9 ${pid} 2>/dev/null
        sleep 1

        if ps -p ${pid} > /dev/null 2>&1; then
            echo -e "${RED}✗ Failed to stop ${service_name}${extra_info} (PID: ${pid})${NC}"
            return 1
        fi
    else
        echo -e " ${GREEN}[stopped]${NC}"
    fi

    # Clean up PID file
    rm -f "${pid_file}"
    return 0
}

# Main execution
echo "========================================"
echo "Stopping InfiniLM-SVC Services"
echo "========================================"
echo ""

# Create log directory if it doesn't exist
mkdir -p "${LOG_DIR}"

# Track results
stopped_count=0
failed_count=0
skipped_count=0

# 1. Stop Distributed Router
echo "[1/3] Stopping Distributed Router..."
if stop_service "Distributed Router" "${LOG_DIR}/router.pid"; then
    stopped_count=$((stopped_count + 1))
else
    skipped_count=$((skipped_count + 1))
fi
echo ""

# 2. Stop all Babysitter instances
echo "[2/3] Stopping Enhanced Babysitter instances..."
babysitter_stopped=0
babysitter_failed=0
babysitter_skipped=0

if [ -d "${LOG_DIR}" ]; then
    # Find all babysitter PID files
    for pid_file in "${LOG_DIR}"/babysitter_*.pid; do
        if [ -f "${pid_file}" ]; then
            # Extract port from filename (e.g., logs/babysitter_8000.pid -> 8000)
            port=$(basename "${pid_file}" | sed 's/babysitter_\([0-9]*\)\.pid/\1/')

            if stop_service "Enhanced Babysitter" "${pid_file}" " (port ${port})"; then
                babysitter_stopped=$((babysitter_stopped + 1))
                stopped_count=$((stopped_count + 1))
            else
                babysitter_skipped=$((babysitter_skipped + 1))
                skipped_count=$((skipped_count + 1))
            fi
        fi
    done
fi

if [ ${babysitter_stopped} -eq 0 ] && [ ${babysitter_failed} -eq 0 ] && [ ${babysitter_skipped} -eq 0 ]; then
    echo -e "${YELLOW}  No babysitter instances found${NC}"
fi
echo ""

# 3. Stop Service Registry (stop last to allow services to deregister)
echo "[3/3] Stopping Service Registry..."
if stop_service "Service Registry" "${LOG_DIR}/registry.pid"; then
    stopped_count=$((stopped_count + 1))
else
    skipped_count=$((skipped_count + 1))
fi
echo ""

# Summary
echo "========================================"
echo "Summary"
echo "========================================"
echo -e "${GREEN}✓ Stopped: ${stopped_count}${NC}"
if [ ${skipped_count} -gt 0 ]; then
    echo -e "${YELLOW}⚠ Skipped (not running): ${skipped_count}${NC}"
fi
if [ ${failed_count} -gt 0 ]; then
    echo -e "${RED}✗ Failed: ${failed_count}${NC}"
fi
echo ""

if [ ${stopped_count} -eq 0 ] && [ ${failed_count} -eq 0 ]; then
    echo "No services were running"
    exit 1
elif [ ${failed_count} -gt 0 ]; then
    exit 1
else
    echo "All services stopped successfully"
    exit 0
fi
