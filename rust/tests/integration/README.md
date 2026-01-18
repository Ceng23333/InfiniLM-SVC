# Integration Tests

This directory contains integration tests for the Rust router and Rust babysitter implementations.

## Prerequisites

1. **Build the router and babysitter**:
   ```bash
   cd ../../..
   cd rust
   cargo build --release --bin infini-router --bin infini-babysitter
   ```

2. **Setup Integration Test Environment**:
   The tests use a dedicated conda environment. Setup the environment:
   ```bash
   cd rust/tests/integration
   bash setup_env.sh
   ```
   
   This will create a conda environment named `infinilm-integration-test` with all required dependencies (aiohttp, requests).
   
   Alternatively, you can manually create the environment:
   ```bash
   conda create -n infinilm-integration-test python=3.10 -y
   conda run -n infinilm-integration-test pip install aiohttp requests
   ```

## Test Components

### Mock Service (`mock_service.py`)

A Python-based mock service that simulates a backend InfiniLM service with:
- OpenAI API compatibility (`/v1/chat/completions`)
- Model support configuration
- Streaming response support
- Health check endpoint (babysitter)
- Automatic registration with service registry

**Usage**:
```bash
python3 mock_service.py \
    --name "service-name" \
    --port 6001 \
    --models "model-a,model-b" \
    --registry-url "http://127.0.0.1:8901"
```

### Integration Test Scripts

#### 1. Basic Integration Test (`test_integration.sh`)

Tests the router with mock services directly (without babysitter):
1. Starts a service registry
2. Starts multiple mock services with different models
3. Starts the Rust router
4. Tests various scenarios:
   - Model aggregation
   - Model-aware routing
   - Load balancing
   - Unsupported model handling
   - Streaming responses
   - Service discovery
   - Health checks

**Usage**:
```bash
cd rust/tests/integration
bash test_integration.sh
```

#### 2. Babysitter Integration Test (`test_babysitter_integration.sh`)

Tests the full stack with Rust babysitter managing mock services:
1. Starts a service registry
2. Starts multiple Rust babysitters (each managing a mock service)
3. Starts the Rust router
4. Tests the complete flow:
   - Babysitter health endpoints
   - Babysitter /models and /info endpoints
   - Service registration via babysitter
   - Model aggregation
   - Model-aware routing
   - Load balancing
   - Unsupported model handling
   - Streaming responses
   - Service discovery
   - Health checks

**Usage**:
```bash
cd rust/tests/integration
bash test_babysitter_integration.sh
```

This test uses TOML config files for babysitter configuration, demonstrating the config file-based approach.

## Test Scenarios

### Basic Integration Test (`test_integration.sh`)
1. **Model Aggregation**: Tests `/models` endpoint aggregates models from all services
2. **Model-Aware Routing**: Tests routing to services supporting specific models
3. **Load Balancing**: Tests load balancing across services supporting the same model
4. **Unsupported Model**: Tests error handling for unsupported models
5. **Streaming**: Tests streaming response proxying
6. **Service Discovery**: Tests service registration and discovery
7. **Health Checks**: Tests health check system

### Babysitter Integration Test (`test_babysitter_integration.sh`)
1. **Babysitter Health**: Tests babysitter health endpoints
2. **Babysitter /models**: Tests babysitter proxying /models to managed service
3. **Babysitter /info**: Tests babysitter info endpoint
4. **Service Registration**: Tests services registered via babysitter
5. **Model Aggregation**: Tests `/models` endpoint aggregates models from babysitter-managed services
6. **Model-Aware Routing**: Tests routing to services managed by babysitters
7. **Load Balancing**: Tests load balancing across babysitter-managed services
8. **Unsupported Model**: Tests error handling for unsupported models
9. **Streaming**: Tests streaming response proxying through babysitter
10. **Service Discovery**: Tests service registration and discovery via babysitter

## Troubleshooting

### Registry fails to start
- Ensure Python dependencies are installed (`aiohttp`)
- Check if port 8901 is available
- Check logs in `/tmp/registry_integration.log` or `/tmp/registry_babysitter_test.log`

### Mock services fail to start
- Ensure Python dependencies are installed
- Check if ports 6001-6003 are available
- Check service logs in `/tmp/service*.log`

### Babysitters fail to start
- Ensure babysitter binary is built: `cargo build --release --bin infini-babysitter`
- Check babysitter logs in `/tmp/babysitter*.log`
- Verify config files are created correctly in `/tmp/babysitter_test_configs/`
- Ensure mock service script path is correct in config files

### Router fails to start
- Ensure router binary is built: `cargo build --release --bin infini-router`
- Check router logs in `/tmp/router_integration.log` or `/tmp/router_babysitter_test.log`

### Tests fail
- Check all service logs for errors
- Ensure services have time to register and pass health checks (wait times in script)
- Verify registry is accessible at `http://127.0.0.1:8901`
- For babysitter tests, verify babysitters are running and their health endpoints respond
- Check that babysitter-managed services are registered with the registry

## Test Output

The test script provides:
- ✅ Pass indicators for successful tests
- ❌ Fail indicators with error details
- Summary of passed/failed tests
- Exit code 0 for success, 1 for failure
