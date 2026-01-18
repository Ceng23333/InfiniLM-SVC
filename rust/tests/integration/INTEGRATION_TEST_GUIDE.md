# Integration Test Setup and Pipeline Guide

This document explains the architecture, components, and pipeline of the integration tests to help with manual investigation.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Integration Test Stack                       │
└─────────────────────────────────────────────────────────────────┘

┌──────────────┐
│   Registry   │  Port 8901 (Python service_registry.py)
│              │  - Service registration endpoint
│              │  - Heartbeat endpoint
│              │  - Service discovery endpoint
└──────┬───────┘
       │
       │ (Service Registration)
       │
       ├─────────────────────────────────────┐
       │                                     │
┌──────▼──────────┐              ┌──────────▼──────────┐
│  Babysitter 1   │              │   Babysitter 2      │
│  Port: 6002     │              │   Port: 6003        │
│                 │              │                     │
│  Manages:       │              │  Manages:          │
│  - Service 1    │              │  - Service 2        │
│    Port: 6001   │              │    Port: 6002       │
│    Models:      │              │    Models:          │
│    - model-a    │              │    - model-b        │
│    - model-     │              │    - model-shared   │
│      shared     │              │                     │
└──────┬──────────┘              └──────────┬──────────┘
       │                                    │
       │ (HTTP Proxy)                      │ (HTTP Proxy)
       │                                    │
┌──────▼──────────┐              ┌──────────▼──────────┐
│  Mock Service 1 │              │   Mock Service 2    │
│  Port: 6001     │              │   Port: 6002        │
│  (Python)       │              │   (Python)          │
│                 │              │                     │
│  Endpoints:     │              │  Endpoints:         │
│  - /v1/models   │              │  - /v1/models      │
│  - /v1/chat/    │              │  - /v1/chat/       │
│    completions  │              │    completions     │
│  - /health      │              │  - /health         │
└─────────────────┘              └─────────────────────┘
       │                                    │
       │                                    │
       └──────────────┬─────────────────────┘
                      │
                      │ (Service Discovery)
                      │
              ┌───────▼────────┐
              │  Rust Router   │  Port 8900
              │                 │
              │  - Load Balancer│
              │  - Health Checks│
              │  - Model Routing│
              │  - Request Proxy│
              └─────────────────┘
                      │
                      │ (Client Requests)
                      │
              ┌───────▼────────┐
              │  Test Script   │
              │  (test_integration.sh)
              └─────────────────┘
```

## Components

### 1. Service Registry (Python)
- **Location**: `python/service_registry.py`
- **Port**: 8901
- **Purpose**: Central service discovery and registration
- **Endpoints**:
  - `POST /services` - Register a service
  - `POST /services/{name}/heartbeat` - Send heartbeat
  - `GET /services` - List all services
  - `GET /health` - Health check

### 2. Rust Babysitter (`infini-babysitter`)
- **Binary**: `rust/target/release/infini-babysitter`
- **Purpose**: Manages lifecycle of mock services
- **Ports**: Service port + 1 (e.g., service on 6001 → babysitter on 6002)
- **Configuration**: TOML files in `/tmp/babysitter_test_configs/`
- **Responsibilities**:
  - Start/stop/restart managed service
  - Health monitoring
  - Registry registration
  - HTTP endpoints:
    - `GET /health` - Babysitter and service health
    - `GET /models` - Proxy to managed service
    - `GET /info` - Babysitter information

### 3. Mock Services (Python)
- **Location**: `rust/tests/integration/mock_service.py`
- **Purpose**: Simulates backend InfiniLM service
- **Ports**: 6001, 6002, 6003
- **Models**:
  - Service 1: `model-a`, `model-shared`
  - Service 2: `model-b`, `model-shared`
  - Service 3: `model-c`
- **Endpoints**:
  - `POST /v1/chat/completions` - Chat completions (OpenAI API)
  - `GET /v1/models` - List supported models
  - `GET /health` - Health check
- **Features**:
  - Automatic registry registration
  - Heartbeat loop (every 10s)
  - Streaming response support
  - Model-specific responses

### 4. Rust Router (`infini-router`)
- **Binary**: `rust/target/release/infini-router`
- **Port**: 8900
- **Purpose**: Request routing, load balancing, service discovery
- **Endpoints**:
  - `GET /health` - Router health
  - `GET /services` - List all discovered services
  - `GET /models` - Aggregate models from all services
  - `GET /stats` - Router statistics
  - `POST /v1/chat/completions` - Proxy to backend (OpenAI API)
  - `*` - Catch-all proxy to backend services

## Test Pipeline

### Phase 1: Setup (Lines 82-135)
1. **Check Prerequisites**
   - Verify binaries exist (`infini-router`, `infini-babysitter`)
   - Verify scripts exist (`service_registry.py`, `mock_service.py`)

2. **Setup Python Environment**
   - Check for conda environment `infinilm-integration-test`
   - Create if missing
   - Install dependencies (`aiohttp`, `requests`)
   - Set `PYTHON_CMD` variable

3. **Start Registry**
   - Launch `service_registry.py` on port 8901
   - Wait 5 seconds
   - Verify health endpoint responds
   - Log: `/tmp/registry_babysitter_test.log`

### Phase 2: Babysitter Configuration (Lines 137-190)
1. **Create TOML Config Files**
   - Directory: `/tmp/babysitter_test_configs/`
   - Files: `babysitter1.toml`, `babysitter2.toml`, `babysitter3.toml`
   - Each config specifies:
     - Service name
     - Port (service port)
     - Registry URL
     - Backend command (Python + mock_service.py)
     - Backend arguments (name, port, models, registry-url)

2. **Example Config** (`babysitter1.toml`):
   ```toml
   name = "babysitter-service-model-a"
   port = 6001
   registry_url = "http://127.0.0.1:8901"
   
   [babysitter]
   max_restarts = 10
   restart_delay = 2
   heartbeat_interval = 10
   
   [backend]
   type = "command"
   command = "conda run -n infinilm-integration-test python"
   args = ["/path/to/mock_service.py", "--name", "service-model-a", 
           "--port", "6001", "--models", "model-a,model-shared", 
           "--registry-url", "http://127.0.0.1:8901"]
   ```

### Phase 3: Start Services (Lines 192-255)
1. **Start Babysitters** (Lines 196-217)
   - Launch 3 babysitter instances with config files
   - Wait 3 seconds
   - Verify health endpoints respond
   - Logs: `/tmp/babysitter1.log`, `/tmp/babysitter2.log`, `/tmp/babysitter3.log`

2. **Babysitter Startup Sequence**:
   ```
   Babysitter starts
   ├─> Starts HTTP server (port = service_port + 1)
   ├─> Spawns managed service process (mock_service.py)
   ├─> Detects service port (waits for HTTP /models to respond)
   ├─> Registers babysitter with registry
   └─> Registers managed service with registry (after models fetched)
   ```

3. **Start Router** (Lines 219-231)
   - Launch router on port 8900
   - Configure:
     - Registry URL: `http://127.0.0.1:8901`
     - Health check interval: 5s
     - Registry sync interval: 2s
   - Wait 3 seconds
   - Log: `/tmp/router_babysitter_test.log`

4. **Service Discovery Wait** (Lines 233-255)
   - Wait 5 seconds for initial discovery
   - Poll `/services` endpoint (up to 20 attempts, 1s intervals)
   - Verify at least 3 healthy services
   - Additional 3 second wait for full readiness

### Phase 4: Test Execution (Lines 257-427)

#### Test 1: Babysitter Health Endpoints
- **Endpoint**: `GET http://127.0.0.1:6002/health`
- **Expected**: JSON with `status` field
- **Purpose**: Verify babysitter HTTP server is running

#### Test 2: Model Aggregation
- **Endpoint**: `GET http://127.0.0.1:8900/models`
- **Expected**: At least 4 models (`model-a`, `model-b`, `model-c`, `model-shared`)
- **Purpose**: Verify router aggregates models from all services

#### Test 3: Model-Aware Routing (model-a)
- **Endpoint**: `POST http://127.0.0.1:8900/v1/chat/completions`
- **Body**: `{"model": "model-a", "messages": [...]}`
- **Expected**: Response with `choices` and `model: "model-a"`
- **Retries**: 3 attempts with 5s delays
- **Purpose**: Verify routing to service supporting `model-a`

#### Test 4: Model-Aware Routing (model-b)
- **Same as Test 3, but for `model-b`**
- **Retries**: 3 attempts with 5s delays

#### Test 5: Load Balancing (model-shared)
- **Endpoint**: `POST http://127.0.0.1:8900/v1/chat/completions` (2 requests)
- **Body**: `{"model": "model-shared", ...}`
- **Expected**: Both requests succeed (may route to different services)
- **Retries**: 3 attempts with 5s delays
- **Purpose**: Verify load balancing across services supporting `model-shared`

#### Test 6: Unsupported Model Handling
- **Endpoint**: `POST http://127.0.0.1:8900/v1/chat/completions`
- **Body**: `{"model": "non-existent-model", ...}`
- **Expected**: HTTP 503 status
- **Purpose**: Verify error handling for unsupported models

#### Test 7: Streaming Response
- **Endpoint**: `POST http://127.0.0.1:8900/v1/chat/completions`
- **Body**: `{"model": "model-a", ..., "stream": true}`
- **Expected**: Response contains `data:` lines (SSE format)
- **Retries**: 3 attempts with 5s delays
- **Purpose**: Verify streaming response proxying

#### Test 8: /services Endpoint
- **Endpoint**: `GET http://127.0.0.1:8900/services`
- **Expected**: At least 3 services in response
- **Purpose**: Verify service discovery and listing

## Manual Investigation Guide

### 1. Check Service Status

```bash
# Check if processes are running
ps aux | grep -E "(babysitter|mock_service|service_registry|infini-router)"

# Check port usage
lsof -i :8900  # Router
lsof -i :8901  # Registry
lsof -i :6001  # Service 1
lsof -i :6002  # Babysitter 1 / Service 2
lsof -i :6003  # Babysitter 2 / Service 3
lsof -i :6004  # Babysitter 3
```

### 2. Check Logs

```bash
# Registry log
tail -f /tmp/registry_babysitter_test.log

# Router log
tail -f /tmp/router_babysitter_test.log

# Babysitter logs
tail -f /tmp/babysitter1.log
tail -f /tmp/babysitter2.log
tail -f /tmp/babysitter3.log
```

### 3. Test Individual Components

#### Test Registry
```bash
# Health check
curl http://127.0.0.1:8901/health

# List services
curl http://127.0.0.1:8901/services
```

#### Test Babysitter
```bash
# Health check
curl http://127.0.0.1:6002/health

# Models (proxied to service)
curl http://127.0.0.1:6002/models

# Info
curl http://127.0.0.1:6002/info
```

#### Test Mock Service Directly
```bash
# Start manually
cd rust/tests/integration
conda run -n infinilm-integration-test python mock_service.py \
    --name "test-service" \
    --port 9999 \
    --models "test-model" \
    --registry-url "http://127.0.0.1:8901"

# Test endpoints
curl http://127.0.0.1:9999/v1/models
curl -X POST http://127.0.0.1:9999/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{"model": "test-model", "messages": [{"role": "user", "content": "test"}]}'
```

#### Test Router
```bash
# Health check
curl http://127.0.0.1:8900/health

# List services
curl http://127.0.0.1:8900/services

# List models
curl http://127.0.0.1:8900/models

# Test routing
curl -X POST http://127.0.0.1:8900/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{"model": "model-a", "messages": [{"role": "user", "content": "test"}]}'
```

### 4. Check Configuration Files

```bash
# View babysitter configs
cat /tmp/babysitter_test_configs/babysitter1.toml
cat /tmp/babysitter_test_configs/babysitter2.toml
cat /tmp/babysitter_test_configs/babysitter3.toml
```

### 5. Debug Service Registration

```bash
# Check what's registered in registry
curl -s http://127.0.0.1:8901/services | python3 -m json.tool

# Check what router sees
curl -s http://127.0.0.1:8900/services | python3 -m json.tool

# Check if services are healthy
curl -s http://127.0.0.1:8900/services | python3 -c "
import sys, json
data = json.load(sys.stdin)
for s in data.get('services', []):
    print(f\"{s['name']}: healthy={s.get('healthy')}, models={s.get('metadata', {}).get('models', [])}\")
"
```

### 6. Monitor Service Startup

```bash
# Watch babysitter logs in real-time
tail -f /tmp/babysitter1.log | grep -E "(Service detected|registered|Fetched|ERROR|WARN)"

# Watch router logs
tail -f /tmp/router_babysitter_test.log | grep -E "(sync|health|service|ERROR|WARN)"

# Monitor port detection
tail -f /tmp/babysitter1.log | grep -E "(port|detected|ready)"
```

### 7. Test Service Readiness

```bash
# Check if service port is listening
nc -zv 127.0.0.1 6001

# Check if HTTP endpoint responds
curl -v http://127.0.0.1:6001/v1/models

# Check babysitter health
curl -v http://127.0.0.1:6002/health
```

### 8. Common Issues and Debugging

#### Issue: Service not detected
```bash
# Check if mock service is actually running
ps aux | grep mock_service

# Check if port is listening
lsof -i :6001

# Check babysitter log for port detection
grep -E "(detected|port|ready)" /tmp/babysitter1.log
```

#### Issue: Service not registered
```bash
# Check registry for service
curl http://127.0.0.1:8901/services | grep "service-model-a"

# Check babysitter log for registration
grep -E "(registered|Fetched|models)" /tmp/babysitter1.log

# Check if models were fetched successfully
grep "Fetched.*models" /tmp/babysitter1.log
```

#### Issue: Router can't find services
```bash
# Check router's service list
curl http://127.0.0.1:8900/services

# Check router log for sync
grep -E "(sync|discovered|services)" /tmp/router_babysitter_test.log

# Verify registry is accessible from router
curl http://127.0.0.1:8901/services
```

#### Issue: Health checks failing
```bash
# Test babysitter health endpoint directly
curl http://127.0.0.1:6002/health

# Test service health endpoint directly
curl http://127.0.0.1:6001/v1/models

# Check router health check log
grep -E "(health|check|unhealthy)" /tmp/router_babysitter_test.log
```

## Timing and Synchronization

### Critical Timing Points

1. **Registry startup**: 5 seconds wait
2. **Babysitter startup**: 3 seconds wait
3. **Router startup**: 3 seconds wait
4. **Service discovery**: 5 seconds + polling (up to 20s)
5. **Service readiness**: Additional 3 seconds
6. **Port detection**: Up to 10 seconds (optimized to ~3.6s)
7. **Model fetching**: Up to 6 seconds (20 attempts × 300ms)

### Service Registration Flow

```
Time 0s:  Babysitter starts, spawns mock service
Time 0.1s: Mock service starts HTTP server
Time 3.6s: Port detected (HTTP /models responds)
Time 3.6s: Babysitter registers with registry
Time 4-6s: Models fetched from service
Time 6s:   Managed service registered with registry
Time 8s:   Router discovers service (next sync cycle)
Time 10s:  Health check passes
Time 13s:  Service ready for requests
```

## Environment Variables and Configuration

### Python Environment
- **Conda Environment**: `infinilm-integration-test`
- **Dependencies**: `aiohttp`, `requests`
- **Command**: `conda run -n infinilm-integration-test python`

### Port Allocation
- **Registry**: 8901
- **Router**: 8900
- **Service 1**: 6001 (Babysitter: 6002)
- **Service 2**: 6003 (Babysitter: 6004)
- **Service 3**: 6005 (Babysitter: 6006)

### Log Files
- Registry: `/tmp/registry_babysitter_test.log`
- Router: `/tmp/router_babysitter_test.log`
- Babysitter 1: `/tmp/babysitter1.log`
- Babysitter 2: `/tmp/babysitter2.log`
- Babysitter 3: `/tmp/babysitter3.log`

## Running Tests Manually

### Step-by-Step Manual Execution

1. **Start Registry**:
   ```bash
   cd /path/to/InfiniLM-SVC
   conda run -n infinilm-integration-test python python/service_registry.py --port 8901
   ```

2. **Start Babysitter 1**:
   ```bash
   cd /path/to/InfiniLM-SVC/rust
   ./target/release/infini-babysitter --config-file /tmp/babysitter_test_configs/babysitter1.toml
   ```

3. **Start Router**:
   ```bash
   cd /path/to/InfiniLM-SVC/rust
   ./target/release/infini-router \
       --router-port 8900 \
       --registry-url http://127.0.0.1:8901 \
       --health-interval 5 \
       --registry-sync-interval 2
   ```

4. **Wait for Services**:
   ```bash
   # Wait for services to register
   sleep 15
   
   # Verify services are registered
   curl http://127.0.0.1:8900/services
   ```

5. **Run Individual Tests**:
   ```bash
   # Test model aggregation
   curl http://127.0.0.1:8900/models
   
   # Test routing
   curl -X POST http://127.0.0.1:8900/v1/chat/completions \
       -H "Content-Type: application/json" \
       -d '{"model": "model-a", "messages": [{"role": "user", "content": "test"}]}'
   ```

## Troubleshooting Checklist

- [ ] All binaries built (`infini-router`, `infini-babysitter`)
- [ ] Conda environment exists and has dependencies
- [ ] Ports 8900, 8901, 6001-6004 are available
- [ ] Registry starts and responds to `/health`
- [ ] Babysitters start and respond to `/health`
- [ ] Mock services start and respond to `/v1/models`
- [ ] Services register with registry (check `/services` endpoint)
- [ ] Router discovers services (check router `/services` endpoint)
- [ ] Health checks pass (services marked as healthy)
- [ ] Models are aggregated correctly (check router `/models` endpoint)
