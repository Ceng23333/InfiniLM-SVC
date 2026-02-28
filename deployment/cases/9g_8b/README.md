# 9g_8b Deployment Case

Single-node InfiniLM-SVC deployment with **registry**, **router**, and one **babysitter** running **9g_8b_thinking_llama**. Supports **NVIDIA** (default) and **Metax** platforms with only image and backend config differing.

## Overview

- **Platforms**: `PLATFORM=nvidia` (default) or `PLATFORM=metax`
- **NVIDIA**: Base image `nvcr.io/nvidia/pytorch:25.12-py3`, InfiniLM with `--nvidia` (CUDA)
- **Metax**: Pre-built image `infinilm-svc:metax`, InfiniLM with `--metax` (HPCC)
- **Model**: 9g_8b_thinking_llama (single instance)
- **Ports**: Registry 18000, Router 8000, Babysitter 8100

## Prerequisites

- Docker with [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)
- 9g_8b_thinking_llama model directory

## Quick Start

### NVIDIA (default)

#### 1. Configure environment

```bash
cd deployment/cases/9g_8b
cp .env.example .env
# Edit .env: set MODEL1_DIR=/path/to/9g_8b_thinking_llama
```

#### 2. Build image (with proxy for faster downloads)

```bash
# From project root:
./docker/nvidia/build-image.sh --proxy http://127.0.0.1:7890
# Or: export HTTP_PROXY=http://127.0.0.1:7890 && ./docker/nvidia/build-image.sh
```

#### 3. Start services

```bash
source .env
./start-master.sh
```

### Metax (pre-built image)

```bash
cd deployment/cases/9g_8b
export MODEL1_DIR=/path/to/9g_8b_thinking_llama
PLATFORM=metax ./start-master.sh
```

Uses pre-built image `infinilm-svc:metax`; no build required. If you have an existing Metax image (e.g. `infinilm-svc:runtime-cache-type-routing-validation-issue1004`), tag it: `docker tag <image> infinilm-svc:metax`.

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
| `Dockerfile.nvidia` | Single-stage build from pytorch:25.12-py3 (NVIDIA only) |
| `config/master-9g_8b_thinking-nvidia.toml` | Babysitter config (InfiniLM --nvidia) |
| `config/master-9g_8b_thinking-metax.toml` | Babysitter config (InfiniLM --metax) |
| `start-master.sh` | Start registry + router + babysitter |
| `validate.sh` | Run health checks and e2e chat completion test |
| `docker/nvidia/build-image.sh` | Build script with proxy support (NVIDIA) |
| `.env.example` | Environment template |

## Proxy

For faster pip/conda/git downloads during build, use a proxy (e.g. `http://127.0.0.1:7890`):

```bash
./docker/nvidia/build-image.sh --proxy http://127.0.0.1:7890
```

When the proxy is on localhost, the build uses `--network host` so the container can reach it.
