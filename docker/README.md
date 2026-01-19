# Docker Environment Configuration

This directory contains Docker entrypoint scripts and example environment files for configuring InfiniLM-SVC services.

## Quick Start

### Using Environment File

1. Copy the example environment file:
   ```bash
   cp docker.env.example docker.env
   ```

2. Edit `docker.env` with your configuration

3. Run the container:
   ```bash
   docker run --env-file docker.env -p 18000:18000 -p 8000:8000 <image-name>
   ```

### Using Environment Variables Directly

```bash
docker run \
  -e LAUNCH_COMPONENTS=all \
  -e REGISTRY_PORT=18000 \
  -e ROUTER_PORT=8000 \
  -e BABYSITTER_CONFIGS="config/babysitter1.toml" \
  -p 18000:18000 -p 8000:8000 \
  <image-name>
```

## Configuration Options

### LAUNCH_COMPONENTS

Controls which components to launch:
- `all` (default): Launch registry, router, and babysitters
- `babysitter`: Launch only babysitters (requires remote registry/router)
- Comma-separated: `registry,router` or `registry,babysitter`, etc.

### Ports

- `REGISTRY_PORT`: Port for registry service (default: 18000)
- `ROUTER_PORT`: Port for router service (default: 8000)

### Remote Endpoints

Use these when components are NOT launched locally:

- `REGISTRY_URL`: Remote registry endpoint (required if registry not launched locally)
- `ROUTER_URL`: Remote router endpoint (optional, used by babysitters)
- `ROUTER_REGISTRY_URL`: Registry URL for router to connect to (auto-configured if not set)

### Babysitter Configuration

- `BABYSITTER_CONFIGS`: Space-separated list of babysitter config file paths
  - Example: `config/babysitter1.toml config/babysitter2.toml`
  - Paths can be relative to `config/` directory or absolute paths

### Build Configuration

- `BUILD_ON_STARTUP`: Build Rust binaries on container startup (default: `false`)
  - Set to `"true"` if binaries are not pre-built in the image

## Deployment Scenarios

### Single Server (All Components)

```bash
docker run \
  -e LAUNCH_COMPONENTS=all \
  -e REGISTRY_PORT=18000 \
  -e ROUTER_PORT=8000 \
  -e BABYSITTER_CONFIGS="config/babysitter1.toml" \
  -p 18000:18000 -p 8000:8000 \
  <image-name>
```

### Multi-Server: Control Server (Registry + Router)

```bash
docker run \
  -e LAUNCH_COMPONENTS=registry,router \
  -e REGISTRY_PORT=18000 \
  -e ROUTER_PORT=8000 \
  -p 18000:18000 -p 8000:8000 \
  <image-name>
```

### Multi-Server: Worker Server (Babysitter Only)

```bash
docker run \
  -e LAUNCH_COMPONENTS=babysitter \
  -e REGISTRY_URL=http://control-server:18000 \
  -e ROUTER_URL=http://control-server:8000 \
  -e BABYSITTER_CONFIGS="config/worker1.toml" \
  <image-name>
```

## Files

- `docker_entrypoint_rust.sh`: Main entrypoint script for Rust version
- `docker.env.example`: Comprehensive example with all options
- `docker.env.examples`: Multiple scenario examples

## See Also

- `../script/launch_all_rust.sh`: Launch script used by entrypoint
- `../config/`: Babysitter configuration files directory
