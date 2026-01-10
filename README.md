# InfiniLM-SVC Maintenance Guide

This document provides comprehensive instructions for maintaining and operating the InfiniLM Service Virtualization and Control (SVC) system. The system implements a distributed architecture with centralized service discovery and load balancing.

## Architecture Overview

The InfiniLM-SVC system consists of three main components deployed across local and remote servers:

```
┌─────────────────────────────────────────────────────────────────┐
│                        Local Server                             │
│  ┌─────────────────┐    ┌─────────────────┐                    │
│  │ Service Registry│    │ Distributed     │                    │
│  │ (Port 8081)     │    │ Router          │                    │
│  │                 │    │ (Port 8080)     │                    │
│  └─────────────────┘    └─────────────────┘                    │
└─────────────────────────────────────────────────────────────────┘
                                │
                                │ Service Discovery & Routing
                                │
┌─────────────────────────────────────────────────────────────────┐
│                    Local & Remote Servers                       │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────┐ │
│  │ Enhanced        │    │ Enhanced        │    │ Enhanced    │ │
│  │ Babysitter 1    │    │ Babysitter 2    │    │ Babysitter N│ │
│  │ + xtask         │    │ + xtask         │    │ + xtask     │ │
│  │ (Port 5002/5003)│    │ (Port 5004/5005)│    │ (Port 5xxx) │ │
│  └─────────────────┘    └─────────────────┘    └─────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Component Roles

1. **Service Registry** (Local Server)
   - Centralized service discovery and health monitoring
   - Manages service metadata and routing information
   - Provides REST API for service management

2. **Distributed Router** (Local Server)
   - Load balancer that routes OpenAI API requests to healthy services
   - Only routes to services with `type: "openai-api"` (xtask instances)
   - Supports both streaming and non-streaming responses
   - **Model-level load balancing**: Routes requests to services based on the requested model
   - Aggregates and exposes a unified `/models` endpoint from all registered services

3. **Enhanced Babysitter** (Local & Remote Servers)
   - Service management wrapper for InfiniLM-Rust services
   - Health checker and interaction wrapper for xtask
   - Registers both itself and xtask in the registry
   - **Does NOT proxy OpenAI requests** (architectural separation)

4. **xtask** (Local & Remote Servers)
   - Provides OpenAI API interface (`/chat/completions`, `/models`)
   - Registered separately with `type: "openai-api"`
   - Receives requests directly from router

## Quick Launch Scripts

The system provides convenient launch scripts for quick deployment. All scripts support configuration via variables at the top of each file and automatically create PID files for easy process management.

### Launch Scripts Overview

1. **`launch_registry.sh`** - Service Registry launcher
2. **`launch_router.sh`** - Distributed Router launcher
3. **`launch_babysitter.sh`** - Enhanced Babysitter launcher (template)
4. **`launch_babysitter_9g8b.sh`** - Enhanced Babysitter for 9g8b model (port 8100)
5. **`launch_babysitter_qwen.sh`** - Enhanced Babysitter for Qwen model (port 8200)
6. **`launch_all.sh`** - Launch all services in sequence (Registry → Router → Babysitter_9g8b → Babysitter_qwen)
7. **`stop_all.sh`** - Stop all services gracefully (Registry, Router, and all Babysitter instances)

### Using Launch Scripts

#### Quick Start: Launch All Services

**Launch all services in the correct order:**
```bash
cd /home/zenghua/repos/InfiniLM-SVC
./launch_all.sh
```

This script will:
- Launch Service Registry
- Wait for Registry to be ready (health check)
- Launch Distributed Router
- Wait for Router to be ready (health check)
- Launch Babysitter for 9g8b model (port 8100)
- Launch Babysitter for Qwen model (port 8200)
- Check service health endpoints
- Display a summary of launched services

**Features:**
- Ensures services start in the correct dependency order
- Waits for each service to be ready before launching the next
- Skips services that are already running (checks PID files)
- Provides status feedback and error reporting
- Shows colored output for easy status identification

**Example output:**
```
========================================
Launching All InfiniLM-SVC Services
========================================

[1/4] Launching Service Registry (port 18000)...
Waiting for Service Registry to be ready... [ready]
  ✓ Service Registry started and ready

[2/4] Launching Distributed Router (port 8000)...
Waiting for Distributed Router to be ready... [ready]
  ✓ Distributed Router started and ready

[3/4] Launching Enhanced Babysitter (9g8b)...
Waiting for Babysitter (9g8b) to be ready... [ready]
  ✓ Babysitter (9g8b) started and ready

[4/4] Launching Enhanced Babysitter (Qwen)...
Waiting for Babysitter (Qwen) to be ready... [ready]
  ✓ Babysitter (Qwen) started and ready

========================================
Launch Summary
========================================
✓ Successfully launched/verified: 4/4 services

All services launched successfully!
```

#### Individual Service Launch

#### 1. Service Registry

**Quick Start:**
```bash
cd /home/zenghua/repos/InfiniLM-SVC
./launch_registry.sh
```

**Configuration:**
Edit the configuration section at the top of `launch_registry.sh`:
```bash
REGISTRY_PORT=8081
HEALTH_INTERVAL=30
HEALTH_TIMEOUT=5
CLEANUP_INTERVAL=60
```

**Process Management:**
```bash
# Stop gracefully (recommended: use stop_all.sh)
./stop_registry.sh

# Or manually:
kill $(cat logs/registry.pid)

# Force kill
kill -9 $(cat logs/registry.pid)

# View logs
tail -f logs/registry_*.log
```

#### 2. Distributed Router

**Quick Start:**
```bash
cd /home/zenghua/repos/InfiniLM-SVC
./launch_router.sh
```

**Configuration:**
Edit the configuration section at the top of `launch_router.sh`:
```bash
ROUTER_PORT=8080
REGISTRY_URL="http://localhost:8081"
HEALTH_INTERVAL=30
HEALTH_TIMEOUT=5
MAX_ERRORS=3
REGISTRY_SYNC_INTERVAL=10
```

**Process Management:**
```bash
# Stop gracefully (recommended: use stop_all.sh)
./stop_router.sh

# Or manually:
kill $(cat logs/router.pid)

# Force kill
kill -9 $(cat logs/router.pid)

# View logs
tail -f logs/router_*.log
```

#### 3. Enhanced Babysitter

**Quick Start:**
```bash
cd /home/zenghua/repos/InfiniLM-SVC
./launch_babysitter.sh
```

**Configuration:**
Edit the configuration section at the top of `launch_babysitter.sh`:
```bash
# Service Configuration
HOST="localhost"
PORT=8000
SERVICE_NAME=""  # Leave empty for auto-generated name
SERVICE_TYPE="InfiniLM"  # Options: "InfiniLM" or "InfiniLM-Rust"

# Registry and Router URLs
REGISTRY_URL="http://localhost:8081"
ROUTER_URL="http://localhost:8080"

# InfiniLM Server Configuration (for SERVICE_TYPE="InfiniLM")
MODEL_PATH="/data-aisoft/zenghua/models/9g_8b_thinking"
DEV="metax"
NDEV=1
MAX_BATCH=3
REQUEST_TIMEOUT=30

# Environment Variables
HPCC_VISIBLE_DEVICES="1"
```

**Process Management:**
```bash
# Stop gracefully (recommended: use stop_all.sh)
./stop_babysitter.sh 8000

# Or manually:
kill $(cat logs/babysitter_8000.pid)

# Force kill
kill -9 $(cat logs/babysitter_8000.pid)

# View logs
tail -f logs/babysitter_*.log
```

### Stop All Services

**Quick Stop:**
```bash
cd /home/zenghua/repos/InfiniLM-SVC
./stop_all.sh
```

This script will:
- Stop Distributed Router
- Stop all Enhanced Babysitter instances
- Stop Service Registry (stops last to allow services to deregister)
- Display a summary of stopped services
- Use graceful shutdown (SIGTERM) with automatic fallback to SIGKILL if needed

**Individual Stop Scripts:**
- `./stop_registry.sh` - Stop Service Registry only
- `./stop_router.sh` - Stop Distributed Router only
- `./stop_babysitter.sh` - Stop all Babysitter instances
- `./stop_babysitter.sh 8000` - Stop Babysitter on port 8000 only

### Multi-Instance Deployment Guide

For deploying multiple service instances on the same or different servers, you can duplicate and customize `launch_babysitter.sh` for each instance.

#### Method 1: Duplicate Scripts (Recommended for Different Configurations)

**Step 1: Create Instance-Specific Scripts**

```bash
cd /home/zenghua/repos/InfiniLM-SVC

# Copy the launch script for each instance
cp launch_babysitter.sh launch_babysitter_8000.sh
cp launch_babysitter.sh launch_babysitter_8001.sh
cp launch_babysitter.sh launch_babysitter_8002.sh
```

**Step 2: Configure Each Script**

Edit each script's configuration section:

**`launch_babysitter_8000.sh`:**
```bash
PORT=8000
SERVICE_NAME="infiniLM-instance-1"
MODEL_PATH="/data-aisoft/zenghua/models/9g_8b_thinking"
HPCC_VISIBLE_DEVICES="0"
```

**`launch_babysitter_8001.sh`:**
```bash
PORT=8001
SERVICE_NAME="infiniLM-instance-2"
MODEL_PATH="/data-aisoft/zenghua/models/9g_8b_thinking"
HPCC_VISIBLE_DEVICES="1"
```

**`launch_babysitter_8002.sh`:**
```bash
PORT=8002
SERVICE_NAME="infiniLM-instance-3"
MODEL_PATH="/data-aisoft/zenghua/models/9g_8b_thinking"
HPCC_VISIBLE_DEVICES="2"
```

**Step 3: Launch All Instances**

```bash
# Launch each instance
./launch_babysitter_8000.sh
./launch_babysitter_8001.sh
./launch_babysitter_8002.sh
```

**Step 4: Verify Deployment**

```bash
# Check all services are registered
curl http://localhost:8081/services

# Check router stats
curl http://localhost:8080/stats

# Test each instance directly
curl http://localhost:8000/models
curl http://localhost:8001/models
curl http://localhost:8002/models
```

**Step 5: Manage Instances**

```bash
# Stop all services (recommended)
./stop_all.sh

# Stop specific babysitter instance
./stop_babysitter.sh 8000

# Stop all babysitter instances
./stop_babysitter.sh

# Or manually:
kill $(cat logs/babysitter_8000.pid)
kill $(cat logs/babysitter_8001.pid)
kill $(cat logs/babysitter_8002.pid)

# View logs for specific instance
tail -f logs/babysitter_8000_*.log
```

#### Method 2: Single Script with Command-Line Override (Advanced)

You can also modify the launch script to accept command-line arguments:

```bash
# Example: Launch with port override
PORT=8000 ./launch_babysitter.sh
PORT=8001 HPCC_VISIBLE_DEVICES="1" ./launch_babysitter.sh
```

#### Best Practices for Multi-Instance Deployment

1. **Port Management:**
   - Ensure each instance uses a unique port
   - Remember: Babysitter uses `PORT`, InfiniLM server uses `PORT`, and babysitter HTTP server uses `PORT+1`
   - Example: Instance on port 8000 uses ports 8000 (InfiniLM) and 8001 (babysitter)

2. **Resource Allocation:**
   - Use `HPCC_VISIBLE_DEVICES` to assign different GPUs to each instance
   - Monitor GPU memory usage: `ht-smi` or `nvidia-smi`
   - Adjust `MAX_BATCH` and `NDEV` based on available resources

3. **Service Naming:**
   - Use descriptive `SERVICE_NAME` values for easy identification
   - Names will appear in registry and router statistics

4. **Log Management:**
   - Each instance creates port-specific timestamped log files: `logs/babysitter_${PORT}_YYMMDDHHmm.log`
   - PID files are port-specific: `logs/babysitter_${PORT}.pid`
   - Use log rotation for production deployments

5. **Model Configuration:**
   - Each instance should serve a specific model (or set of models)
   - Model names are automatically derived from the model path directory name (like vLLM/llama.cpp)
   - Multiple instances can serve the same model for load balancing
   - The router automatically distributes requests for the same model across instances
   - Use `MODEL_NAME` in launch script to override the default model name if needed

5. **Model Configuration:**
   - Each instance should serve a specific model (or set of models)
   - Model names are automatically derived from the model path directory name
   - Multiple instances can serve the same model for load balancing
   - The router automatically distributes requests for the same model across instances

5. **Network Configuration:**
   - Ensure firewall rules allow all required ports
   - For remote servers, update `REGISTRY_URL` and `ROUTER_URL` with actual hostnames/IPs

6. **Health Monitoring:**
   ```bash
   # Check all babysitter health endpoints
   curl http://localhost:8001/health  # Instance 1 babysitter
   curl http://localhost:8003/health  # Instance 2 babysitter
   curl http://localhost:8005/health  # Instance 3 babysitter

   # Check all InfiniLM server endpoints
   curl http://localhost:8000/models  # Instance 1
   curl http://localhost:8002/models  # Instance 2
   curl http://localhost:8004/models  # Instance 3
   ```

#### Example: Deploying 3 Instances on Same Server

```bash
# Terminal 1: Start Registry
cd /home/zenghua/repos/InfiniLM-SVC
./launch_registry.sh

# Terminal 2: Start Router
./launch_router.sh

# Terminal 3: Start Instance 1 (GPU 0)
./launch_babysitter_8000.sh

# Terminal 4: Start Instance 2 (GPU 1)
./launch_babysitter_8001.sh

# Terminal 5: Start Instance 3 (GPU 2)
./launch_babysitter_8002.sh

# Verify all instances are running
curl http://localhost:8081/services | jq
```

#### Example: Deploying on Remote Servers

**On Remote Server (e.g., 192.168.1.100):**

```bash
# Edit launch_babysitter.sh
REGISTRY_URL="http://192.168.1.10:8081"  # Registry server IP
ROUTER_URL="http://192.168.1.10:8080"    # Router server IP
HOST="192.168.1.100"                      # This server's IP
PORT=8000
HPCC_VISIBLE_DEVICES="0"

# Launch
./launch_babysitter.sh
```

## System Maintenance

### 1. Service Registry Management

#### Starting the Registry

**Using Launch Script (Recommended):**
```bash
cd /home/zenghua/repos/InfiniLM-SVC
./launch_registry.sh
```

**Manual Start:**
```bash
cd /home/zenghua/repos/InfiniLM-SVC
source /root/miniconda3/etc/profile.d/conda.sh
conda activate infinilm-distributed
python3 service_registry.py --port 8081
```

#### Registry Health Check
```bash
curl http://localhost:8081/health
```

#### List Registered Services
```bash
curl http://localhost:8081/services
```

#### Registry Statistics
```bash
curl http://localhost:8081/stats
```

### 2. Distributed Router Management

#### Starting the Router

**Using Launch Script (Recommended):**
```bash
cd /home/zenghua/repos/InfiniLM-SVC
./launch_router.sh
```

**Manual Start:**
```bash
cd /home/zenghua/repos/InfiniLM-SVC
source /root/miniconda3/etc/profile.d/conda.sh
conda activate infinilm-distributed
python3 distributed_router.py --router-port 8080 --registry-url http://localhost:8081
```

#### Router Health Check
```bash
curl http://localhost:8080/health
```

#### Router Statistics
```bash
curl http://localhost:8080/stats
```

#### Test Router Functionality
```bash
# Test models endpoint (aggregates models from all services)
curl http://localhost:8080/models

# Test chat completions (non-streaming)
# Router automatically routes to a service that supports the requested model
curl -X POST http://localhost:8080/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "Qwen3-32B", "messages": [{"role": "user", "content": "Hello"}]}'
```

#### Model-Level Load Balancing

The router implements **model-aware load balancing**, which routes requests to services that support the specific model requested by the client.

**How It Works:**

1. **Model Discovery:**
   - Each service registers its supported models in the registry metadata when it starts
   - The router's `/models` endpoint aggregates models from all healthy services
   - Model names are deduplicated across services (same model on multiple services appears once in the aggregated list)

2. **Request Routing:**
   - When a request includes a `model` parameter (e.g., in `/chat/completions`), the router extracts it from the request body
   - The router filters services to only those that support the requested model
   - Requests are load-balanced using weighted round-robin among services supporting that model
   - If no service supports the requested model, the router returns HTTP 503 with an error message

3. **Load Balancing Behavior:**
   - **Per-Model Balancing:** Load balancing is performed separately for each model
   - **Weighted Selection:** Services can have different weights for priority-based routing
   - **Health-Aware:** Only healthy services are considered for routing
   - **Round-Robin:** Requests for the same model are distributed evenly across available services

**Example Scenario:**

```bash
# Service 1 (Port 8000): Supports model "Qwen3-32B"
# Service 2 (Port 8100): Supports model "Qwen3-32B"
# Service 3 (Port 8200): Supports model "GPT-4"

# Request for "Qwen3-32B" will be load-balanced between Service 1 and Service 2
curl -X POST http://localhost:8080/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "Qwen3-32B", "messages": [{"role": "user", "content": "Hello"}]}'

# Request for "GPT-4" will route only to Service 3
curl -X POST http://localhost:8080/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "GPT-4", "messages": [{"role": "user", "content": "Hello"}]}'

# View all available models (aggregated from all services)
curl http://localhost:8080/models
# Returns: {"object": "list", "data": [{"id": "Qwen3-32B", ...}, {"id": "GPT-4", ...}]}
```

**Model Registration:**

Services automatically register their models when they start:
- For InfiniLM services, the model name is derived from the model path directory name (consistent with vLLM/llama.cpp)
- Models are fetched from each service's `/models` endpoint during registration
- Model information is included in service metadata and tracked by the router
- Multiple instances serving the same model will automatically share load

**Benefits:**

- **Scalability:** Add more instances for a popular model to handle increased load
- **Efficiency:** Requests are routed only to services that can handle them
- **Flexibility:** Deploy different models on different services without configuration changes
- **Availability:** If one instance fails, requests automatically route to other instances serving the same model

### 3. Service Instance Management

#### Starting Enhanced Babysitter

**Using Launch Script (Recommended):**
```bash
cd /home/zenghua/repos/InfiniLM-SVC
# Edit launch_babysitter.sh configuration section, then:
./launch_babysitter.sh
```

**Manual Start (InfiniLM Python):**
```bash
cd /home/zenghua/repos/InfiniLM-SVC
python3 enhanced_babysitter.py \
  --path /data-aisoft/zenghua/models/9g_8b_thinking \
  --port 8000 \
  --service-type InfiniLM \
  --dev metax \
  --ndev 1 \
  --max-batch 3 \
  --request-timeout 30 \
  --registry http://localhost:8081 \
  --router http://localhost:8080
```

**Manual Start (InfiniLM-Rust):**
```bash
cd /home/zenghua/repos/InfiniLM-SVC
python3 enhanced_babysitter.py \
  --path /path/to/config.toml \
  --port 5002 \
  --service-type InfiniLM-Rust \
  --name real-service \
  --registry http://localhost:8081 \
  --router http://localhost:8080 \
  --host localhost
```

#### Service Health Checks
```bash
# Check babysitter health
curl http://localhost:5002/health

# Check xtask health (via babysitter)
curl http://localhost:5002/models

# Check xtask directly
curl http://localhost:5003/health
```

### 4. Network Status

#### Firewall Configuration
The system requires specific ports to be open for proper operation. Use `firewall-cmd` to manage firewall rules:

```bash
# List currently open ports
firewall-cmd --list-ports

# Add required ports for InfiniLM services
firewall-cmd --permanent --add-port=8080/tcp  # Router service
firewall-cmd --permanent --add-port=8081/tcp  # Registry service
firewall-cmd --permanent --add-port=5002/tcp  # Babysitter service
firewall-cmd --permanent --add-port=5003/tcp  # Main service (xtask)

# Reload firewall rules
firewall-cmd --reload

# Verify ports are open
firewall-cmd --list-ports
```

### 4. Configuration Management

#### Service Configuration Template
The system uses Jinja2-like templates for generating service configurations:

**Template Location:** `templates/service.toml.template`
**Configuration Source:** `deployment_configs/test_services.json`

#### Generating Service Configuration
```bash
python3 render_service_config.py \
  --config deployment_configs/test_services.json \
  --output service_generated.toml
```

#### Example Configuration (test_services.json)
```json
{
  "services": [
    {
      "name": "Qwen3-32B",
      "model": {
        "path": "/root/zenghua/Qwen3-F16.gguf",
        "max_tokens": 2048,
        "temperature": 0.7,
        "top_p": 0.9,
        "top_k": 40,
        "repetition_penalty": 1.1,
        "think": false,
        "max_sessions": 100
      },
      "gpu": {
        "devices": [4, 5, 6, 7]
      }
    }
  ]
}
```

## Monitoring and Troubleshooting

### 1. System Validation

#### Run Complete Validation Pipeline
```bash
cd /root/zenghua/repos/InfiniLM-SVC
source /root/miniconda3/etc/profile.d/conda.sh
conda activate infinilm-distributed
python3 validate_integration.py
```

The validation pipeline tests:
1. Registry startup and health
2. Router startup and health
3. Mock service startup and registration
4. Real service (babysitter + xtask) startup
5. Router integration with round-robin testing
6. Service deregistration and cleanup

#### Round-Robin Pattern Testing
The validation includes a specific round-robin test pattern:
- **Pattern:** [non-stream, non-stream, stream, stream]
- **Expected:** 1st and 3rd to real service, 2nd and 4th to mock service
- **Purpose:** Verify load balancing works correctly across services

### 2. Log Management

#### Log Locations
- **Registry:** `logs/registry_YYMMDDHHmm.log`
- **Router:** `logs/router_YYMMDDHHmm.log`
- **Babysitter:** `logs/babysitter_YYMMDDHHmm.log`
- **PID Files:** `logs/registry.pid`, `logs/router.pid`, `logs/babysitter_${PORT}.pid`
- **Validation:** Console output with detailed step-by-step results

#### Log Monitoring
```bash
# Monitor registry logs
tail -f logs/registry_*.log

# Monitor router logs
tail -f logs/router_*.log

# Monitor babysitter logs
tail -f logs/babysitter_*.log

# Monitor specific instance
tail -f logs/babysitter_8000_*.log
```

### 3. Common Issues and Solutions

#### Issue: Router Returns 503 "No OpenAI API services available"
**Cause:** No services with `type: "openai-api"` are registered or healthy
**Solution:**
1. Check registry: `curl http://localhost:8081/services`
2. Verify xtask services are registered with correct type
3. Check service health: `curl http://localhost:5003/health`

#### Issue: Streaming Responses Fail
**Cause:** Router not properly handling Server-Sent Events (SSE)
**Solution:**
1. Verify router is updated with streaming support
2. Check that router properly forwards chunked responses
3. Test with non-streaming first, then streaming

#### Issue: Service Registration Fails
**Cause:** Registry not running or network connectivity issues
**Solution:**
1. Check registry health: `curl http://localhost:8081/health`
2. Verify network connectivity between services
3. Check service configuration and metadata

#### Issue: Router Returns 503 "No healthy services available for model 'X'"
**Cause:** No services are registered that support the requested model
**Solution:**
1. Check available models: `curl http://localhost:8080/models`
2. Verify services are registered with the correct model information: `curl http://localhost:8081/services`
3. Check that service metadata includes the `models` field with the correct model ID
4. Ensure the model name in the request matches exactly (case-sensitive)
5. Verify services have successfully fetched and registered their model information during startup
6. Check babysitter logs for model fetching errors (e.g., 502 errors during registration)

#### Issue: Model Not Found in Router's /models Endpoint
**Cause:** Services may not have registered their models correctly
**Solution:**
1. Check individual service models: `curl http://localhost:8000/models`
2. Verify babysitter is fetching models from the InfiniLM server during registration
3. Check babysitter logs for model fetching errors or timeout issues
4. Ensure model name is correctly derived from the model path or explicitly specified via `--model-name`
5. Wait for services to fully start (model loading can take several minutes)

#### Issue: Model Loading Fails
**Cause:** Incorrect model path or insufficient GPU memory
**Solution:**
1. Verify model file exists: `ls -la /root/zenghua/Qwen3-F16.gguf`
2. Check GPU availability: `ht-smi`
3. Update configuration with correct model path

### 4. Performance Monitoring

#### Service Statistics
```bash
# Registry statistics
curl http://localhost:8081/stats

# Router statistics
curl http://localhost:8080/stats

# Service-specific statistics
curl http://localhost:8080/services
```

#### Health Monitoring
```bash
# Check all service health
curl http://localhost:8081/services?healthy=true

# Monitor service response times
curl http://localhost:8080/stats | jq '.services[].response_time'
```

## Deployment Procedures

### 1. Initial System Setup

**Quick Start (Recommended):**
```bash
cd /home/zenghua/repos/InfiniLM-SVC
./launch_all.sh
```

This will launch all services in the correct order: Registry → Router → Babysitter instances.

**Manual Step-by-Step Setup:**

1. **Start Registry**
   ```bash
   cd /home/zenghua/repos/InfiniLM-SVC
   ./launch_registry.sh
   ```

2. **Start Router**
   ```bash
   cd /home/zenghua/repos/InfiniLM-SVC
   ./launch_router.sh
   ```

3. **Deploy Service Instances**
   ```bash
   # On each server (local and remote)
   cd /home/zenghua/repos/InfiniLM-SVC

   # Launch specific babysitter instances:
   ./launch_babysitter_9g8b.sh   # Port 8100, model 9g_8b_thinking
   ./launch_babysitter_qwen.sh   # Port 8200, model Qwen3-32B

   # Or create custom instances:
   cp launch_babysitter.sh launch_babysitter_8000.sh
   # Edit launch_babysitter_8000.sh configuration
   ./launch_babysitter_8000.sh
   ```

### 2. Adding New Service Instances

1. **Prepare Configuration**
   - Copy `launch_babysitter.sh` to `launch_babysitter_<PORT>.sh`
   - Edit the configuration section in the new script

2. **Deploy Service**
   ```bash
   # Edit the new script's configuration:
   # - PORT=<NEW_PORT>
   # - SERVICE_NAME="<NEW_SERVICE_NAME>"
   # - HPCC_VISIBLE_DEVICES="<GPU_ID>"
   # - Other instance-specific settings

   ./launch_babysitter_<PORT>.sh
   ```

3. **Verify Registration**
   ```bash
   curl http://localhost:8081/services
   curl http://localhost:8080/stats
   curl http://localhost:<NEW_PORT>/models
   ```

### 3. Removing Service Instances

1. **Graceful Shutdown**
   ```bash
   # Using PID file (recommended)
   kill $(cat logs/babysitter_<PORT>.pid)

   # Or force kill
   kill -9 $(cat logs/babysitter_<PORT>.pid)
   ```

2. **Verify Deregistration**
   ```bash
   curl http://localhost:8081/services
   ```

3. **Cleanup**
   - Remove PID file: `rm logs/babysitter_<PORT>.pid`
   - Archive or remove log files if needed
   - Remove instance-specific launch script if desired

## Security Considerations

### 1. Network Security
- Registry and router should be deployed on trusted networks
- Consider firewall rules for service ports
- Use HTTPS for production deployments

### 2. Service Authentication
- Implement API key authentication for production
- Use service tokens for registry communication
- Secure service-to-service communication

### 3. Resource Management
- Monitor GPU memory usage
- Implement resource limits per service
- Use process monitoring and restart mechanisms

## Backup and Recovery

### 1. Configuration Backup
```bash
# Backup configuration files
tar -czf config_backup_$(date +%Y%m%d).tar.gz \
  deployment_configs/ \
  templates/ \
  *.json \
  *.toml
```

### 2. Service Recovery
1. **Registry Recovery**
   - Restart registry service
   - Services will re-register automatically

2. **Router Recovery**
   - Restart router service
   - Router will re-discover services from registry

3. **Service Instance Recovery**
   - Restart babysitter service
   - Service will re-register with registry

## Maintenance Schedule

### Daily
- Check service health status
- Monitor log files for errors
- Verify service registration

### Weekly
- Review service statistics
- Clean up old log files
- Update service configurations if needed

### Monthly
- Full system validation test
- Performance analysis
- Security review
- Backup configuration files

## Support and Documentation

### Key Files
- `validate_integration.py` - Complete system validation
- `distributed_router.py` - Router implementation
- `service_registry.py` - Registry implementation
- `enhanced_babysitter.py` - Service management wrapper
- `render_service_config.py` - Configuration generation

### Dependencies
- Python 3.8+
- aiohttp
- requests
- openai (for client testing)
- InfiniLM-Rust (for xtask services)

### Environment Setup

#### Option 1: Using Conda (Recommended)
```bash
# Create conda environment
conda create -n infinilm-distributed python=3.11
conda activate infinilm-distributed

# Install dependencies
pip install -r requirements.txt
```
