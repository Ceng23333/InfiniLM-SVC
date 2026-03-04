# infinilm-metax-deployment-opt

Deployment case: **2 hosts (1 master, 1 slave)** using the latest **infinilm-demo-runtime** image.

## Architecture

- **Master (Server 1)**:
  - 1 Registry (default port 18000)
  - 1 Router (default port 8000)
  - 1 Embedding service (optional, port 20002; started if `EMBEDDING_MODEL_DIR` is set)
  - 1x 9g_8b_thinking model service (port 8100)
  - 1x Qwen3-32B model service with **paged** cache (port 8200)

- **Slave (Server 2)** - optional presets:
  - **Preset 2static** (default): 2x Qwen3-32B static cache, 4 GPU each (ports 8200, 8300)
  - **Preset 1static1vllm**: 1x Qwen3-32B static cache (4 GPU) + 1x vLLM (4 GPU)
  - **Preset 3vllm**: 2x vLLM (4 GPU each) at slave; use with **MASTER_PRESET=3vllm** on master (1 vLLM at master, no paged). Requires both master and slave to use the 3vllm preset.
  - **Preset 1paged2vllm**: 2x vLLM (4 GPU each) at slave; master runs default (1 paged). Same slave config as 3vllm but master keeps paged.

## Prerequisites

- Docker on both hosts
- Network connectivity between master and slave
- Latest image: `infinilm-svc:infinilm-demo-runtime`  
  Build with: `./docker/metax/build-image.sh` (Phase 2 or 3); use runtime tag: `infinilm-svc:infinilm-demo-runtime`
- Model directories on each host:
  - **Master**: MODEL1_DIR (9g_8b_thinking), MODEL2_DIR or QWEN3_32B_DIR (Qwen3-32B)
  - **Slave**: QWEN3_32B_DIR or MODEL2_GGUF (Qwen3-32B)

## Port and GPU summary

### Master (fixed)

| Role   | Service               | Port  | GPUs (example)   |
|--------|------------------------|-------|------------------|
| Master | 9g_8b_thinking         | 8100  | 0                |
| Master | Qwen3-32B paged        | 8200  | 1,2,3,4          |
| Master | Embeddings             | 20002 | -                |

### Slave Preset 1 (2static) - default

| Role  | Service              | Port  | GPUs      |
|-------|----------------------|-------|-----------|
| Slave | slave-2static-1      | 8200  | 0,1,2,3   |
| Slave | slave-2static-2      | 8300  | 4,5,6,7   |

### Slave Preset 2 (1static1vllm)

| Role  | Service                        | Port  | GPUs      |
|-------|--------------------------------|-------|-----------|
| Slave | slave-1static1vllm-static-1    | 8200  | 0,1,2,3   |
| Slave | slave-1static1vllm-vllm-1      | 8300  | 4,5,6,7   |

### Preset 1paged2vllm (1 paged master + 2 vLLM slave)

| Role   | Service               | Port  | GPUs      |
|--------|------------------------|-------|-----------|
| Master | master-9g_8b_thinking  | 8100  | (as before) |
| Master | master-qwen3-32b-paged | 8200  | 4,5,6,7   |
| Slave  | slave-3vllm-vllm-1     | 8200  | 0,1,2,3   |
| Slave  | slave-3vllm-vllm-2     | 8300  | 4,5,6,7   |

### Preset 3vllm (1 vLLM master + 2 vLLM slave)

| Role   | Service               | Port  | GPUs      |
|--------|------------------------|-------|-----------|
| Master | master-9g_8b_thinking  | 8100  | (as before) |
| Master | master-3vllm-vllm-1    | 8200  | 4,5,6,7   |
| Slave  | slave-3vllm-vllm-1     | 8200  | 0,1,2,3   |
| Slave  | slave-3vllm-vllm-2     | 8300  | 4,5,6,7   |

Registry: 18000; Router: 8000.

## Load balancer (size-based routing)

The router routes requests by message body size:

- **Large requests** (bytes > `CACHE_TYPE_ROUTING_THRESHOLD`): forward to static cache and vLLM instances (`cache_type = "static"`)
- **Small requests** (≤ threshold): forward to paged cache instance (`cache_type = "paged"`)

Set `CACHE_TYPE_ROUTING_THRESHOLD` in `.env` on the master (default 51200 = 50KB). For RAG workloads with document-heavy prompts (e.g. jg_rag_benchmark), use a lower threshold such as 15000 so messages with docs route to static/vLLM.

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
# Optionally set SLAVE_PRESET: 2static (default), 1static1vllm, 3vllm, or 1paged2vllm

export QWEN3_32B_DIR=/path/to/Qwen3-32B

# Default: 2 static cache instances (4 GPU each)
./start-slave.sh <MASTER_IP> <SLAVE_IP>

# Or use 1static1vllm preset: 1 static + 1 vLLM
SLAVE_PRESET=1static1vllm ./start-slave.sh <MASTER_IP> <SLAVE_IP>

# Or use 1paged2vllm preset: 1 paged at master (default) + 2 vLLM at slave
SLAVE_PRESET=1paged2vllm ./start-slave.sh <MASTER_IP> <SLAVE_IP>

# Or use 3vllm preset (requires MASTER_PRESET=3vllm on master): 1 vLLM master + 2 vLLM slave
# On master: MASTER_PRESET=3vllm ./start-master.sh <MASTER_IP>
# On slave:
SLAVE_PRESET=3vllm ./start-slave.sh <MASTER_IP> <SLAVE_IP>
```

### Validate

```bash
./validate.sh <MASTER_IP>
# With slave (match SLAVE_PRESET used by start-slave.sh):
./validate.sh <MASTER_IP> <SLAVE_IP>
./validate.sh <MASTER_IP> <SLAVE_IP> 1static1vllm
./validate.sh <MASTER_IP> <SLAVE_IP> 1paged2vllm
# For 3vllm preset, pass SLAVE_PRESET and MASTER_PRESET:
./validate.sh <MASTER_IP> <SLAVE_IP> 3vllm 3vllm
```

### Stop all

```bash
./stop-all.sh
```

(Containers `infinilm-svc-master-opt` and `infinilm-svc-slave-opt` must be reachable from the host where you run `stop-all.sh`; otherwise stop/remove them manually on each host.)

### Benchmark (reproduce cache-type-routing-validation workload)

Run the same benchmark as cache-type-routing-validation (16KB and 65KB context) against the existing deployment:

```bash
export QWEN3_32B_DIR=/path/to/Qwen3-32B
export VLLM_DIR=/path/to/vllm  # optional, defaults to /home/zenghua/repos/vllm

# Default: 192.168.163.151:8000
./run-benchmark.sh

# Custom host/port
ROUTER_HOST=10.0.0.1 ROUTER_PORT=8000 ./run-benchmark.sh
```

Results are saved to `results/metax-opt-*.json`. To compare with cache-type-routing-validation:

```bash
cd ../cache-type-routing-validation
python compare-routing-strategies.py \
  --size-based results/size-based-routing-*.json \
  --2paged ../infinilm-metax-deployment-opt/results/metax-opt-*.json
```

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
