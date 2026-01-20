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
- A usable **InfiniLM** checkout on each server (or at least on the host where you run the container):
  - This demo **mounts** InfiniLM repo into the container and runs the inference server from it.
- Model directory available on each server (mounted into container as `/models/<model>`).

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
cd /path/to/InfiniLM-SVC/demo/infinilm-backend-2server

# Required environment:
export INFINILM_DIR=/path/to/InfiniLM
export MODEL_DIR=/path/to/model_dir   # should be the model directory for --model_path

./start-server1.sh <SERVER1_IP>
```

## Start Server 2

```bash
cd /path/to/InfiniLM-SVC/demo/infinilm-backend-2server

export INFINILM_DIR=/path/to/InfiniLM
export MODEL_DIR=/path/to/model_dir

./start-server2.sh <SERVER1_IP> <SERVER2_IP>
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
