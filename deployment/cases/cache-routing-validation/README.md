# Cache Routing Validation Deployment Case

## Overview

This deployment case validates `prompt_cache_key` routing functionality in InfiniLM-SVC. The case deploys 2 instances of the same model (9g_8b_thinking) on one host and supports three deployment configurations that differ at the client level (using different vLLM bench configurations).

## Architecture

```
Single Host:
  - Registry (port 18000)
  - Router (port 8000)
  - Instance 1: master-9g_8b_thinking (port 8100)
  - Instance 2: slave-9g_8b_thinking (port 8200)
```

## Three Validation Scenarios

1. **Single instance**: Only instance 1 running
2. **Round-robin**: Both instances, no prompt_cache_key (default routing)
3. **Cache routing**: Both instances, with prompt_cache_key (session-aware routing)

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
```

### 2. Setup vLLM Benchmark Environment

```bash
cd /home/zenghua/repos/InfiniLM-SVC/deployment/cases/cache-routing-validation
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
- Router on port 8000
- master-9g_8b_thinking instance on port 8100
- slave-9g_8b_thinking instance on port 8200

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
- Load balancing (round-robin)
- Cache routing (with prompt_cache_key)

## Running Benchmarks

**Note**: All benchmark scripts now use **shared-prefix prompts by default** for better cache routing validation. The dataset is automatically generated if it doesn't exist.

### Generate Shared-Prefix Prompts (Automatic)

The benchmark scripts will automatically generate shared-prefix prompts if the dataset file doesn't exist. You can also generate it manually:

```bash
cd /home/zenghua/repos/InfiniLM-SVC/deployment/cases/cache-routing-validation
python gen-shared-prefix.py \
  --num-prompts 64 \
  --prefix-len 8192 \
  --suffix-len 32 \
  --output shared_prefix.jsonl
```

**Parameters:**
- `--num-prompts`: Number of prompts to generate (default: 32)
- `--prefix-len`: Length of shared prefix in characters (default: 8192)
- `--suffix-len`: Length of unique suffix in characters (default: 32)
- `--output`: Output JSONL file path (default: shared_prefix.jsonl)

**Multi-Prefix** (recommended for cache routing validation):
```bash
python gen-multi-prefix.py \
  --num-prompts 64 \
  --num-prefixes 4 \
  --prefix-len 8192 \
  --suffix-len 32 \
  --output multi_prefix.jsonl
```

**Parameters:**
- `--num-prompts`: Number of prompts to generate (default: 64)
- `--num-prefixes`: Number of different shared prefixes (default: 4)
- `--prefix-len`: Length of each shared prefix in characters (default: 8192)
- `--suffix-len`: Length of unique suffix in characters (default: 32)
- `--output`: Output JSONL file path (default: multi_prefix.jsonl)

**Why use multiple prefixes?**
- With a single prefix, all requests go to the same instance (no routing benefit)
- With multiple prefixes, requests are distributed across instances
- Requests with the same prefix route to the same instance and benefit from cache hits
- Better demonstrates cache routing impact and benefits

### Single Instance Benchmark

Tests performance with only the master instance running:

```bash
# Activate conda environment first
conda activate vllm-bench

# Run benchmark
./bench-single.sh [REGISTRY_IP]
```

**Configuration**: Only master-9g_8b_thinking (port 8100) is running

### Round-Robin Benchmark

Tests load balancing across both instances without cache routing:

```bash
conda activate vllm-bench
./bench-roundrobin.sh [REGISTRY_IP]
```

**Configuration**: Both instances running, no prompt_cache_key
**Dataset**: Multi-prefix prompts (4 prefixes by default, auto-generated if needed)
**Expected Behavior**: Requests should be distributed across both instances in round-robin fashion

### Cache Routing Benchmark

Tests session-aware routing using prompt_cache_key:

```bash
conda activate vllm-bench
export MODEL1_DIR=/path/to/9g_8b_thinking_llama
./bench-cache-routing.sh [REGISTRY_IP]
```

**Configuration**: Both instances running, with prompt_cache_key
**Dataset**: Multi-prefix prompts (4 prefixes by default, auto-generated if needed)

**Expected Behavior**:
- Requests with the same `prompt_cache_key` should route to the same instance
- The default pattern `bench_key_{request_id % 4}` creates 4 different cache keys (matches number of prefixes)
- Requests are distributed across instances based on cache key hash
- **Cache hits** (same prefix/key) show lower TTFT compared to **cache misses** (different prefix/key)
- Better demonstrates cache routing impact compared to single-prefix approach

**Why multiple prefixes?**
- With a single shared prefix, all requests go to the same instance (no routing benefit)
- With multiple prefixes, requests are distributed across instances
- Requests with the same prefix route to the same instance and benefit from cache hits
- This better demonstrates the cache routing impact

**Compare Results:**
```bash
# After running both benchmarks, compare the results
python compare-results.py \
  results/round-robin-*.json \
  results/cache-routing-*.json
```

**Custom Cache Key Pattern**:

```bash
export CACHE_KEY_PATTERN="my_key_{request_id % 2}"
./bench-cache-routing.sh [REGISTRY_IP]
```

## Benchmark Configuration

You can customize benchmark parameters via environment variables:

```bash
export REQUEST_RATE=2.0      # Requests per second (default: 1.0)
export NUM_REQUESTS=100      # Total number of requests (default: 64)
export NUM_PREFIXES=8        # Number of different prefixes (default: 4)
export PREFIX_LEN=8192       # Each prefix length in chars (default: 8192)
export SUFFIX_LEN=32         # Unique suffix length in chars (default: 32)
export DATASET_FILE=./my_custom.jsonl  # Custom dataset file (default: multi_prefix.jsonl)
```

## Results

Benchmark results are saved to `results/` directory in JSON format. Each run includes:
- Throughput metrics
- Latency metrics (TTFT, TPOT, ITL)
- Per-request details (if `--save-detailed` is used)
- Metadata about the run

### Comparing Results

Use the comparison script to analyze cache routing impact:

```bash
# Compare round-robin vs cache-routing results
python compare-results.py \
  results/round-robin-*.json \
  results/cache-routing-multi-prefix-*.json
```

The comparison script shows:
- Performance differences between round-robin and cache-routing
- Cache hit benefits (lower TTFT for cached requests)
- Throughput improvements
- Insights about cache routing effectiveness

## Validation Criteria

### Single Instance
- ✅ All requests should be handled by master-9g_8b_thinking
- ✅ Baseline performance metrics established

### Round-Robin
- ✅ Requests should be distributed across both instances
- ✅ Load balancing should be approximately even
- ✅ No session stickiness (requests can go to different instances)

### Cache Routing
- ✅ Requests with the same `prompt_cache_key` should route to the same instance
- ✅ Different cache keys can route to different instances
- ✅ Session stickiness is maintained for the same cache key
- ✅ Cache hit benefits should be visible (lower TTFT for repeated keys)

### Cache Routing with Shared Prefix (Advanced Validation)

For more accurate cache routing validation, use the shared-prefix prompt generation script:

```bash
# Generate multi-prefix prompts (4 prefixes by default)
python gen-multi-prefix.py \
  --num-prompts 64 \
  --num-prefixes 4 \
  --prefix-len 8192 \
  --suffix-len 32 \
  --output multi_prefix.jsonl

# Run cache routing benchmark with multi-prefix dataset
export MODEL1_DIR=/path/to/9g_8b_thinking_llama
./bench-cache-routing.sh 172.22.162.18
```

**What to look for:**
- **TTFT (Time to First Token)**: Cache hits should have much lower TTFT than cache misses
- **Prefill latency**: Should be near zero for cached prefixes
- **Token throughput**: Should be higher for cache hits
- **Request distribution**: Check server logs to verify requests with same cache key route to same instance

**Expected behavior:**
- First request with a cache key: Normal TTFT (full prefill)
- Subsequent requests with same cache key: Much lower TTFT (cache hit)
- Different cache keys: May route to different instances, each with their own cache

## vLLM Bench Patches

This deployment case includes patches to vLLM bench to support `prompt_cache_key`:

1. **CLI Argument**: Added `--prompt-cache-key` argument to `vllm/benchmarks/serve.py`
2. **Payload Injection**: Modified `vllm/benchmarks/lib/endpoint_request_func.py` to inject `prompt_cache_key` into request payloads
3. **Dynamic Key Support**: Supports patterns like `bench_key_{request_id % 4}` for routing distribution testing

### Dynamic Key Patterns

The `--prompt-cache-key` argument supports dynamic key generation:

- `bench_key_{request_id}` - Uses the request ID directly
- `bench_key_{request_id % 4}` - Creates 4 different cache keys (0, 1, 2, 3)
- `bench_key_{request_id // 10}` - Groups requests into batches of 10

## Troubleshooting

### Services Not Starting

1. Check Docker container logs:
   ```bash
   docker logs -f infinilm-svc-master
   ```

2. Verify model path is correct:
   ```bash
   echo $MODEL1_DIR
   ls -la $MODEL1_DIR
   ```

3. Check port availability:
   ```bash
   netstat -tuln | grep -E ':(18000|8000|8100|8200|8101|8201)'
   ```

### Benchmark Failures

1. Verify vLLM environment is activated:
   ```bash
   conda activate vllm-bench
   python -c "import vllm; print(vllm.__version__)"
   ```

2. Check router accessibility:
   ```bash
   curl http://localhost:8000/health
   ```

3. Verify model is available:
   ```bash
   curl http://localhost:8000/models
   ```

### Cache Routing Not Working

1. Verify both instances are running:
   ```bash
   curl http://localhost:8101/health
   curl http://localhost:8201/health
   ```

2. Check service registry:
   ```bash
   curl http://localhost:18000/services | jq
   ```

3. Verify `prompt_cache_key` is being sent:
   - Check benchmark script output
   - Verify vLLM patches are applied correctly

## Files Structure

```
cache-routing-validation/
├── README.md                          # This file
├── install.defaults.sh                # Deployment defaults
├── start-master.sh                    # Start script for both instances
├── validate.sh                        # Validation script
├── setup-vllm-env.sh                  # vLLM environment setup
├── bench-single.sh                    # Single instance benchmark
├── bench-roundrobin.sh                # Round-robin benchmark
├── bench-cache-routing.sh            # Cache routing benchmark
├── config/
│   ├── master-9g_8b_thinking.toml    # Master instance config (port 8100)
│   └── slave-9g_8b_thinking.toml     # Slave instance config (port 8200)
└── results/                           # Benchmark results directory
```

## Related Documentation

- [InfiniLM-SVC Main Documentation](../../../README.md)
- [Babysitter Configuration](../../../rust/src/bin/README.md)
- [vLLM Benchmarks Documentation](https://github.com/vllm-project/vllm)

## Notes

- Both instances use the same model (9g_8b_thinking) but run on different ports
- The router handles routing logic based on `prompt_cache_key` presence
- Cache routing enables session stickiness for better cache hit rates
- Benchmark results can be compared across the three scenarios to validate routing behavior
