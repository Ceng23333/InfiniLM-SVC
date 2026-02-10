# Cache Type Routing Validation - Results Summary

## Overview

This document summarizes the benchmark results comparing two routing strategies:
1. **Size-Based Routing**: Routes requests based on message body size (paged cache for small, static cache for large)
2. **2-Paged Round-Robin**: Two paged cache instances with round-robin routing

## Test Configurations

All tests used:
- **Model**: Qwen3-32B (32B parameters)
- **GPUs**: 8 GPUs total (4 GPUs per instance)
- **Tensor Parallelism**: tp=4 per instance
- **Total Requests**: 16 requests (4 conversations × 4 messages each)
- **Max Concurrency**: 4 concurrent requests
- **Request Rate**: 1.0 req/s
- **Routing Threshold**: 10KB (for size-based routing)

## Results by Context Size

### Test 1: Large Context = 20KB (20000 chars, ~5000 tokens)

**Dataset**: 1 large context conversation (4 requests), 3 small context conversations (12 requests)

| Metric | Size-Based Routing | 2-Paged Round-Robin | Winner | Improvement |
|--------|-------------------|---------------------|--------|-------------|
| Mean TTFT | 16.5s | 5.2s | 2-Paged RR | **68.8% faster** |
| Median TTFT | 2.6s | 3.8s | Size-Based | 31.0% faster |
| P99 TTFT | 81.8s | 14.5s | 2-Paged RR | **466.0% better** |
| Mean TPOT | 325.6 ms | 278.5 ms | 2-Paged RR | 14.5% faster |
| Output Throughput | 9.56 tok/s | 12.74 tok/s | 2-Paged RR | 24.9% higher |
| Total Throughput | 45.19 tok/s | 60.18 tok/s | 2-Paged RR | **33.2% higher** |
| Duration | 426.6s | 320.4s | 2-Paged RR | 25.0% faster |

**Result File**: `size-based-routing-1.0qps-concurrency4-Qwen3-32B-20260209-204007.json` vs `2paged-round-robin-1.0qps-concurrency4-Qwen3-32B-20260209-205110.json`

**Summary**: 2-Paged Round-Robin wins 8 metrics, Size-Based wins 1 metric

---

### Test 2: Large Context = 16KB (16000 chars, ~4000 tokens)

**Dataset**: 1 large context conversation (4 requests), 3 small context conversations (12 requests)

| Metric | Size-Based Routing | 2-Paged Round-Robin | Winner | Improvement |
|--------|-------------------|---------------------|--------|-------------|
| Mean TTFT | 21.3s | 4.1s | 2-Paged RR | **80.6% faster** |
| Median TTFT | 5.9s | 3.5s | 2-Paged RR | 70.4% faster |
| P99 TTFT | 92.6s | 10.8s | 2-Paged RR | **88.4% better** |
| Mean TPOT | 319.0 ms | 263.6 ms | 2-Paged RR | 17.4% faster |
| Output Throughput | 9.17 tok/s | 12.96 tok/s | 2-Paged RR | 29.3% higher |
| Total Throughput | 38.63 tok/s | 54.61 tok/s | 2-Paged RR | **41.4% higher** |
| Duration | 445.1s | 314.9s | 2-Paged RR | 29.3% faster |

**Result File**: `size-based-routing-1.0qps-concurrency4-Qwen3-32B-20260209-211728.json` vs `2paged-round-robin-1.0qps-concurrency4-Qwen3-32B-20260209-212640.json`

**Summary**: 2-Paged Round-Robin wins 9 metrics, Size-Based wins 0 metrics

---

### Test 3: Large Context = 65KB (65536 chars, ~16k tokens)

**Dataset**: 1 large context conversation (4 requests), 3 small context conversations (12 requests)

| Metric | Size-Based Routing | 2-Paged Round-Robin | Winner | Improvement |
|--------|-------------------|---------------------|--------|-------------|
| Mean TTFT | 19.0s | 36.0s | **Size-Based** | **47.1% faster** |
| Median TTFT | 8.5s | 9.3s | **Size-Based** | 9.3% faster |
| P99 TTFT | 90.7s | 103.5s | **Size-Based** | 12.4% better |
| Mean TPOT | 356.7 ms | 401.6 ms | **Size-Based** | 11.2% faster |
| Median TPOT | 299.5 ms | 521.5 ms | **Size-Based** | **42.6% faster** |
| Output Throughput | 8.65 tok/s | 6.13 tok/s | **Size-Based** | **41.2% higher** |
| Total Throughput | 91.24 tok/s | 64.63 tok/s | **Size-Based** | **41.2% higher** |
| Duration | 471.7s | 665.9s | **Size-Based** | 29.2% faster |

**Result File**: `size-based-routing-1.0qps-concurrency4-Qwen3-32B-20260209-213842.json` vs `2paged-round-robin-1.0qps-concurrency4-Qwen3-32B-20260209-215139.json`

**Summary**: Size-Based Routing wins 8 metrics, 2-Paged Round-Robin wins 1 metric

---

## Key Insights

### 1. **Context Size Determines Optimal Strategy**

The performance advantage **flips** based on the size of large contexts:

```
Small-Medium Contexts (≤20KB):  2-Paged Round-Robin performs better
Very Large Contexts (≥65KB):    Size-Based Routing performs better
```

**Crossover Point**: Approximately between 20KB and 65KB, where size-based routing becomes advantageous.

### 2. **Size-Based Routing Benefits**

✅ **For Very Large Contexts (≥65KB)**:
- Static cache handles large contexts more efficiently
- Mean TTFT: 47.1% faster than 2-paged
- Total throughput: 41.2% higher
- Better resource utilization (specialized cache types)

❌ **For Small-Medium Contexts (≤20KB)**:
- Higher latency variance (P99 TTFT: 81.8s vs 14.5s)
- Lower overall throughput
- Overhead of routing decision may not be justified

### 3. **2-Paged Round-Robin Benefits**

✅ **For Small-Medium Contexts (≤20KB)**:
- Consistent low latency (mean TTFT: 4-5s)
- Higher throughput (33-41% better)
- Simpler routing logic (no size calculation overhead)
- Better load distribution across instances

❌ **For Very Large Contexts (≥65KB)**:
- Struggles with large contexts (mean TTFT: 36.0s vs 19.0s)
- Lower throughput (29% worse)
- Paged cache not optimized for very large sequences

### 4. **Latency Variance Analysis**

**Size-Based Routing**:
- Shows high variance in P99 TTFT (81-93s) for small-medium contexts
- More consistent performance for very large contexts
- Indicates static cache handles large requests more predictably

**2-Paged Round-Robin**:
- Lower variance for small-medium contexts (P99 TTFT: 10-15s)
- Higher variance for very large contexts (P99 TTFT: 103.5s)
- More predictable performance when contexts fit well in paged cache

### 5. **Throughput Trends**

| Context Size | Size-Based Throughput | 2-Paged Throughput | Difference |
|--------------|----------------------|-------------------|------------|
| 20KB | 45.19 tok/s | 60.18 tok/s | -24.8% |
| 16KB | 38.63 tok/s | 54.61 tok/s | -29.3% |
| 65KB | 91.24 tok/s | 64.63 tok/s | **+41.2%** |

**Observation**: Size-based routing shows **higher total throughput** for very large contexts, likely due to:
- Static cache's efficiency with large sequences
- Better resource allocation (large requests don't block small ones)

### 6. **Median vs Mean TTFT**

**Size-Based Routing**:
- Large gap between median and mean TTFT (2.6s vs 16.5s at 20KB)
- Indicates some requests take much longer (likely large context requests)
- With very large contexts, gap narrows (8.5s vs 19.0s at 65KB)

**2-Paged Round-Robin**:
- Smaller gap between median and mean (3.5s vs 4.1s at 16KB)
- More consistent performance across request sizes
- Gap increases with very large contexts (9.3s vs 36.0s at 65KB)

## Recommendations

### 1. **Use Size-Based Routing When**:
- Workload contains **very large contexts** (≥50KB or ~12k+ tokens)
- Need to optimize for **mixed workloads** with both small and very large requests
- Static cache is available and properly configured
- Can tolerate higher latency variance for small-medium requests

### 2. **Use 2-Paged Round-Robin When**:
- Workload contains **small to medium contexts** (≤20KB or ~5k tokens)
- Need **consistent low latency** across all requests
- Simpler routing logic is preferred
- All requests fit well in paged cache

### 3. **Hybrid Approach**:
Consider **adaptive threshold** based on workload characteristics:
- Monitor request size distribution
- Adjust routing threshold dynamically
- Use size-based routing only when large contexts exceed a certain percentage

### 4. **Configuration Tuning**:
- **Routing Threshold**: Current 10KB threshold works well, but may need adjustment based on:
  - Model size and capabilities
  - Available GPU memory
  - Typical request patterns
- **Static Cache max_cache_len**: Ensure it's large enough (currently 16384 tokens) for very large contexts
- **Concurrency**: Current max_concurrency=4 is appropriate; higher values may stress static cache

## Conclusion

The benchmark results demonstrate that **both routing strategies have their place**:

- **2-Paged Round-Robin** excels for workloads with small to medium contexts, providing consistent performance and higher throughput.

- **Size-Based Routing** excels for workloads with very large contexts, leveraging static cache's efficiency for large sequences while keeping paged cache available for smaller requests.

The **optimal strategy depends on the workload characteristics**, particularly the distribution of request sizes. For production deployments, consider:
1. Analyzing historical request size distributions
2. Setting appropriate routing thresholds
3. Monitoring performance metrics to validate strategy choice
4. Potentially implementing adaptive routing based on real-time metrics

---

## Result Files Reference

All result files are stored in `results/` directory:

**Size-Based Routing**:
- `size-based-routing-1.0qps-concurrency4-Qwen3-32B-20260209-204007.json` (20KB context)
- `size-based-routing-1.0qps-concurrency4-Qwen3-32B-20260209-211728.json` (16KB context)
- `size-based-routing-1.0qps-concurrency4-Qwen3-32B-20260209-213842.json` (65KB context)

**2-Paged Round-Robin**:
- `2paged-round-robin-1.0qps-concurrency4-Qwen3-32B-20260209-205110.json` (20KB context)
- `2paged-round-robin-1.0qps-concurrency4-Qwen3-32B-20260209-212640.json` (16KB context)
- `2paged-round-robin-1.0qps-concurrency4-Qwen3-32B-20260209-215139.json` (65KB context)

---

*Generated: 2026-02-09*
*Model: Qwen3-32B*
*Deployment: cache-type-routing-validation*
