# Reproducing Cache Type Routing Benchmark Results

This document explains how to reproduce the benchmark results documented in `RESULTS_SUMMARY.md` using the Docker image `infinilm-svc:runtime-cache-type-routing-validation`.

## Prerequisites

1. **Docker Image**: The image `infinilm-svc:runtime-cache-type-routing-validation` must be available
   ```bash
   docker images | grep runtime-cache-type-routing-validation
   ```

2. **Model Directory**: Qwen3-32B model must be available on the host
   ```bash
   export QWEN3_32B_DIR=/path/to/Qwen3-32B
   ```

3. **vLLM Repository**: vLLM repository for running benchmarks
   ```bash
   export VLLM_DIR=/path/to/vllm  # Optional, defaults to /home/zenghua/repos/vllm
   ```

4. **Conda Environment**: vLLM benchmark environment (optional, will be created if needed)
   ```bash
   export CONDA_ENV_NAME=vllm-bench  # Optional, defaults to vllm-bench
   ```

## Quick Start

Run the reproduction script:

```bash
cd /home/zenghua/repos/InfiniLM-SVC/deployment/cases/cache-type-routing-validation

# Set required environment variables
export QWEN3_32B_DIR=/path/to/Qwen3-32B
export IMAGE_NAME=infinilm-svc:runtime-cache-type-routing-validation

# Run reproduction script
./reproduce-results.sh [REGISTRY_IP]
```

The script will:
1. Check prerequisites (Docker image, model directory, vLLM)
2. Generate test datasets if needed (16KB and 65KB contexts)
3. Run size-based routing benchmarks for both context sizes
4. Run 2-paged round-robin benchmarks for both context sizes
5. Compare results automatically

## Test Configurations

The script reproduces two test configurations from `RESULTS_SUMMARY.md`:

### Test 2: 16KB Context
- **Dataset**: `large_context_16000.jsonl`
- **Configuration**: 4 conversations × 4 messages = 16 requests
- **Large context**: 1 conversation with 16KB initial context
- **Small context**: 3 conversations with small initial context
- **Routing threshold**: 10KB (10000 bytes)

### Test 3: 65KB Context
- **Dataset**: `large_context_65536.jsonl`
- **Configuration**: 4 conversations × 4 messages = 16 requests
- **Large context**: 1 conversation with 65KB initial context
- **Small context**: 3 conversations with small initial context
- **Routing threshold**: 10KB (10000 bytes)

## Benchmark Parameters

All benchmarks use:
- **Model**: Qwen3-32B
- **Request Rate**: 1.0 req/s
- **Max Concurrency**: 4
- **Total Requests**: 16 (4 conversations × 4 messages)
- **Tensor Parallelism**: tp=4 per instance
- **GPUs**: 8 GPUs total (4 per instance)

## Deployment Configurations

### Size-Based Routing
- **Instance 1**: paged-cache-qwen3-32b (port 8100, GPUs 0-3)
- **Instance 2**: static-cache-qwen3-32b (port 8200, GPUs 4-7)
- **Routing**: Size-based (small → paged, large → static)

### 2-Paged Round-Robin
- **Instance 1**: paged-cache-qwen3-32b (port 8100, GPUs 0-3)
- **Instance 2**: paged-cache-qwen3-32b-2 (port 8300, GPUs 4-7)
- **Routing**: Round-robin (no size-based selection)

## Results

Results are saved in the `results/` directory with filenames like:
- `size-based-routing-1.0qps-concurrency4-Qwen3-32B-YYYYMMDD-HHMMSS.json`
- `2paged-round-robin-1.0qps-concurrency4-Qwen3-32B-YYYYMMDD-HHMMSS.json`

## Comparing Results

After running benchmarks, compare results:

```bash
# Auto-detect latest results
python compare-routing-strategies.py --auto-detect

# Or specify files explicitly
python compare-routing-strategies.py \
  --size-based results/size-based-routing-*.json \
  --2paged results/2paged-round-robin-*.json
```

## Manual Steps (Alternative)

If you prefer to run benchmarks manually:

### 1. Start Size-Based Routing Deployment

```bash
export IMAGE_NAME=infinilm-svc:runtime-cache-type-routing-validation
export QWEN3_32B_DIR=/path/to/Qwen3-32B
export CACHE_TYPE_ROUTING_THRESHOLD=10000  # 10KB
./start-master-qwen3-32b.sh [REGISTRY_IP]
```

### 2. Run Size-Based Routing Benchmarks

```bash
# 16KB context
export MODEL=Qwen3-32B
export DATASET_FILE=large_context_16000.jsonl
export NUM_CONVERSATIONS=4
export MESSAGES_PER_CONV=4
export NUM_LARGE_CONTEXT=1
export REQUEST_RATE=1.0
export MAX_CONCURRENCY=4
./bench-size-based-routing.sh [REGISTRY_IP]

# 65KB context
export DATASET_FILE=large_context_65536.jsonl
./bench-size-based-routing.sh [REGISTRY_IP]
```

### 3. Start 2-Paged Round-Robin Deployment

```bash
export IMAGE_NAME=infinilm-svc:runtime-cache-type-routing-validation
export QWEN3_32B_DIR=/path/to/Qwen3-32B
./start-master-2paged-qwen3-32b.sh [REGISTRY_IP]
```

### 4. Run 2-Paged Round-Robin Benchmarks

```bash
# 16KB context
export MODEL=Qwen3-32B
export DATASET_FILE=large_context_16000.jsonl
export NUM_CONVERSATIONS=4
export MESSAGES_PER_CONV=4
export NUM_LARGE_CONTEXT=1
export REQUEST_RATE=1.0
export MAX_CONCURRENCY=4
./bench-2paged.sh [REGISTRY_IP]

# 65KB context
export DATASET_FILE=large_context_65536.jsonl
./bench-2paged.sh [REGISTRY_IP]
```

## Troubleshooting

### Docker Image Not Found
```bash
# Check available images
docker images | grep infinilm-svc

# Build the image if needed (see docker/metax/build-image.sh)
```

### Model Directory Not Found
```bash
# Verify model directory exists
ls -la ${QWEN3_32B_DIR}

# Check that it contains model files
ls -la ${QWEN3_32B_DIR}/tokenizer*
```

### Services Not Starting
```bash
# Check container logs
docker logs infinilm-svc-master-qwen3-32b
docker logs infinilm-svc-master-2paged-qwen3-32b

# Check if ports are in use
netstat -tuln | grep -E "8000|8100|8200|8300|18000"
```

### Benchmark Failures
```bash
# Check benchmark logs
tail -100 bench-size-based-routing.log
tail -100 bench-2paged.log

# Verify router is accessible
curl http://localhost:8000/health

# Verify instances are accessible
curl http://localhost:8101/health  # paged cache
curl http://localhost:8201/health  # static cache
curl http://localhost:8301/health  # paged cache 2
```

## Expected Results

Based on `RESULTS_SUMMARY.md`, you should see:

### Test 2: 16KB Context
- Size-Based Routing: Mean TTFT ~4.9s, Total Throughput ~67.55 tok/s
- 2-Paged Round-Robin: Mean TTFT ~4.1s, Total Throughput ~54.61 tok/s

### Test 3: 65KB Context
- Size-Based Routing: Mean TTFT ~10.6s, Total Throughput ~150.60 tok/s
- 2-Paged Round-Robin: Mean TTFT ~36.0s, Total Throughput ~64.63 tok/s

Note: Actual results may vary based on hardware, system load, and other factors.
