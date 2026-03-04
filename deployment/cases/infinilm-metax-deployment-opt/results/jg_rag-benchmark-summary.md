# jg_rag Benchmark Results Summary

Benchmark dataset: `bench/jg_rag_benchmark.jsonl` (40 requests, mixed RAG/translate/revise/policies modules)  
Router: 192.168.163.151:8000 | Request rate: 1.0 req/s | Max concurrency: 4

## Deployment Presets Compared

| Preset                     | Description     | GPU Layout                                     |
| -------------------------- | --------------- | ---------------------------------------------- |
| **1paged2static** (baseline) | Original config | 1 paged at master + 2× static cache at slave (4 GPU each, ports 8200, 8300) |
| **1paged1static1vllm**      | Slave preset 2  | 1 paged at master + 1× static (4 GPU) + 1× vLLM (4 GPU) at slave |
| **1paged2vllm**             | Slave preset    | 1 paged at master + 2× vLLM at slave (4 GPU each) |
| **3vllm**                   | Master + slave  | 1 vLLM at master + 2× vLLM at slave (4 GPU each) |


## Results Overview (Latest: 1paged2static 2026-02-28; 1paged1static1vllm/1paged2vllm/3vllm 2026-03-04)

| Metric                     | 1paged2static (baseline) | 1paged1static1vllm | 1paged2vllm | 3vllm |
| -------------------------- | ------------------------ | ------------------ | ----------- | ----- |
| **Completed**              | 40                       | 40                 | 40          | 40    |
| **Failed**                 | 0                        | 0                  | 0           | 0     |
| **Duration**               | 27.8 min                 | 11.5 min           | 18.0 min    | 27.5 min |
| **Mean TTFT**              | 22.3 s                   | 1.1 s              | 12.4 s      | 1.9 s |
| **Median TTFT**            | 12.2 s                   | 0.84 s             | 1.8 s       | 1.5 s |
| **P99 TTFT**               | 67.9 s                   | 4.7 s              | 60.3 s      | 5.9 s |
| **Mean TPOT**              | 316.4 ms                 | 165.3 ms           | 268.6 ms    | 601.4 ms |
| **Median TPOT**            | 276.2 ms                 | 65.8 ms            | 203.0 ms    | 566.6 ms |
| **P99 TPOT**               | 663.6 ms                 | 630.9 ms           | 775.2 ms    | 1115.9 ms |
| **Output Throughput**      | 9.28 tok/s               | 19.51 tok/s        | 14.51 tok/s | 6.18 tok/s |
| **Total Token Throughput** | 223.1 tok/s              | 539.3 tok/s        | 345.1 tok/s | 222.4 tok/s |


## Key Findings

- **1paged1static1vllm** (lower max_cache_len run): 100% success (40/40), ~2.4× shorter duration (11.5 min vs 27.8 min), ~2.4× higher total token throughput (539.3 vs 223.1 tok/s), and much lower TTFT (mean 1.1 s, median 0.84 s). vLLM contributes to faster prefill and token generation.
- **1paged2static** achieves 100% success rate but with longer duration and higher latency. Best for reliability when failures are unacceptable.
- **1paged2vllm** (1 paged master + 2 vLLM slave): 100% success (40/40), median TTFT 1.8 s, output throughput 14.51 tok/s, total token throughput 345.1 tok/s. Between 1paged2static and 1paged1static1vllm on throughput; lower mean TTFT variance than 1paged2static.
- **3vllm** (1 vLLM master + 2 vLLM slave): 100% success (40/40), low mean TTFT (1.9 s), but lower output throughput (6.18 tok/s) and higher TPOT (601 ms) than 1paged1static1vllm in this run. Total token throughput similar to 1paged2static (~222 tok/s).


## Result Files

| Preset        | Date       | File |
| ------------- | ---------- | ---- |
| 1paged2static       | 2026-02-28 | `jg_rag-baseline-2static4gpu-1.0qps-concurrency4-Qwen3-32B-20260228-093603.json` |
| 1paged1static1vllm  | 2026-03-04 | `jg_rag-baseline-1paged1static1vllm-1.0qps-concurrency4-Qwen3-32B-20260304-163421.json` (lower max_cache_len, no failure) |
| 1paged2vllm         | 2026-03-04 | `jg_rag-baseline-1paged2vllm-1.0qps-concurrency4-Qwen3-32B-20260304-154705.json` |
| 3vllm               | 2026-03-04 | `jg_rag-baseline-3vllm-1.0qps-concurrency4-Qwen3-32B-20260304-120004.json` |

