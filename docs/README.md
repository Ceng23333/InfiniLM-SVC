# InfiniLM-SVC Maintenance Guide

This document provides instructions for maintaining and operating the InfiniLM Service Virtualization and Control (SVC) system. The system implements a distributed architecture with centralized service discovery and load balancing.

## Architecture Overview

The InfiniLM-SVC system consists of three main components:

```
┌─────────────────────────────────────────────────────────┐
│                    Local Server                         │
│  ┌──────────────┐    ┌──────────────┐                   │
│  │   Registry   │    │    Router    │                   │
│  │  (Port 8081) │    │  (Port 8080) │                   │
│  └──────────────┘    └──────────────┘                   │
└─────────────────────────────────────────────────────────┘
                          │
                          │ Service Discovery & Routing
                          │
┌─────────────────────────────────────────────────────────┐
│              Local & Remote Servers                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  Babysitter  │  │  Babysitter  │  │  Babysitter  │  │
│  │   + xtask    │  │   + xtask    │  │   + xtask    │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### Component Roles

1. **Service Registry** - Centralized service discovery and health monitoring
2. **Distributed Router** - Load balancer with model-aware routing and request proxying
3. **Enhanced Babysitter** - Service management wrapper for InfiniLM services
4. **xtask** - Provides OpenAI API interface (`/chat/completions`, `/models`)

## Implementation Versions

- **Python Version** (Original): Full-featured Python implementation
- **Rust Version** (Recommended): High-performance Rust implementation with better reliability and lower resource usage

Both versions provide the same API and functionality.

## Quick Start

### Rust Version (Recommended)

**Build:**
```bash
cd rust
cargo build --release --bin infini-registry --bin infini-router --bin infini-babysitter
```

**Launch All Services:**
```bash
# Configure babysitter configs
export BABYSITTER_CONFIGS=("config/babysitter1.toml" "config/babysitter2.toml")

# Optional: Override ports and settings
export REGISTRY_PORT=18000
export ROUTER_PORT=8000

# Launch
./script/launch_all_rust.sh
```

**Configuration Options:**
- `REGISTRY_PORT` - Registry port (default: 18000)
- `ROUTER_PORT` - Router port (default: 8000)
- `ROUTER_REGISTRY_URL` - Registry URL for router (default: http://localhost:18000)
- `BABYSITTER_CONFIGS` - Array of TOML config files for babysitters
- `REGISTRY_HEALTH_INTERVAL`, `REGISTRY_HEALTH_TIMEOUT`, `REGISTRY_CLEANUP_INTERVAL` - Registry settings
- `ROUTER_HEALTH_INTERVAL`, `ROUTER_HEALTH_TIMEOUT`, `ROUTER_REGISTRY_SYNC_INTERVAL` - Router settings

**Docker Usage:**
```bash
docker run -d \
  -e REGISTRY_PORT=18000 \
  -e ROUTER_PORT=8000 \
  -e BABYSITTER_CONFIGS="config/babysitter1.toml config/babysitter2.toml" \
  -v /path/to/config:/app/config \
  -v /path/to/logs:/app/logs \
  infinilm-svc-rust
```

### Python Version

**Launch All Services:**
```bash
./script/launch_all.sh
```

**Individual Services:**
- `./script/launch_registry.sh` - Service Registry
- `./script/launch_router.sh` - Distributed Router
- `./script/launch_babysitter.sh` - Enhanced Babysitter (template)
- `./script/launch_babysitter_9g8b.sh` - Babysitter for 9g8b model
- `./script/launch_babysitter_qwen.sh` - Babysitter for Qwen model

## Service Management

### Start Services

**Rust Version:**
```bash
./script/launch_all_rust.sh
```

**Python Version:**
```bash
./script/launch_all.sh
```

### Stop Services

```bash
./script/stop_all.sh
```

**Individual Stop:**
- `./script/stop_registry.sh` - Stop Registry
- `./script/stop_router.sh` - Stop Router
- `./script/stop_babysitter.sh` - Stop all Babysitters
- `./script/stop_babysitter.sh <PORT>` - Stop specific Babysitter

### Health Checks

```bash
# Registry
curl http://localhost:18000/health
curl http://localhost:18000/services

# Router
curl http://localhost:8000/health
curl http://localhost:8000/models
curl http://localhost:8000/services

# Babysitter (port + 1)
curl http://localhost:8001/health
```

## Configuration

### Rust Babysitter Configuration (TOML)

Create a TOML config file in `config/` directory:

```toml
name = "babysitter-service-1"
port = 8000
registry_url = "http://localhost:18000"

[babysitter]
max_restarts = 10
restart_delay = 2
heartbeat_interval = 10

[backend]
type = "command"
command = "python"
args = ["/path/to/service.py", "--port", "8000"]
work_dir = "/path/to/workdir"
env = { "CUDA_VISIBLE_DEVICES" = "0" }
```

### Python Babysitter Configuration

Edit the configuration section in `launch_babysitter.sh`:

```bash
PORT=8000
SERVICE_NAME="service-1"
SERVICE_TYPE="InfiniLM"  # or "InfiniLM-Rust"
MODEL_PATH="/path/to/model"
REGISTRY_URL="http://localhost:18000"
HPCC_VISIBLE_DEVICES="0"
```

## Multi-Instance Deployment

### Rust Version

Create multiple TOML config files and specify them:

```bash
export BABYSITTER_CONFIGS=(
  "config/babysitter1.toml"
  "config/babysitter2.toml"
  "config/babysitter3.toml"
)
./script/launch_all_rust.sh
```

### Python Version

Duplicate and customize launch scripts:

```bash
cp script/launch_babysitter.sh script/launch_babysitter_8000.sh
cp script/launch_babysitter.sh script/launch_babysitter_8001.sh
# Edit each script's configuration section
./script/launch_babysitter_8000.sh
./script/launch_babysitter_8001.sh
```

## Key Features

### Model-Aware Load Balancing

The router routes requests to services based on the requested model:

- Services register their supported models during startup
- Router aggregates models from all healthy services
- Requests are load-balanced among services supporting the requested model
- Returns 503 if no service supports the requested model

### Service Discovery

- Services automatically register with the registry on startup
- Registry tracks service health and metadata
- Router syncs service list from registry periodically
- Unhealthy services are automatically excluded from routing

### Health Monitoring

- Registry performs periodic health checks on registered services
- Router monitors service health and routes only to healthy services
- Babysitter monitors managed service health and restarts on failure

## Monitoring

### Service Status

```bash
# List all registered services
curl http://localhost:18000/services

# Router statistics
curl http://localhost:8000/stats

# Service health
curl http://localhost:8000/services
```

### Logs

Logs are stored in `logs/` directory:
- `logs/registry_*.log` - Registry logs
- `logs/router_*.log` - Router logs
- `logs/babysitter_*.log` - Babysitter logs

```bash
# Monitor logs
tail -f logs/registry_*.log
tail -f logs/router_*.log
tail -f logs/babysitter_*.log
```

## Troubleshooting

### Common Issues

**Router returns 503 "No healthy services available"**
- Check registry: `curl http://localhost:18000/services`
- Verify services are registered and healthy
- Check service logs for errors

**Service not registering**
- Verify registry is running: `curl http://localhost:18000/health`
- Check network connectivity
- Review service configuration

**Model not found**
- Check available models: `curl http://localhost:8000/models`
- Verify service model registration in registry
- Check babysitter logs for model fetching errors

## Docker Deployment

### Rust Version

```bash
# Build image
docker build -t infinilm-svc-rust -f docker/Dockerfile.rust .

# Run container
docker run -d \
  -e REGISTRY_PORT=18000 \
  -e ROUTER_PORT=8000 \
  -e BABYSITTER_CONFIGS="config/babysitter1.toml" \
  -v $(pwd)/config:/app/config \
  -v $(pwd)/logs:/app/logs \
  infinilm-svc-rust
```

### Python Version

```bash
# Build image
docker build -t infinilm-svc -f docker/Dockerfile .

# Run container
docker run -d \
  -p 8000:8000 -p 8080:8080 -p 8081:8081 \
  infinilm-svc
```

## Additional Documentation

- **Integration Tests**: `rust/tests/integration/README.md`
- **Babysitter Guide**: `rust/src/bin/README.md`
- **Distributed Deployment**: `docs/DISTRIBUTED_DEPLOYMENT_README.md`
- **Multi-Service Guide**: `docs/MULTI_SERVICE_README.md`

## Requirements

### Rust Version
- Rust 1.70+ (nightly recommended)
- Cargo

### Python Version
- Python 3.8+
- Dependencies: `aiohttp`, `requests`

## Support

For detailed configuration examples and advanced usage, see the individual component documentation in the `docs/` directory.
