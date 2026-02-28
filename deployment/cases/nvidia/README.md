# NVIDIA GPU Deployment Case

Single-node InfiniLM-SVC deployment on NVIDIA GPU with **registry**, **router**, and one **babysitter** running **9g_8b_thinking_llama** via InfiniLM with `--nvidia` (CUDA).

## Overview

- **Base image**: `nvcr.io/nvidia/pytorch:25.12-py3`
- **Backend**: InfiniLM inference_server with `--nvidia` (standard CUDA)
- **Model**: 9g_8b_thinking_llama (single instance)
- **Ports**: Registry 18000, Router 8000, Babysitter 8100

## Prerequisites

- Docker with [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)
- 9g_8b_thinking_llama model directory

## Quick Start

### 1. Configure environment

```bash
cd deployment/cases/nvidia
cp .env.example .env
# Edit .env: set MODEL1_DIR=/path/to/9g_8b_thinking_llama
```

### 2. Build image (with proxy for faster downloads)

```bash
# From project root:
./docker/nvidia/build-image.sh --proxy http://127.0.0.1:7890
# Or: export HTTP_PROXY=http://127.0.0.1:7890 && ./docker/nvidia/build-image.sh
```

### 3. Start services

```bash
source .env
./start-master.sh
```

### 4. Verify

```bash
./validate.sh
# Or manually:
# curl http://localhost:18000/health   # Registry
# curl http://localhost:8000/health    # Router
# curl http://localhost:8101/health    # Babysitter (9g_8b_thinking)
```

## Files

| File | Description |
|------|-------------|
| `install.defaults.sh` | Install-time defaults (InfiniCore --nv-gpu, branches) |
| `Dockerfile.nvidia` | Single-stage build from pytorch:25.12-py3 |
| `config/master-9g_8b_thinking.toml` | Babysitter config (InfiniLM --nvidia) |
| `start-master.sh` | Start registry + router + babysitter |
| `validate.sh` | Run health checks and e2e chat completion test |
| `docker/nvidia/build-image.sh` | Build script with proxy support |
| `.env.example` | Environment template |

## Proxy

For faster pip/conda/git downloads during build, use a proxy (e.g. `http://127.0.0.1:7890`):

```bash
./docker/nvidia/build-image.sh --proxy http://127.0.0.1:7890
```

When the proxy is on localhost, the build uses `--network host` so the container can reach it.
