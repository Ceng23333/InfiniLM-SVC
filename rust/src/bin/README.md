# Rust Babysitter - Universal Backend Support

## Overview

The Rust babysitter supports **universal backends** - any service that exposes an OpenAI-compatible API can be managed by the babysitter. Configuration can be specified via **TOML config files** (recommended) or CLI arguments.

## Configuration Methods

### 1. Config File (Recommended)

Use a TOML config file for cleaner, more maintainable configuration:

```bash
./target/release/infini-babysitter --config-file /path/to/babysitter.toml
```

See `config/babysitter_example.toml` for examples.

### 2. CLI Arguments

For quick testing or simple setups, use CLI arguments:

```bash
./target/release/infini-babysitter \
    --port 8100 \
    --service-type command \
    --command "python3 -m vllm.entrypoints.openai.api_server" \
    --args "--model /models/llama-2-7b --port 8100" \
    --registry-url http://localhost:18000
```

**Note**: CLI arguments override config file values when both are provided.

## Supported Backend Types

### 1. Command-Based (Universal)
The most flexible option - run any command as a backend.

**Config File:**
```toml
name = "vllm-service"
port = 8100
registry_url = "http://localhost:18000"

[backend]
type = "command"
command = "python3"
args = ["-m", "vllm.entrypoints.openai.api_server", "--model", "/models/llama-2-7b", "--port", "8100"]
work_dir = "/path/to/vllm"
env = { CUDA_VISIBLE_DEVICES = "0", VLLM_WORKER_MULTIPROC_METHOD = "spawn" }
```

**CLI:**
```bash
./target/release/infini-babysitter \
    --port 8100 \
    --service-type command \
    --command "python3 -m vllm.entrypoints.openai.api_server" \
    --args "--model /models/llama-2-7b --port 8100" \
    --registry-url http://localhost:18000
```

### 2. vLLM Backend
Pre-configured support for vLLM.

**Config File:**
```toml
name = "vllm-service"
port = 8100
registry_url = "http://localhost:18000"

[backend]
type = "vllm"
model = "/models/llama-2-7b"
args = ["--tensor-parallel-size", "1", "--gpu-memory-utilization", "0.9"]
env = { CUDA_VISIBLE_DEVICES = "0" }
```

**CLI:**
```bash
./target/release/infini-babysitter \
    --port 8100 \
    --service-type vLLM \
    --path /models/llama-2-7b \
    --args "--tensor-parallel-size 1 --gpu-memory-utilization 0.9" \
    --registry-url http://localhost:18000
```

### 3. Mock Backend
For testing and development.

**Config File:**
```toml
name = "mock-service"
port = 8100
registry_url = "http://localhost:18000"

[backend]
type = "mock"
models = ["model-a", "model-b", "model-c"]
```

**CLI:**
```bash
./target/release/infini-babysitter \
    --port 8100 \
    --service-type mock \
    --args "model-a,model-b,model-c" \
    --registry-url http://localhost:18000
```

### 4. InfiniLM-Rust
InfiniLM Rust service.

```bash
./target/release/infini-babysitter \
    --port 8100 \
    --service-type InfiniLM-Rust \
    --path /path/to/config.toml \
    --registry-url http://localhost:18000
```

### 5. InfiniLM Python
InfiniLM Python service.

```bash
./target/release/infini-babysitter \
    --port 8100 \
    --service-type InfiniLM \
    --path /path/to/model \
    --registry-url http://localhost:18000
```

## Backend Requirements

Any backend managed by the babysitter must:

1. **Expose OpenAI-Compatible API**:
   - `GET /models` - List available models
   - `POST /v1/chat/completions` - Chat completions endpoint
   - Optional: `GET /health` - Health check endpoint

2. **Port Configuration**:
   - Backend should listen on the port specified by `--port`
   - Babysitter will use `port+1` for its HTTP server

3. **Startup Behavior**:
   - Backend should start and begin listening within reasonable time
   - Backend should respond to `/models` endpoint when ready

## Examples

### vLLM with Custom Arguments (Config File)
```toml
name = "vllm-service"
port = 8100
registry_url = "http://localhost:18000"

[babysitter]
max_restarts = 10000
restart_delay = 5
heartbeat_interval = 30

[backend]
type = "command"
command = "python3"
args = ["-m", "vllm.entrypoints.openai.api_server", "--model", "/models/llama-2-7b", "--port", "8100", "--tensor-parallel-size", "2"]
work_dir = "/path/to/vllm"
env = { CUDA_VISIBLE_DEVICES = "0,1" }
```

### llama.cpp Server (Config File)
```toml
name = "llama-server"
port = 8100
registry_url = "http://localhost:18000"

[backend]
type = "command"
command = "/path/to/llama-server"
args = ["--model", "/models/llama.gguf", "--port", "8100", "--n-gpu-layers", "35"]
```

### Custom Python Backend (Config File)
```toml
name = "custom-backend"
port = 8100
registry_url = "http://localhost:18000"

[backend]
type = "command"
command = "python3"
args = ["/path/to/my_backend.py", "--port", "8100"]
work_dir = "/path/to/backend"
env = { PYTHONPATH = "/path/to/backend" }
```

## Port Management

- **Service Port**: The port specified by `--port` is where the backend service listens
- **Babysitter Port**: The babysitter HTTP server listens on `port+1`
- **Health Checks**: Router checks babysitter health at `http://host:port+1/health`

## Registry Integration

The babysitter automatically:
1. Registers itself with the registry (as a babysitter service)
2. Detects when the backend is ready
3. Fetches models from the backend
4. Registers the backend with the registry (as an `openai-api` service)
5. Sends periodic heartbeats for both services

## Monitoring

The babysitter monitors the backend process and:
- Automatically restarts on crash (up to `--max-restarts`)
- Detects when backend becomes ready
- Tracks restart count and uptime
- Provides health status via HTTP endpoints
