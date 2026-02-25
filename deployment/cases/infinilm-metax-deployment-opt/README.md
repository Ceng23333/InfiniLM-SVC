# infinilm-metax-deployment-opt

Deployment case: **2 hosts (1 master, 1 slave)** using the latest **infinilm-demo-runtime** image.

## Architecture

- **Master (Server 1)**:
  - 1 Registry (default port 18000)
  - 1 Router (default port 8000)
  - 1 Embedding service (optional, port 20002; started if `EMBEDDING_MODEL_DIR` is set)
  - 1x 9g_8b_thinking model service (port 8100)
  - 1x Qwen3-32B model service with **paged** cache (port 8200)

- **Slave (Server 2)**:
  - 2x Qwen3-32B model services with **static** cache (ports 8200 and 8300)

## Prerequisites

- Docker on both hosts
- Network connectivity between master and slave
- Latest image: `infinilm-svc:infinilm-demo-runtime`  
  Build with: `./docker/metax/build-image.sh` (Phase 2 or 3); use runtime tag: `infinilm-svc:infinilm-demo-runtime`
- Model directories on each host:
  - **Master**: MODEL1_DIR (9g_8b_thinking), MODEL2_DIR or QWEN3_32B_DIR (Qwen3-32B)
  - **Slave**: QWEN3_32B_DIR or MODEL2_GGUF (Qwen3-32B)

## Port and GPU summary

| Role   | Service               | Port  | GPUs (example)   |
|--------|------------------------|-------|------------------|
| Master | 9g_8b_thinking         | 8100  | 0                |
| Master | Qwen3-32B paged        | 8200  | 1,2,3,4          |
| Master | Embeddings             | 20002 | -                |
| Slave  | Qwen3-32B static #1    | 8200  | 0,1,2,3          |
| Slave  | Qwen3-32B static #2    | 8300  | 4,5,6,7          |

Registry: 18000; Router: 8000.

## Quick start

### On Master host

```bash
cd deployment/cases/infinilm-metax-deployment-opt

# Copy and edit env
cp .env.example .env
# Set MODEL1_DIR and MODEL2_DIR (or QWEN3_32B_DIR) in .env

export MODEL1_DIR=/path/to/9g_8b_thinking_llama
export MODEL2_DIR=/path/to/Qwen3-32B
# Or: export QWEN3_32B_DIR=/path/to/Qwen3-32B

./start-master.sh <MASTER_IP>
```

### On Slave host

```bash
cd deployment/cases/infinilm-metax-deployment-opt

# Copy and edit env
cp .env.slave.example .env.slave
# Set QWEN3_32B_DIR (or MODEL2_GGUF) in .env.slave

export QWEN3_32B_DIR=/path/to/Qwen3-32B

./start-slave.sh <MASTER_IP> <SLAVE_IP>
```

### Validate

```bash
./validate.sh <MASTER_IP>
# With slave: ./validate.sh <MASTER_IP> <SLAVE_IP>
```

### Stop all

```bash
./stop-all.sh
```

(Containers `infinilm-svc-master-opt` and `infinilm-svc-slave-opt` must be reachable from the host where you run `stop-all.sh`; otherwise stop/remove them manually on each host.)

## Embedding server (optional)

To enable the embedding service on the master:

1. Set `EMBEDDING_MODEL_DIR` to the path containing MiniCPM-Embedding-Light (or the embedding model directory).
2. Ensure `embeddings_server.py` is present in this case directory (it is copied from `infinilm-metax-deployment` if you need it; the runtime image may already include it when built with a case that has embeddings).
3. Restart the master so that `master-embeddings.toml` is included in `BABYSITTER_CONFIGS` and the embedding model is mounted.

If the runtime image was built without embedding support, copy `embeddings_server.py` from `deployment/cases/infinilm-metax-deployment/` into this directory and rebuild or use an image that includes it.

## Image

Default image: **infinilm-svc:infinilm-demo-runtime**.  
Override with: `export IMAGE_NAME=your-registry/infinilm-svc:your-runtime-tag`

## References

- **infinilm-metax-deployment**: Master/slave layout, start scripts, embedding and config patterns.
- **cache-type-routing-validation**: Paged vs static cache TOML configs and inference_server.py `--cache_type` usage.
