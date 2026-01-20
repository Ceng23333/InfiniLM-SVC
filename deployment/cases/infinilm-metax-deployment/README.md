# InfiniLM Backend (Python) + InfiniLM-SVC (Rust) — 2-Server Deployment Demo

This demo updates the deployment model to:

- **InfiniLM-SVC**: Rust refactor (`infini-registry`, `infini-router`, `infini-babysitter`) deployed across **2 servers**
- **Backend service**: **InfiniLM** Python inference server launched via:
  - `python python/infinilm/server/inference_server.py ...` (see `InfiniLM/README.md` for the full command)

## Architecture

```
Server 1 (Control + one worker):
  - Registry  (18000)
  - Router    (8000)
  - Babysitter A (8100 -> manages InfiniLM backend on 8100; babysitter health on 8101)

Server 2 (Worker):
  - Babysitter B (8100 -> manages InfiniLM backend on 8100; babysitter health on 8101)
  - Registers to Server 1 registry/router
```

## Prerequisites

- Docker installed on both servers
- Network connectivity between servers
- Ports open:
  - Server 1: `18000`, `8000`, `8100`, `8101`
  - Server 2: `8100`, `8101`
- **InfiniCore** and **InfiniLM** checkouts on each server:
  - These repos are **mounted** into the container at `/mnt/InfiniCore` and `/mnt/InfiniLM`
  - They must be installed inside the container using `install.sh` (see Installation section below)
- Model directory available on each server (mounted into container as `/models/<model>`)

## Build demo image (on both servers)

```bash
cd /path/to/InfiniLM-SVC/demo/infinilm-backend-2server

# Base image (Rust SVC)
cd /path/to/InfiniLM-SVC
docker build -f docker/Dockerfile.rust -t infinilm-svc:latest .

# Demo image (adds python runtime deps: fastapi + uvicorn)
cd demo/infinilm-backend-2server
docker build -f Dockerfile.demo -t infinilm-svc:infinilm-demo .
```

## Start Server 1

```bash
cd /path/to/InfiniLM-SVC/deployment/cases/infinilm-metax-deployment

# Required environment:
export INFINILM_DIR=/path/to/InfiniLM
export INFINICORE_DIR=/path/to/InfiniCore
export MODEL1_DIR=/path/to/9g8b_model_dir
export MODEL2_DIR=/path/to/qwen3_model_dir

./start-server1.sh <SERVER1_IP>
```

After starting the container, **install InfiniCore and InfiniLM inside it**:

```bash
docker exec -it infinilm-svc-infinilm-server1 bash -c '
  cd /app &&
  bash scripts/install.sh \
    --deployment-case infinilm-metax-deployment \
    --install-infinicore true \
    --install-infinilm true \
    --infinicore-src /mnt/InfiniCore \
    --infinilm-src /mnt/InfiniLM \
    --allow-xmake-root auto
'
```

## Start Server 2

```bash
cd /path/to/InfiniLM-SVC/deployment/cases/infinilm-metax-deployment

export INFINILM_DIR=/path/to/InfiniLM
export INFINICORE_DIR=/path/to/InfiniCore
export MODEL_DIR=/path/to/model_dir

./start-server2.sh <SERVER1_IP> <SERVER2_IP>
```

After starting the container, **install InfiniCore and InfiniLM inside it**:

```bash
docker exec -it infinilm-svc-infinilm-server2 bash -c '
  cd /app &&
  bash scripts/install.sh \
    --deployment-case infinilm-metax-deployment \
    --install-infinicore true \
    --install-infinilm true \
    --infinicore-src /mnt/InfiniCore \
    --infinilm-src /mnt/InfiniLM \
    --allow-xmake-root auto
'
```

## Validate

```bash
./validate.sh <SERVER1_IP>
```

## Notes / Customization

- **Backend command** is controlled in `config/babysitter-*.toml` under `[backend]`.
- Default backend uses `--cpu` and binds `--host 0.0.0.0 --port 8100`.
- If you need GPU:
  - switch `--cpu` to your platform flag (e.g. `--nvidia`, `--metax`, ...)
  - set env vars in `[backend].env` (e.g. `CUDA_VISIBLE_DEVICES`, `HPCC_VISIBLE_DEVICES`).
