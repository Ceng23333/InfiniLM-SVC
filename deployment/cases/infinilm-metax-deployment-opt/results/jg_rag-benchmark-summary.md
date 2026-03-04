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


## Results Overview (Latest: 1paged2static/1paged1static1vllm 2026-02-28; 3vllm 2026-03-04)

| Metric                     | 1paged2static (baseline) | 1paged1static1vllm | 3vllm |
| -------------------------- | ---------------------- | ------------ | ----- |
| **Completed**              | 40                     | 39           | 40    |
| **Failed**                 | 0                      | 1            | 0     |
| **Duration**               | 27.8 min               | 10.9 min     | 27.5 min |
| **Mean TTFT**              | 22.3 s                 | 3.5 s        | 1.9 s |
| **Median TTFT**            | 12.2 s                 | 1.4 s        | 1.5 s |
| **P99 TTFT**               | 67.9 s                 | 24.2 s       | 5.9 s |
| **Mean TPOT**              | 316.4 ms               | 189.3 ms     | 601.4 ms |
| **Median TPOT**            | 276.2 ms               | 79.7 ms      | 566.6 ms |
| **P99 TPOT**               | 663.6 ms               | 668.7 ms     | 1115.9 ms |
| **Output Throughput**      | 9.28 tok/s             | 24.43 tok/s  | 6.18 tok/s |
| **Total Token Throughput** | 223.1 tok/s            | 538.6 tok/s  | 222.4 tok/s |


## Key Findings

- **1paged1static1vllm** has ~2.5× shorter duration (10.9 min vs 27.8 min), ~2.4× higher total token throughput (538.6 vs 223.1 tok/s), and much lower TTFT (mean 3.5 s vs 22.3 s). vLLM contributes to faster prefill and token generation. One failed request out of 40.
- **1paged2static** achieves 100% success rate but with longer duration and higher latency. Best for reliability when failures are unacceptable.
- **3vllm** (1 vLLM master + 2 vLLM slave): 100% success (40/40), low mean TTFT (1.9 s), but lower output throughput (6.18 tok/s) and higher TPOT (601 ms) than 1paged1static1vllm in this run. Total token throughput similar to 1paged2static (~222 tok/s).


## Result Files

| Preset        | Date       | File |
| ------------- | ---------- | ---- |
| 1paged2static       | 2026-02-28 | `jg_rag-baseline-2static4gpu-1.0qps-concurrency4-Qwen3-32B-20260228-093603.json` |
| 1paged1static1vllm  | 2026-02-28 | `jg_rag-baseline-1static1vllm-1.0qps-concurrency4-Qwen3-32B-20260228-211826.json` |
| 1paged2vllm         | TBD        | Run: `LABEL=jg_rag-baseline-1paged2vllm ./run-jg_rag-benchmark.sh <ROUTER_HOST>` |
| 3vllm               | 2026-03-04 | `jg_rag-baseline-3vllm-1.0qps-concurrency4-Qwen3-32B-20260304-120004.json` |

