# Integration Validation Demo

This demo validates InfiniLM-SVC in a multi-server distributed deployment scenario.

## Architecture

```
Server 1 (Control Server):
├── Registry (port 18000)
├── Router (port 8000)
├── Babysitter A (port 8100) → Mock Service A → Model 1
└── Babysitter B (port 8200) → Mock Service B → Model 2

Server 2 (Worker Server):
├── Babysitter C (port 8100) → Mock Service C → Model 1
└── Babysitter D (port 8200) → Mock Service D → Model 2
    (Registers to Server 1's Registry)
```

## Model Distribution

- **Model 1**: Deployed on Babysitters A and C
- **Model 2**: Deployed on Babysitters B and D

## Prerequisites

1. Docker installed on both servers
2. InfiniLM-SVC Docker image built or available
3. Network connectivity between servers
4. Ports available on each host: 18000, 8000, 8100, 8200, 8101, 8201

### Networking Note (important)

This demo **defaults to `--network host`** in `start-server1.sh` / `start-server2.sh`.

- This avoids Docker NAT/iptables and works even when `net.ipv4.ip_forward=0` (common on hardened systems).
- It requires the ports above to be free on the host.
- To use bridge networking + `-p` instead, set `USE_HOST_NETWORK=false` when running the scripts.

## Quick Start

### Step 1: Build Docker Image (on both servers)

**Option A: Build base image + demo image (recommended)**
```bash
cd /path/to/InfiniLM-SVC

# Build base image
docker build -f docker/Dockerfile.rust -t infinilm-svc:latest .

# Build demo image with Python support
cd demo/integration-validation
docker build -f Dockerfile.demo -t infinilm-svc:demo .
```

**Option B: Build base image only (if Python already in base)**
```bash
cd /path/to/InfiniLM-SVC
docker build -f docker/Dockerfile.rust -t infinilm-svc:latest .
```

**Option C: Build via docker commit (from running container)**
```bash
# Start a container from base image
docker run -d --name infinilm-svc-temp infinilm-svc:latest sleep infinity

# Install Python and dependencies in the running container
docker exec infinilm-svc-temp apt-get update
docker exec infinilm-svc-temp apt-get install -y python3 python3-pip
docker exec infinilm-svc-temp pip3 install --no-cache-dir aiohttp

# Commit the changes to create demo image with correct entrypoint
docker commit --change 'ENTRYPOINT ["/bin/bash", "/workspace/docker_entrypoint.sh"]' \
    infinilm-svc-temp infinilm-svc:demo

# Clean up temporary container
docker rm -f infinilm-svc-temp
```

**Note:** The demo requires Python 3 and `aiohttp`. If your base image doesn't include them, use Option A or Option C.

### Step 2: Start Server 1 (Control Server)

```bash
cd demo/integration-validation
./start-server1.sh <SERVER1_IP>
```

Or manually:
```bash
docker run -d --name infinilm-svc-server1 \
  -e LAUNCH_COMPONENTS=all \
  -e REGISTRY_PORT=18000 \
  -e ROUTER_PORT=8000 \
  -e BABYSITTER_CONFIGS="config/babysitter-a.toml config/babysitter-b.toml" \
  -p 18000:18000 \
  -p 8000:8000 \
  -p 8100:8100 -p 8101:8101 \
  -p 8200:8200 -p 8201:8201 \
  -v $(pwd)/config:/app/config:ro \
  -v $(pwd)/mock_service.py:/app/mock_service.py:ro \
  infinilm-svc:latest
```

### Step 3: Start Server 2 (Worker Server)

```bash
./start-server2.sh <SERVER1_IP> <SERVER2_IP>
```

Or manually:
```bash
docker run -d --name infinilm-svc-server2 \
  -e LAUNCH_COMPONENTS=babysitter \
  -e REGISTRY_URL=http://<SERVER1_IP>:18000 \
  -e ROUTER_URL=http://<SERVER1_IP>:8000 \
  -e BABYSITTER_CONFIGS="config/babysitter-c.toml config/babysitter-d.toml" \
  -p 8100:8100 -p 8101:8101 \
  -p 8200:8200 -p 8201:8201 \
  -v $(pwd)/config:/app/config:ro \
  -v $(pwd)/mock_service.py:/app/mock_service.py:ro \
  infinilm-svc:latest
```

### Step 4: Validate

```bash
# From any server or client
./validate.sh <SERVER1_IP>
```

## Validation Tests

The validation script (`validate.sh`) performs 8 comprehensive tests:

1. **Registry Health**: Verifies registry is running and reports healthy services count
2. **Router Health**: Verifies router is running and connected to registry
3. **Service Discovery**: Confirms all 8 services are registered (4 babysitters + 4 managed services)
4. **Model Aggregation**: Verifies both model-1 and model-2 are available through the router
5. **Chat Completions - Model 1**: Tests routing of model-1 requests to correct services (A or C)
6. **Chat Completions - Model 2**: Tests routing of model-2 requests to correct services (B or D)
7. **Load Balancing**: Verifies requests are distributed across multiple services for the same model
8. **Log Verification**: Checks service logs for request handling confirmation

### Expected Success Output

When all tests pass, you should see:

```
==========================================
InfiniLM-SVC Integration Validation
==========================================
Server 1: <SERVER1_IP>
Registry: http://<SERVER1_IP>:18000
Router: http://<SERVER1_IP>:8000

[Test 1] Registry Health
  Checking Registry health... ✓ (HTTP 200)
  {"healthy_services":8,"registered_services":8,...}
✓ PASSED

[Test 2] Router Health
  Checking Router health... ✓ (HTTP 200)
  {"healthy_services":"4/4",...}
✓ PASSED

[Test 3] Service Discovery
  Found 8 services
  Services:
    - babysitter-a
    - babysitter-a-server
    - babysitter-b
    - babysitter-b-server
    - babysitter-c
    - babysitter-c-server
    - babysitter-d
    - babysitter-d-server
✓ PASSED

[Test 4] Model Aggregation
  ✓ Both models found in aggregation
  Models:
    - model-1
    - model-2
✓ PASSED

[Test 5] Chat Completions - Model 1
  ✓ Request routed successfully
  Response from: mock-service-a (or mock-service-c)
✓ PASSED

[Test 6] Chat Completions - Model 2
  ✓ Request routed successfully
  Response from: mock-service-b (or mock-service-d)
✓ PASSED

[Test 7] Load Balancing Test
  ✓ Load balancing working (requests distributed across services)
✓ PASSED

[Test 8] Log Verification
  ✓ Log check complete
✓ PASSED

==========================================
Validation Summary
==========================================
  Passed: 8
  Failed: 0

✅ All tests passed!
```

## Files

- `config/`: Babysitter configuration files
- `mock_service.py`: Mock service implementation
- `start-server1.sh`: Script to start Server 1
- `start-server2.sh`: Script to start Server 2
- `validate.sh`: Validation script
- `stop-all.sh`: Cleanup script

## Key Features Validated

This demo validates:

- ✅ **Multi-server deployment**: Services across two servers working together
- ✅ **Service discovery**: Registry correctly tracks all services
- ✅ **Model aggregation**: Router aggregates models from multiple services
- ✅ **Load balancing**: Requests distributed across multiple instances of the same model
- ✅ **Cross-server routing**: Router successfully routes requests to services on remote servers
- ✅ **Health monitoring**: Services report health status correctly
- ✅ **Service registration**: Remote babysitters register with central registry

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues and solutions.

### Common Issues Resolved

- **Connection refused errors**: Fixed by ensuring mock services bind to `0.0.0.0` and router uses correct URLs
- **Model fetching failures**: Fixed by using `127.0.0.1` for local service access (host config is for registration only)
- **Python dependencies**: Fixed by installing `aiohttp` in both system Python and Conda environments
- **Network connectivity**: Resolved by using `--network host` to avoid Docker NAT issues
