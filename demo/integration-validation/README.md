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
4. Ports available: 18000, 8000, 8100, 8200, 8101, 8201, 8102, 8202

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

**Note:** The demo requires Python 3 and `aiohttp`. If your base image doesn't include them, use Option A.

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

The validation script checks:

1. **Registry Health**: All services registered
2. **Router Health**: Router connected to registry
3. **Model Aggregation**: Both models available from router
4. **Service Discovery**: All 4 babysitters discovered
5. **Chat Completions**: Requests routed correctly to appropriate services
6. **Log Verification**: Service logs confirm request handling

## Files

- `config/`: Babysitter configuration files
- `mock_service.py`: Mock service implementation
- `start-server1.sh`: Script to start Server 1
- `start-server2.sh`: Script to start Server 2
- `validate.sh`: Validation script
- `stop-all.sh`: Cleanup script

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues.
