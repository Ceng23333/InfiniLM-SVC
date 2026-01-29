# InfiniLM Backend (Python) + InfiniLM-SVC (Rust) — 2-Server Deployment Demo

This demo updates the deployment model to:

- **InfiniLM-SVC**: Rust refactor (`infini-registry`, `infini-router`, `infini-babysitter`) deployed across **2 servers**
- **Backend service**: **InfiniLM** Python inference server and **InfiniLM-Rust** inference engine

## Architecture

```
Master (Server 1 / Control + worker):
  - Registry  (default: 18000, configurable via REGISTRY_PORT)
  - Router    (default: 8000, configurable via ROUTER_PORT)
  - master-9g_8b_thinking (8100 -> InfiniLM Python backend)
  - master-Qwen3-32B (8200 -> InfiniLM-Rust backend)

Slave (Server 2 / Worker):
  - slave-9g_8b_thinking (8100 -> InfiniLM Python backend)
  - slave-Qwen3-32B (8200 -> InfiniLM-Rust backend)
  - Registers to Master registry/router
```

## Prerequisites

- Docker installed on both servers
- Network connectivity between servers
- Ports open:
  - Server 1: `REGISTRY_PORT` (default: 18000), `ROUTER_PORT` (default: 8000), `8100`, `8101`, `8200`, `8201`
  - Server 2: `8100`, `8101`, `8200`, `8201`
- **InfiniCore** and **InfiniLM** checkouts:
  - Default: Use `/workspace/InfiniCore` and `/workspace/InfiniLM` in container (if pre-installed)
  - Optional: Mount host directories via `INFINICORE_DIR` and `INFINILM_DIR` environment variables
- Model directories/files available on each server

## Configuration

### Port Configuration

Ports are configurable via environment variables:

```bash
export REGISTRY_PORT=18000  # Default: 18000
export ROUTER_PORT=8000      # Default: 8000
```

Or pass as arguments to `start-server2.sh`:
```bash
./start-server2.sh <SERVER1_IP> <SERVER2_IP> [REGISTRY_PORT] [ROUTER_PORT]
```

### Directory Configuration

- **INFINILM_DIR** (optional): Host path to InfiniLM checkout. If not set, uses `/workspace/InfiniLM` in container.
- **INFINICORE_DIR** (optional): Host path to InfiniCore checkout. If not set, uses `/workspace/InfiniCore` in container.
- **CONFIG_DIR** (optional): Host path to config directory. If not set, uses `${SCRIPT_DIR}/config`.

When directories are mounted:
- `INFINILM_DIR` → `/workspace/InfiniLM` (overrides runtime usage directly)
- `INFINICORE_DIR` → `/workspace/InfiniCore` (overrides runtime usage directly)
- If not mounted, uses `/workspace/InfiniLM` and `/workspace/InfiniCore` from container image

## Build deployment image

### Option 1: Using GPU Factory Base Image (Recommended for Metax deployments)

This builds the deployment image on top of a GPU factory provided base image (e.g., Metax GPU factory image with HPCC, PyTorch, Python, etc.):

```bash
cd /path/to/InfiniLM-SVC/deployment/cases/infinilm-metax-deployment

# Build with default GPU factory base image
./build-image.sh

# Build with custom base image
./build-image.sh --base-image cr.metax-tech.com/public-ai-release-wb/x201/vllm:your-tag

# Build and push to registry
./build-image.sh --push --registry your-registry.com --tag your-registry/infinilm-svc:latest

# Build without cache
./build-image.sh --no-cache
```

The build script uses `Dockerfile.gpu-factory` which:
- Uses a multi-stage build (Rust builder + GPU factory runtime)
- Includes InfiniLM-SVC binaries, scripts, and deployment case files
- Preserves GPU factory image capabilities (HPCC, PyTorch, Python, etc.)

### Option 2: Using Standard Base Images

```bash
cd /path/to/InfiniLM-SVC

# Base image (Rust SVC)
docker build -f docker/Dockerfile.rust -t infinilm-svc:latest .

# Demo image (adds python runtime deps: fastapi + uvicorn)
docker build -f docker/Dockerfile.demo -t infinilm-svc:infinilm-demo .
```

## Start Server 1

```bash
cd /path/to/InfiniLM-SVC/deployment/cases/infinilm-metax-deployment

# Required environment:
export MODEL1_DIR=/path/to/9g8b_model_dir
export MODEL2_GGUF=/path/to/Qwen3-32B.gguf

# Optional environment:
export REGISTRY_PORT=18000      # Default: 18000
export ROUTER_PORT=8000         # Default: 8000
export INFINILM_DIR=/path/to/InfiniLM      # Optional: mount InfiniLM
export INFINICORE_DIR=/path/to/InfiniCore  # Optional: mount InfiniCore
export CONFIG_DIR=/path/to/config          # Optional: custom config dir

./start-master.sh <MASTER_IP>
```

After starting the container, **install InfiniCore and InfiniLM inside it** (if not pre-installed or mounted):

```bash
docker exec -it infinilm-svc-master bash -c '
  cd /app &&
  bash scripts/install.sh \
    --deployment-case infinilm-metax-deployment \
    --install-infinicore true \
    --install-infinilm true \
    --infinicore-src /workspace/InfiniCore \
    --infinilm-src /workspace/InfiniLM \
    --allow-xmake-root auto
'
```

Note: If `INFINILM_DIR` and `INFINICORE_DIR` are mounted, they override `/workspace/InfiniLM` and `/workspace/InfiniCore` directly, so installation may not be needed if the mounted directories are already built.

## Start Server 2

```bash
cd /path/to/InfiniLM-SVC/deployment/cases/infinilm-metax-deployment

# Required environment:
export MODEL1_DIR=/path/to/9g8b_model_dir
export MODEL2_GGUF=/path/to/Qwen3-32B.gguf

# Optional environment:
export INFINILM_DIR=/path/to/InfiniLM      # Optional: mount InfiniLM
export INFINICORE_DIR=/path/to/InfiniCore  # Optional: mount InfiniCore
export CONFIG_DIR=/path/to/config          # Optional: custom config dir

./start-slave.sh <MASTER_IP> <SLAVE_IP> [SLAVE_ID]
```

After starting the container, **install InfiniCore and InfiniLM inside it** (if not pre-installed or mounted):

```bash
docker exec -it infinilm-svc-slave bash -c '
  cd /app &&
  bash scripts/install.sh \
    --deployment-case infinilm-metax-deployment \
    --install-infinicore true \
    --install-infinilm true \
    --infinicore-src /workspace/InfiniCore \
    --infinilm-src /workspace/InfiniLM \
    --allow-xmake-root auto
'
```

Note: If `INFINILM_DIR` and `INFINICORE_DIR` are mounted, they override `/workspace/InfiniLM` and `/workspace/InfiniCore` directly, so installation may not be needed if the mounted directories are already built.

## Validate

```bash
# Single server
./validate.sh <SERVER1_IP>

# Two servers
./validate.sh <SERVER1_IP> <SERVER2_IP> [REGISTRY_PORT] [ROUTER_PORT]
```

## Babysitter Configuration Files

Babysitter configs follow the pattern `<role>-<model>.toml`:

- `master-9g_8b_thinking.toml`: Master (Server 1), 9g_8b_thinking model (InfiniLM Python)
- `master-Qwen3-32B.toml`: Master (Server 1), Qwen3-32B model (InfiniLM-Rust)
- `slave-9g_8b_thinking.toml`: Slave (Server 2), 9g_8b_thinking model (InfiniLM Python)
- `slave-Qwen3-32B.toml`: Slave (Server 2), Qwen3-32B model (InfiniLM-Rust)

## Notes / Customization

- **Backend command** is controlled in `config/server*-*.toml` under `[backend]`.
- Default backend uses `--metax` for Metax GPU support.
- If you need different GPU configuration:
  - Update the `args` in the config file (e.g., change `--metax` to `--nvidia`, `--cpu`, etc.)
  - Set env vars in `[backend].env` (e.g. `CUDA_VISIBLE_DEVICES`, `HPCC_VISIBLE_DEVICES`).
- **Ports** are configurable via environment variables or script arguments.
- **Directories** default to `/workspace` in container but can be overridden with mounts.
