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

# Function to kill process tree (parent and all children)
kill_tree() {
    local pid=$1
    local signal=${2:-TERM}

    if [ -z "${pid}" ] || ! ps -p ${pid} > /dev/null 2>&1; then
        return 0
    fi

    # Use pkill to kill the process tree (more reliable)
    # First try to get children and kill them recursively
    local children=$(ps -o pid= --ppid ${pid} 2>/dev/null | tr -d ' ')

    # Kill children first
    if [ -n "${children}" ]; then
        for child in ${children}; do
            if [ -n "${child}" ] && ps -p ${child} > /dev/null 2>&1; then
                kill_tree ${child} ${signal}
            fi
        done
    fi

    # Kill the parent process
    if ps -p ${pid} > /dev/null 2>&1; then
        kill -${signal} ${pid} 2>/dev/null
    fi
}

# Function to kill processes by pattern (for orphaned processes)
kill_by_pattern() {
    local pattern=$1
    local name=$2

    # Find processes matching the pattern
    local pids=$(pgrep -f "${pattern}" 2>/dev/null)

    if [ -z "${pids}" ]; then
        return 0
    fi

    echo -n "  Killing ${name} processes..."
    for pid in ${pids}; do
        # Kill the process tree
        kill_tree ${pid} TERM
    done

    # Wait a bit
    sleep 2

    # Force kill any remaining
    pids=$(pgrep -f "${pattern}" 2>/dev/null)
    if [ -n "${pids}" ]; then
        for pid in ${pids}; do
            kill_tree ${pid} KILL
        done
        sleep 1
    fi

    echo -e " ${GREEN}[done]${NC}"
}

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

    # Kill the process tree (parent and all children)
    kill_tree ${pid} TERM

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
        kill_tree ${pid} KILL
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
    # Find all babysitter PID files (handles both old and new naming: babysitter_8100.pid or babysitter_9g8b_8100.pid)
    for pid_file in "${LOG_DIR}"/babysitter_*.pid; do
        if [ -f "${pid_file}" ]; then
            # Extract identifier from filename for display
            # e.g., logs/babysitter_8100.pid -> 8100, logs/babysitter_9g8b_8100.pid -> 9g8b_8100
            identifier=$(basename "${pid_file}" .pid | sed 's/babysitter_//')

            if stop_service "Enhanced Babysitter" "${pid_file}" " (${identifier})"; then
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

# 4. Kill any orphaned InfiniLM processes that might still be holding GPU resources
echo "[4/4] Cleaning up orphaned InfiniLM processes..."
# Kill Python InfiniLM server processes
if pgrep -f "launch_server.py.*--port" > /dev/null 2>&1; then
    kill_by_pattern "launch_server.py.*--port" "InfiniLM (Python)"
fi

# Kill Rust InfiniLM service processes
if pgrep -f "xtask.*service" > /dev/null 2>&1 || pgrep -f "cargo.*xtask.*service" > /dev/null 2>&1; then
    kill_by_pattern "xtask.*service" "InfiniLM-Rust (xtask)"
    kill_by_pattern "cargo.*xtask.*service" "InfiniLM-Rust (cargo)"
fi

# Check if any processes are still holding ports 8100, 8200 (InfiniLM server ports)
for port in 8100 8200; do
    pid=$(lsof -ti:${port} 2>/dev/null || fuser ${port}/tcp 2>/dev/null | awk '{print $NF}')
    if [ -n "${pid}" ]; then
        echo -n "  Killing process holding port ${port} (PID: ${pid})..."
        kill_tree ${pid} TERM
        sleep 2
        if ps -p ${pid} > /dev/null 2>&1; then
            kill_tree ${pid} KILL
        fi
        echo -e " ${GREEN}[done]${NC}"
    fi
done
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
