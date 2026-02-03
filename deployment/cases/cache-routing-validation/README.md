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
- Good for testing routing distribution, but limited cache benefit

**Accumulating Context** (recommended for chatbot scenarios):
```bash
python gen-accumulate-context.py \
  --num-conversations 4 \
  --messages-per-conv 8 \
  --context-len 2048 \
  --new-msg-len 128 \
  --output accumulate_context.jsonl
```

**Parameters:**
- `--num-conversations`: Number of different conversations (default: 4)
- `--messages-per-conv`: Number of messages per conversation (default: 8)
- `--context-len`: Length of context added by each message (default: 2048)
- `--new-msg-len`: Length of new message content (default: 128)
- `--output`: Output JSONL file path (default: accumulate_context.jsonl)

**Why use accumulating context?**
- Simulates real chatbot behavior where each request contains full conversation history
- Early messages have short context, later messages have long accumulated context
- Cache routing benefits **increase dramatically** as shared prefix grows
- Better matches real-world chatbot workloads where context accumulates over time
- Shows the **true value** of cache routing for conversational AI

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
**Dataset**: Accumulating context (chatbot scenario) - same as cache-routing for fair comparison
**Expected Behavior**: Requests should be distributed across both instances in round-robin fashion

### Cache Routing Benchmark

Tests session-aware routing using prompt_cache_key:

```bash
conda activate vllm-bench
export MODEL1_DIR=/path/to/9g_8b_thinking_llama
./bench-cache-routing.sh [REGISTRY_IP]
```

**Configuration**: Both instances running, with prompt_cache_key
**Dataset**: Accumulating context (chatbot scenario) - same as round-robin for fair comparison

**Expected Behavior**:
- Requests with the same `prompt_cache_key` should route to the same instance
- Each conversation uses the same cache key (`conv_{conversation_id}`)
- Requests from the same conversation share accumulating context (growing shared prefix)
- **Cache hits** show significantly lower TTFT compared to round-robin routing
- Later messages in conversations benefit most from cached prefixes
- This simulates real chatbot scenarios where context accumulates over time

**Why accumulating context?**
- Real chatbots send full conversation history with each request
- Early messages have short context, later messages have long accumulated context
- Cache routing benefits **increase dramatically** as shared prefix grows
- This scenario shows the **true value** of cache routing for conversational AI
- See [Performance Benefits](#cache-routing-performance-benefits) section for benchmark results

**Compare Results:**
```bash
# After running both benchmarks, compare the results
python compare-results.py \
  results/round-robin-*.json \
  results/cache-routing-*.json
```


**Note**: `prompt_cache_key` is now read directly from the JSON dataset. Each record in the accumulating context dataset includes an explicit `prompt_cache_key` field (e.g., `conv_0`, `conv_1`), so no CLI argument is needed.

## Benchmark Configuration

You can customize benchmark parameters via environment variables:

```bash
export REQUEST_RATE=2.0              # Requests per second (default: 1.0)
export NUM_CONVERSATIONS=4            # Number of conversations (default: 4)
export MESSAGES_PER_CONV=8            # Messages per conversation (default: 8)
export CONTEXT_LEN=2048               # Context length per message (default: 2048)
export NEW_MSG_LEN=128                # New message length (default: 128)
export DATASET_FILE=./my_custom.jsonl # Custom dataset file (default: accumulate_context.jsonl)
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
# Compare round-robin vs cache-routing results (backward compatible)
python compare-results.py \
  results/round-robin-*.json \
  results/cache-routing-*.json

# Compare single-instance vs round-robin
python compare-results.py \
  --single results/single-instance-*.json \
  --roundrobin results/round-robin-*.json

# Compare single-instance vs cache-routing
python compare-results.py \
  --single results/single-instance-*.json \
  --cache-routing results/cache-routing-*.json

# Compare all three configurations (comprehensive analysis)
python compare-results.py \
  --single results/single-instance-*.json \
  --roundrobin results/round-robin-*.json \
  --cache-routing results/cache-routing-*.json
```

The comparison script shows:
- Performance differences between configurations
- Cache hit benefits (lower TTFT for cached requests)
- Load balancing benefits (round-robin vs single-instance)
- Throughput improvements
- Insights about cache routing effectiveness

### Cache Routing Performance Benefits

Based on benchmark results using accumulating context dataset (chatbot scenario), comprehensive comparison of all three deployment configurations:

#### Comprehensive Performance Comparison

| Metric | Single-Instance | Round-Robin | Cache-Routing | Round-Robin vs Single | Cache-Routing vs Single | Cache-Routing vs Round-Robin |
|--------|----------------|-------------|---------------|----------------------|------------------------|----------------------------|
| **Mean TTFT (ms)** | 11851.87 | 3487.55 | 2375.03 | **+70.57% ↓** | **+79.96% ↓** | **+31.90% ↓** |
| **Median TTFT (ms)** | 12465.53 | 2882.27 | 2077.73 | **+76.88% ↓** | **+83.33% ↓** | **+27.91% ↓** |
| **P99 TTFT (ms)** | 14741.05 | 7284.62 | 5064.15 | **+50.58% ↓** | **+65.65% ↓** | **+30.48% ↓** |
| **Mean TPOT (ms)** | 487.74 | 239.56 | 218.77 | **+50.88% ↓** | **+55.15% ↓** | **+8.68% ↓** |
| **Median TPOT (ms)** | 485.22 | 234.48 | 208.22 | **+51.68% ↓** | **+57.09% ↓** | **+11.20% ↓** |
| **P99 TPOT (ms)** | 562.13 | 298.05 | 286.43 | **+46.98% ↓** | **+49.05% ↓** | **+3.90% ↓** |
| **Output Throughput (tok/s)** | 53.64 | 100.42 | 106.64 | **+87.22% ↑** | **+98.82% ↑** | **+6.19% ↑** |
| **Total Token Throughput (tok/s)** | 265.57 | 497.21 | 528.00 | **+87.22% ↑** | **+98.82% ↑** | **+6.19% ↑** |
| **Request Throughput (req/s)** | 0.21 | 0.39 | 0.42 | **+87.22% ↑** | **+98.82% ↑** | **+6.19% ↑** |

**Test Configuration:**
- Dataset: Accumulating context (4 conversations, 8 messages each, 32 total requests)
- Context length: 1024 chars per message
- New message length: 128 chars
- Request rate: 1.0 req/s
- Model: 9g_8b_thinking

#### Key Insights

✅ **Cache-Routing shows best overall performance:**
   - **31.9% improvement vs Round-Robin** in Mean TTFT
   - **80.0% improvement vs Single-Instance** in Mean TTFT
   - This indicates cache hits are working effectively
   - Accumulating context scenario maximizes cache benefits
   - Later messages in conversations benefit most from cached prefixes

✅ **Round-Robin shows significant improvement vs Single-Instance:**
   - **70.6% improvement** in Mean TTFT
   - **87.2% improvement** in throughput metrics
   - This indicates load balancing is distributing load effectively
   - Two instances handle requests better than one

✅ **Consistent improvements across all latency metrics:**
   - Mean, median, and P99 TTFT all show significant improvements
   - TPOT improvements indicate better token generation efficiency
   - Lower variance in response times

✅ **Throughput gains:**
   - Cache-Routing: 6.19% improvement vs Round-Robin
   - Round-Robin: 87.22% improvement vs Single-Instance
   - Cache-Routing: 98.82% improvement vs Single-Instance
   - Better resource utilization through cache reuse and load balancing
   - Higher overall system capacity

**Why these benefits matter:**
- **Lower TTFT**: Users experience faster first-token response times, critical for interactive applications
- **Better throughput**: System can handle more requests per second with the same resources
- **Consistent performance**: Lower variance means more predictable user experience
- **Cost efficiency**: Cache reuse reduces redundant computation, improving cost per request
- **Scalability**: Load balancing enables horizontal scaling with multiple instances

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
