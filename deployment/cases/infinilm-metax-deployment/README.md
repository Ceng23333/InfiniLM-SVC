# InfiniLM Backend (Python) + InfiniLM-SVC (Rust) — 2-Server Deployment Demo

This demo updates the deployment model to:

- **InfiniLM-SVC**: Rust refactor (`infini-registry`, `infini-router`, `infini-babysitter`) deployed across **2 servers**
- **Backend service**: **InfiniLM** Python inference server and **InfiniLM-Rust** inference engine

## Architecture

```
Server 1 (Control + worker):
  - Registry  (default: 18000, configurable via REGISTRY_PORT)
  - Router    (default: 8000, configurable via ROUTER_PORT)
  - server1-9g_8b_thinking_llama (8100 -> InfiniLM Python backend)
  - server1-Qwen3-32B (8200 -> InfiniLM-Rust backend)

Server 2 (Worker):
  - server2-9g_8b_thinking_llama (8100 -> InfiniLM Python backend)
  - server2-Qwen3-32B (8200 -> InfiniLM-Rust backend)
  - Registers to Server 1 registry/router
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

## Build demo image (on both servers)

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

./start-server1.sh <SERVER1_IP>
```

After starting the container, **install InfiniCore and InfiniLM inside it** (if not pre-installed or mounted):

```bash
docker exec -it infinilm-svc-infinilm-server1 bash -c '
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

./start-server2.sh <SERVER1_IP> <SERVER2_IP> [REGISTRY_PORT] [ROUTER_PORT]
```

After starting the container, **install InfiniCore and InfiniLM inside it** (if not pre-installed or mounted):

```bash
docker exec -it infinilm-svc-infinilm-server2 bash -c '
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

Babysitter configs follow the pattern `<server>-<model>.toml`:

- `server1-9g_8b_thinking_llama.toml`: Server 1, 9g_8b_thinking_llama model (InfiniLM Python)
- `server1-Qwen3-32B.toml`: Server 1, Qwen3-32B model (InfiniLM-Rust)
- `server2-9g_8b_thinking_llama.toml`: Server 2, 9g_8b_thinking_llama model (InfiniLM Python)
- `server2-Qwen3-32B.toml`: Server 2, Qwen3-32B model (InfiniLM-Rust)

## Notes / Customization

- **Backend command** is controlled in `config/server*-*.toml` under `[backend]`.
- Default backend uses `--metax` for Metax GPU support.
- If you need different GPU configuration:
  - Update the `args` in the config file (e.g., change `--metax` to `--nvidia`, `--cpu`, etc.)
  - Set env vars in `[backend].env` (e.g. `CUDA_VISIBLE_DEVICES`, `HPCC_VISIBLE_DEVICES`).
- **Ports** are configurable via environment variables or script arguments.
- **Directories** default to `/workspace` in container but can be overridden with mounts.
