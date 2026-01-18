#!/bin/bash

# Distributed InfiniLM Services Deployment Script
# Deploys services across multiple servers with service discovery

set -e

# Script directory (auto-detected)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Default values
DEPLOYMENT_CONFIG="${PROJECT_ROOT}/config/deployment_configs"
REGISTRY_PORT=8081
ROUTER_PORT=8080
INFINILM_ROOT=/root/zenghua/repos/InfiniLM
SERVICE_DIR=/root/zenghua/repos/service

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] COMMAND"
    echo ""
    echo "Commands:"
    echo "  start-registry     Start the service registry"
    echo "  start-router       Start the distributed router"
    echo "  start-services     Start services on local server"
    echo "  stop-all           Stop all services"
    echo "  status             Show status of all services"
    echo "  deploy-remote      Deploy services to remote servers"
    echo "  generate-config    Generate nginx configuration"
    echo ""
    echo "Options:"
    echo "  -c, --config-dir DIR    Deployment config directory (default: deployment_configs)"
    echo "  -r, --registry-port PORT Registry port (default: 8081)"
    echo "  -p, --router-port PORT   Router port (default: 8080)"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 start-registry        # Start service registry"
    echo "  $0 start-router          # Start distributed router"
    echo "  $0 start-services        # Start local services"
    echo "  $0 generate-config       # Generate nginx config"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--config-dir)
            DEPLOYMENT_CONFIG="$2"
            shift 2
            ;;
        -r|--registry-port)
            REGISTRY_PORT="$2"
            shift 2
            ;;
        -p|--router-port)
            ROUTER_PORT="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        start-registry|start-router|start-services|stop-all|status|deploy-remote|generate-config)
            COMMAND="$1"
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            echo "Unexpected argument: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Check if command is provided
if [[ -z "$COMMAND" ]]; then
    echo "Error: Command is required"
    show_usage
    exit 1
fi

# Check if deployment config directory exists
if [[ ! -d "$DEPLOYMENT_CONFIG" ]]; then
    echo "Error: Deployment config directory '$DEPLOYMENT_CONFIG' not found"
    exit 1
fi

# Create logs directory
mkdir -p logs

# Function to start service registry
start_registry() {
    echo "Starting service registry on port $REGISTRY_PORT..."

    # Check if registry config exists
    local registry_config="$DEPLOYMENT_CONFIG/registry_config.json"
    if [[ -f "$registry_config" ]]; then
        local config_port=$(jq -r '.registry.port // 8081' "$registry_config")
        local health_interval=$(jq -r '.registry.health_interval // 30' "$registry_config")
        local health_timeout=$(jq -r '.registry.health_timeout // 5' "$registry_config")
        local cleanup_interval=$(jq -r '.registry.cleanup_interval // 60' "$registry_config")

        cd "${PROJECT_ROOT}" || exit 1
        nohup python3 python/service_registry.py \
            --port "$config_port" \
            --health-interval "$health_interval" \
            --health-timeout "$health_timeout" \
            --cleanup-interval "$cleanup_interval" > "${PROJECT_ROOT}/logs/registry.log" 2>&1 &

        local pid=$!
        mkdir -p "${PROJECT_ROOT}/logs"
        echo "$pid" > "${PROJECT_ROOT}/logs/registry.pid"
        echo "Service registry started with PID: $pid"
    else
        cd "${PROJECT_ROOT}" || exit 1
        nohup python3 python/service_registry.py --port "$REGISTRY_PORT" > "${PROJECT_ROOT}/logs/registry.log" 2>&1 &
        local pid=$!
        mkdir -p "${PROJECT_ROOT}/logs"
        echo "$pid" > "${PROJECT_ROOT}/logs/registry.pid"
        echo "Service registry started with PID: $pid"
    fi
}

# Function to start distributed router
start_router() {
    echo "Starting distributed router on port $ROUTER_PORT..."

    # Check if router config exists
    local router_config="$DEPLOYMENT_CONFIG/router_config.json"
    if [[ -f "$router_config" ]]; then
        local config_port=$(jq -r '.router.port // 8080' "$router_config")
        local registry_url=$(jq -r '.router.registry_url // ""' "$router_config")
        local static_services_file="$DEPLOYMENT_CONFIG/router_config.json"

        cd "${PROJECT_ROOT}" || exit 1
        if [[ -n "$registry_url" ]]; then
            nohup python3 python/distributed_router.py \
                --router-port "$config_port" \
                --registry-url "$registry_url" \
                --static-services "$static_services_file" > "${PROJECT_ROOT}/logs/distributed_router.log" 2>&1 &
        else
            nohup python3 python/distributed_router.py \
                --router-port "$config_port" \
                --static-services "$static_services_file" > "${PROJECT_ROOT}/logs/distributed_router.log" 2>&1 &
        fi

        local pid=$!
        mkdir -p "${PROJECT_ROOT}/logs"
        echo "$pid" > "${PROJECT_ROOT}/logs/distributed_router.pid"
        echo "Distributed router started with PID: $pid"
    else
        echo "Error: Router config file not found at $router_config"
        exit 1
    fi
}

# Function to start local services
start_services() {
    echo "Starting local services..."

    # Get server hostname/IP
    local server_ip=$(hostname -I | awk '{print $1}')
    local server_hostname=$(hostname)

    # Find config files for this server
    local config_files=()
    for config_file in "$DEPLOYMENT_CONFIG"/*_services.json; do
        if [[ -f "$config_file" ]]; then
            # Check if this config is for the current server
            local config_host=$(jq -r '.services[0].host // ""' "$config_file")
            if [[ "$config_host" == "$server_ip" ]] || [[ "$config_host" == "$server_hostname" ]]; then
                config_files+=("$config_file")
            fi
        fi
    done

    if [[ ${#config_files[@]} -eq 0 ]]; then
        echo "No service configurations found for this server ($server_ip/$server_hostname)"
        echo "Available configurations:"
        for config_file in "$DEPLOYMENT_CONFIG"/*_services.json; do
            if [[ -f "$config_file" ]]; then
                local config_host=$(jq -r '.services[0].host // "unknown"' "$config_file")
                echo "  $config_file (host: $config_host)"
            fi
        done
        exit 1
    fi

    # Start services from each config file
    for config_file in "${config_files[@]}"; do
        echo "Starting services from $config_file..."

        # Extract services from config
        local services=$(jq -r '.services[] | "\(.name):\(.host):\(.port):\(.weight // 1)"' "$config_file")

        for service_spec in $services; do
            IFS=':' read -r name host port weight <<< "$service_spec"

            # Find corresponding config file
            local service_config=""
            case "$name" in
                *gpu1*) service_config="service_instance1.toml" ;;
                *gpu2*) service_config="service_instance2.toml" ;;
                *gpu3*) service_config="service_instance1.toml" ;;
                *gpu4*) service_config="service_instance2.toml" ;;
                *) service_config="service.toml" ;;
            esac

            if [[ -f "$service_config" ]]; then
                echo "Starting $name on port $port with config $service_config"

                # Start service with registry registration
                local registry_url="http://localhost:$REGISTRY_PORT/services"
                nohup ./start_service_instance.sh \
                    --port "$port" \
                    --config "$service_config" \
                    --name "$name" \
                    --registry "$registry_url" > "${PROJECT_ROOT}/logs/${name}.log" 2>&1 &

                local pid=$!
                mkdir -p "${PROJECT_ROOT}/logs"
                echo "$pid" > "${PROJECT_ROOT}/logs/${name}.pid"
                echo "$name started with PID: $pid"
            else
                echo "Warning: Config file $service_config not found for service $name"
            fi
        done
    done
}

# Function to stop all services
stop_all() {
    echo "Stopping all services..."

    # Stop router
    if [[ -f "${PROJECT_ROOT}/logs/distributed_router.pid" ]]; then
        local router_pid=$(cat "${PROJECT_ROOT}/logs/distributed_router.pid")
        if kill -0 "$router_pid" 2>/dev/null; then
            echo "Stopping distributed router (PID: $router_pid)..."
            kill "$router_pid"
        fi
        rm -f logs/distributed_router.pid
    fi

    # Stop registry
    if [[ -f "${PROJECT_ROOT}/logs/registry.pid" ]]; then
        local registry_pid=$(cat "${PROJECT_ROOT}/logs/registry.pid")
        if kill -0 "$registry_pid" 2>/dev/null; then
            echo "Stopping service registry (PID: $registry_pid)..."
            kill "$registry_pid"
        fi
        rm -f logs/registry.pid
    fi

    # Stop all service instances
    for pid_file in "${PROJECT_ROOT}/logs"/*.pid; do
        if [[ -f "$pid_file" ]]; then
            local service_name=$(basename "$pid_file" .pid)
            local service_pid=$(cat "$pid_file")
            if kill -0 "$service_pid" 2>/dev/null; then
                echo "Stopping $service_name (PID: $service_pid)..."
                kill "$service_pid"
            fi
            rm -f "$pid_file"
        fi
    done

    echo "All services stopped"
}

# Function to show status
status() {
    echo "Service Status:"
    echo "==============="

    # Check registry
    if [[ -f "${PROJECT_ROOT}/logs/registry.pid" ]]; then
        local registry_pid=$(cat "${PROJECT_ROOT}/logs/registry.pid")
        if kill -0 "$registry_pid" 2>/dev/null; then
            echo "✓ Service Registry: Running (PID: $registry_pid)"
        else
            echo "✗ Service Registry: Not running"
        fi
    else
        echo "✗ Service Registry: Not started"
    fi

    # Check router
    if [[ -f "${PROJECT_ROOT}/logs/distributed_router.pid" ]]; then
        local router_pid=$(cat "${PROJECT_ROOT}/logs/distributed_router.pid")
        if kill -0 "$router_pid" 2>/dev/null; then
            echo "✓ Distributed Router: Running (PID: $router_pid)"
        else
            echo "✗ Distributed Router: Not running"
        fi
    else
        echo "✗ Distributed Router: Not started"
    fi

    # Check service instances
    echo ""
    echo "Service Instances:"
    for pid_file in "${PROJECT_ROOT}/logs"/*.pid; do
        if [[ -f "$pid_file" ]]; then
            local service_name=$(basename "$pid_file" .pid)
            local service_pid=$(cat "$pid_file")
            if kill -0 "$service_pid" 2>/dev/null; then
                echo "✓ $service_name: Running (PID: $service_pid)"
            else
                echo "✗ $service_name: Not running"
            fi
        fi
    done

    # Show registry status if available
    if [[ -f "${PROJECT_ROOT}/logs/registry.pid" ]]; then
        local registry_pid=$(cat "${PROJECT_ROOT}/logs/registry.pid")
        if kill -0 "$registry_pid" 2>/dev/null; then
            echo ""
            echo "Registry Services:"
            curl -s "http://localhost:$REGISTRY_PORT/services" | jq -r '.services[] | "\(.name): \(.status) (\(.host):\(.port))"' 2>/dev/null || echo "Could not fetch registry status"
        fi
    fi
}

# Function to generate nginx configuration
generate_config() {
    echo "Generating nginx configuration..."

    # Get registry URL from router config
    local router_config="$DEPLOYMENT_CONFIG/router_config.json"
    local registry_url=""
    if [[ -f "$router_config" ]]; then
        registry_url=$(jq -r '.router.registry_url // ""' "$router_config")
    fi

    if [[ -n "$registry_url" ]]; then
        # Generate config from registry
        echo "Fetching services from registry: $registry_url"
        curl -s "$registry_url/services?healthy=true" | jq -r '.services[] | "\(.name):\(.host):\(.port):\(.weight // 1)"' > /tmp/services.txt

        if [[ -s /tmp/services.txt ]]; then
            local services_list=$(tr '\n' ',' < /tmp/services.txt | sed 's/,$//')
            cd "${PROJECT_ROOT}" || exit 1
            python3 python/generate_nginx_config.py \
                --router-port "$ROUTER_PORT" \
                --services "$services_list" \
                --output "${PROJECT_ROOT}/nginx_distributed.conf"
            echo "Nginx configuration generated: ${PROJECT_ROOT}/nginx_distributed.conf"
        else
            echo "No services found in registry"
        fi
        rm -f /tmp/services.txt
    else
        echo "No registry URL configured, using static configuration"
        # Use static configuration
        local static_config="$DEPLOYMENT_CONFIG/router_config.json"
        if [[ -f "$static_config" ]]; then
            cd "${PROJECT_ROOT}" || exit 1
            python3 python/generate_nginx_config.py \
                --config-file "$static_config" \
                --output "${PROJECT_ROOT}/nginx_distributed.conf"
            echo "Nginx configuration generated: ${PROJECT_ROOT}/nginx_distributed.conf"
        else
            echo "Error: No static configuration found"
            exit 1
        fi
    fi
}

# Main execution
case "$COMMAND" in
    start-registry)
        start_registry
        ;;
    start-router)
        start_router
        ;;
    start-services)
        start_services
        ;;
    stop-all)
        stop_all
        ;;
    status)
        status
        ;;
    generate-config)
        generate_config
        ;;
    deploy-remote)
        echo "Remote deployment not implemented yet"
        echo "Use SSH to run this script on remote servers"
        ;;
    *)
        echo "Unknown command: $COMMAND"
        show_usage
        exit 1
        ;;
esac
