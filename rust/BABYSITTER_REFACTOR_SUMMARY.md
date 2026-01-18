# Babysitter Rust Refactoring Summary

## Overview
The Enhanced Babysitter has been refactored from Python to Rust, providing better performance, reliability, and integration with the Rust router.

## Implementation Status

### ✅ Completed Features

1. **Process Management** (`process_manager.rs`)
   - Start and monitor InfiniLM services (both Rust and Python)
   - Automatic restart on crash
   - Service port detection
   - Health monitoring

2. **HTTP Server** (`handlers.rs`)
   - Health check endpoint (`/health`)
   - Models proxy endpoint (`/models`)
   - Service info endpoint (`/info`)
   - Runs on port+1 (babysitter_port = service_port + 1)

3. **Registry Integration** (`registry_client.rs`)
   - Register babysitter with registry
   - Register managed service with registry
   - Periodic heartbeats
   - Model fetching from managed service

4. **Configuration** (`config.rs`)
   - CLI argument parsing
   - Support for both InfiniLM-Rust and InfiniLM Python services
   - Configurable restart limits, delays, and intervals

5. **Main Application** (`babysitter.rs`)
   - Graceful shutdown handling
   - Concurrent task management
   - State management

## Architecture

```
┌─────────────────────────────────────┐
│     infini-babysitter (Rust)       │
├─────────────────────────────────────┤
│  ┌──────────────┐  ┌─────────────┐ │
│  │ HTTP Server  │  │   Process   │ │
│  │ (port+1)    │  │   Manager   │ │
│  └──────────────┘  └─────────────┘ │
│  ┌───────────────────────────────┐  │
│  │   Registry Client            │  │
│  │   (Registration & Heartbeat) │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
         │                    │
         │                    │
    ┌────▼────┐         ┌────▼────┐
    │ Registry│         │ InfiniLM│
    │         │         │ Service │
    └─────────┘         └─────────┘
```

## Key Features

### Process Management
- **Universal Backend Support**: Supports any backend that exposes OpenAI-compatible API
- **Service Types Supported**:
  - `command`: Universal command-based backend (specify any command)
  - `InfiniLM-Rust`: Uses `xtask service` command
  - `InfiniLM`: Uses Python `launch_server.py`
  - `vLLM`: vLLM backend (Python module)
  - `mock`: Mock backend for testing
- **Automatic Restart**: Configurable max restarts and delay
- **Port Detection**: Automatically detects when service is ready
- **Working Directory**: Configurable working directory for commands

### HTTP Endpoints
- **`GET /health`**: Returns babysitter and service health status
- **`GET /models`**: Proxies to managed service's `/models` endpoint
- **`GET /info`**: Returns babysitter information and statistics

### Registry Integration
- **Dual Registration**: Registers both babysitter and managed service
- **Model Discovery**: Fetches models from managed service and includes in registration
- **Heartbeats**: Periodic heartbeats to keep services registered

## Usage

### Build
```bash
cd rust
cargo build --release --bin infini-babysitter
```

### Run

**Using Config File (Recommended):**
```bash
./target/release/infini-babysitter --config-file /path/to/babysitter.toml
```

**Using CLI Arguments:**
```bash
# Universal command-based backend (recommended for vLLM, mock, or any backend)
./target/release/infini-babysitter \
    --port 8100 \
    --service-type command \
    --command "python3 -m vllm.entrypoints.openai.api_server" \
    --args "--model /path/to/model --port 8100" \
    --registry-url http://localhost:18000

# For InfiniLM-Rust service
./target/release/infini-babysitter \
    --port 8200 \
    --service-type InfiniLM-Rust \
    --path /path/to/config.toml \
    --registry-url http://localhost:18000

# For vLLM backend
./target/release/infini-babysitter \
    --port 8300 \
    --service-type vLLM \
    --path /path/to/model \
    --args "--tensor-parallel-size 1" \
    --registry-url http://localhost:18000

# For mock backend
./target/release/infini-babysitter \
    --port 8400 \
    --service-type mock \
    --args "model-a,model-b" \
    --registry-url http://localhost:18000
```

## Configuration Options

- `--name`: Service name (auto-generated if not provided)
- `--host`: Host address (default: localhost)
- `--port`: Service port (babysitter uses port+1)
- `--service-type`: "command", "InfiniLM-Rust", "InfiniLM", "vLLM", or "mock" (default: "command")
- `--path`: Config file, model path, or path (depending on service type)
- `--command`: Command to run (for service-type="command", required)
- `--args`: Additional command arguments (space-separated)
- `--work-dir`: Working directory for the command
- `--registry-url`: Registry URL (optional)
- `--router-url`: Router URL (optional, for future use)
- `--max-restarts`: Maximum restart attempts (default: 10000)
- `--restart-delay`: Delay between restarts in seconds (default: 5)
- `--heartbeat-interval`: Heartbeat interval in seconds (default: 30)

## Universal Backend Support

The Rust babysitter supports **any backend** that exposes an OpenAI-compatible API:

1. **Command-Based (Recommended)**: Use `--service-type command` with `--command` to run any backend
   - Example: `--command "python3 -m vllm.entrypoints.openai.api_server" --args "--model /path/to/model"`
   - Works with vLLM, llama.cpp, or any custom backend

2. **Built-in Support**: Pre-configured support for common backends:
   - `vLLM`: vLLM OpenAI API server
   - `mock`: Mock service for testing
   - `InfiniLM-Rust`: InfiniLM Rust service
   - `InfiniLM`: InfiniLM Python service

3. **Requirements**: Backend must:
   - Expose `/models` endpoint (for model discovery)
   - Expose `/v1/chat/completions` endpoint (for requests)
   - Listen on the specified port
   - Respond to health checks

## Differences from Python Version

### Improvements
1. **Universal Backend Support**: Command-based approach supports any backend
2. **Performance**: Rust implementation is more efficient
3. **Type Safety**: Strong typing prevents runtime errors
4. **Concurrency**: Better async/await handling
5. **Memory**: Lower memory footprint

### Simplified Features (for initial version)
1. **Process Monitoring**: Simplified process status checking (can be enhanced)
2. **Log Parsing**: Port detection uses HTTP checks instead of log parsing
3. **Python Service Args**: Simplified Python service argument handling

## Future Enhancements

1. **Enhanced Process Monitoring**: Proper process status checking using `try_wait()`
2. **Log Parsing**: Parse service logs to detect port and status
3. **Full Python Args Support**: Complete support for all InfiniLM Python arguments
4. **Metrics**: Add metrics collection and reporting
5. **Configuration File**: Support TOML/YAML configuration files
6. **Signal Handling**: Enhanced signal handling for graceful shutdown

## Files Created

- `rust/src/bin/babysitter.rs` - Main application
- `rust/src/bin/config.rs` - Configuration management
- `rust/src/bin/handlers.rs` - HTTP handlers
- `rust/src/bin/process_manager.rs` - Process management
- `rust/src/bin/registry_client.rs` - Registry integration
- `rust/src/bin/mod.rs` - Module declarations

## Integration

The Rust babysitter integrates seamlessly with:
- **Rust Router**: Uses same registry format
- **Service Registry**: Compatible with existing Python registry
- **InfiniLM Services**: Supports both Rust and Python services

## Testing

The babysitter can be tested by:
1. Starting a registry
2. Starting the babysitter with a test service
3. Verifying registration and health checks
4. Testing HTTP endpoints

## Status

✅ **Core functionality implemented and compiling**
- Process management
- HTTP server
- Registry integration
- Configuration

⚠️ **Simplified implementations** (can be enhanced):
- Process status checking
- Port detection
- Python service argument handling

The Rust babysitter is ready for testing and can be enhanced with additional features as needed.
