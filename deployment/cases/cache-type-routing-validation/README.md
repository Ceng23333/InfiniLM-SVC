# Cache Type Routing Validation Deployment Case

## Overview

This deployment case validates size-based routing functionality in InfiniLM-SVC based on cache type and message body size. The case deploys 2 instances of the same model (9g_8b_thinking) with different cache types (paged vs static) on one host and validates routing based on message body size.

## Architecture

```
Single Host:
  - Registry (port 18000)
  - Router (port 8000) with size-based routing
  - Instance 1: paged-cache-9g_8b_thinking (port 8100, cache_type=paged)
  - Instance 2: static-cache-9g_8b_thinking (port 8200, cache_type=static)
```

## Routing Strategy

The router implements size-based routing:
- **Small requests** (body size ≤ threshold, default 50KB): Route to **paged cache** instance
- **Large requests** (body size > threshold): Route to **static cache** instance

This strategy optimizes cache utilization:
- Paged cache is efficient for smaller, frequently changing contexts
- Static cache is better for larger, more stable contexts

## Prerequisites

1. **Docker**: Docker must be installed and running
2. **Model**: The 9g_8b_thinking model must be available on the host
3. **InfiniLM-SVC Image**: The InfiniLM-SVC Docker image must be built
4. **vLLM Repository**: vLLM repository must be available for benchmarking
5. **Conda**: Conda must be installed for the vLLM benchmark environment

## Setup Instructions

### 1. Set Environment Variables

```bash
export MODEL1_DIR=/path/to/9g_8b_thinking_llama

# The benchmark scripts will use MODEL1_DIR for the tokenizer path
# If MODEL1_DIR is not set, the scripts will show a warning and try to download from HuggingFace (may fail if offline)
export VLLM_DIR=/path/to/vllm  # Optional, defaults to /home/zenghua/repos/vllm
export CONDA_ENV_NAME=vllm-bench  # Optional, defaults to vllm-bench

# Optional: Configure routing threshold (default: 51200 bytes = 50KB)
export CACHE_TYPE_ROUTING_THRESHOLD=51200
```

### 2. Setup vLLM Benchmark Environment

```bash
cd /home/zenghua/repos/InfiniLM-SVC/deployment/cases/cache-type-routing-validation
./setup-vllm-env.sh
```

This script will:
- Create a conda environment named `vllm-bench` (or the value of `CONDA_ENV_NAME`)
- Install minimal Python dependencies needed for benchmarks
- **Note**: vLLM is NOT built/installed. The benchmark scripts run directly from the vLLM source directory using PYTHONPATH

### 3. Start the Deployment

```bash
./start-master.sh [REGISTRY_IP]
```

This will start:
- Registry on port 18000
- Router on port 8000 (with size-based routing enabled)
- paged-cache-9g_8b_thinking instance on port 8100
- static-cache-9g_8b_thinking instance on port 8200

### 4. Validate the Deployment

```bash
./validate.sh [REGISTRY_IP]
```

This script validates:
- Core health endpoints
- Service discovery
- Model aggregation
- Chat completions
- Instance health checks
- Size-based routing (small vs large requests)

## Running Benchmarks

### Generate Large Context Test Cases

Generate test cases with configurable probability of large initial context:

```bash
python gen-large-context.py \
  --num-conversations 4 \
  --messages-per-conv 8 \
  --context-len 1024 \
  --new-msg-len 128 \
  --large-context-prob 0.5 \
  --large-context-len 2048 \
  --output large_context.jsonl
```

**Parameters:**
- `--num-conversations`: Number of different conversations (default: 4)
- `--messages-per-conv`: Number of messages per conversation (default: 8)
- `--context-len`: Length of context added by each message (default: 1024)
- `--new-msg-len`: Length of new message content (default: 128)
- `--large-context-prob`: Probability of large initial context (default: 0.5)
- `--large-context-len`: Length of large initial context in characters (default: 2048)
- `--output`: Output JSONL file path (default: large_context.jsonl)

### Run Size-Based Routing Benchmark

```bash
conda activate vllm-bench
export MODEL1_DIR=/path/to/9g_8b_thinking_llama
./bench-size-based-routing.sh [REGISTRY_IP]
```

**Expected Behavior**:
- Small requests (≤ threshold) should route to paged cache instance
- Large requests (> threshold) should route to static cache instance
- Routing accuracy can be verified via logs and comparison script

### Compare Cache Types

Compare performance between paged and static cache instances:

```bash
conda activate vllm-bench
python compare-cache-types.py \
  results/paged-cache-*.json \
  results/static-cache-*.json
```

## Configuration

### Routing Threshold

The routing threshold can be configured via environment variable:

```bash
export CACHE_TYPE_ROUTING_THRESHOLD=51200  # 50KB in bytes (default)
```

Or via router configuration (if supported).

### Instance Configuration

Each instance is configured with:
- **cache_type** metadata: `"paged"` or `"static"`
- **--cache_type** argument: Passed to the inference server

See `config/paged-cache-9g_8b_thinking.toml` and `config/static-cache-9g_8b_thinking.toml` for details.

## Validation Criteria

### Size-Based Routing
- ✅ Small requests (≤ threshold) should route to paged cache instance
- ✅ Large requests (> threshold) should route to static cache instance
- ✅ Routing should be consistent for requests of similar size
- ✅ Both instances should receive traffic based on request size distribution

### Performance
- ✅ Paged cache should show good performance for small requests
- ✅ Static cache should show good performance for large requests
- ✅ Overall system throughput should be maintained

## Files Structure

```
cache-type-routing-validation/
├── README.md                          # This file
├── install.defaults.sh                # Deployment defaults
├── start-master.sh                    # Start script for both instances
├── validate.sh                        # Validation script
├── setup-vllm-env.sh                  # vLLM environment setup
├── bench-size-based-routing.sh        # Size-based routing benchmark
├── compare-cache-types.py             # Cache type comparison script
├── gen-large-context.py               # Test case generator
├── config/
│   ├── paged-cache-9g_8b_thinking.toml    # Paged cache instance config (port 8100)
│   └── static-cache-9g_8b_thinking.toml   # Static cache instance config (port 8200)
└── results/                           # Benchmark results directory
```

## Related Documentation

- [InfiniLM-SVC Main Documentation](../../../README.md)
- [Babysitter Configuration](../../../rust/src/bin/README.md)
- [Cache Routing Validation](../cache-routing-validation/README.md) - Similar deployment with cache key routing

## Notes

- Both instances use the same model (9g_8b_thinking) but with different cache types
- The router handles routing logic based on message body size
- Size-based routing enables optimal cache type selection for different request sizes
- Benchmark results can be compared to validate routing behavior and performance
