# Reproduce with InfiniCore issue/1004 and Compare

## 1. Build image (InfiniCore issue/1004 only, no deps phase)

From project root, with local InfiniCore at branch issue/1004 (e.g. `InfiniCore_pgv2`):

```bash
cd /home/zenghua/repos/InfiniLM-SVC
export RUNTIME_TAG=infinilm-svc:runtime-cache-type-routing-validation-issue1004
./docker/metax/build-image.sh --deployment-case cache-type-routing-validation \
  --phase build \
  --deps-image infinilm-svc:deps-cache-type-routing-validation \
  --infinicore-src /home/zenghua/repos/InfiniCore_pgv2
```

Wait until the build finishes and you see: `Runtime (deployment) image: infinilm-svc:runtime-cache-type-routing-validation-issue1004`.

## 1b. Check container while waiting for ready

If "Waiting for model..." takes too long, inspect the running container:

```bash
cd /home/zenghua/repos/InfiniLM-SVC/deployment/cases/cache-type-routing-validation
./check-container.sh           # show both containers
./check-container.sh qwen3-32b   # size-based master only
./check-container.sh 2paged       # 2paged master only
```

Or manually: `docker logs infinilm-svc-master-qwen3-32b --tail 50` (or `infinilm-svc-master-2paged-qwen3-32b`).

You can also set `MAX_READY_WAIT=300` (seconds) to fail sooner if the model never becomes ready.

## 2. Run reproduction with issue/1004 image

```bash
cd /home/zenghua/repos/InfiniLM-SVC/deployment/cases/cache-type-routing-validation
export IMAGE_NAME=infinilm-svc:runtime-cache-type-routing-validation-issue1004
export QWEN3_32B_DIR=/data-aisoft/zenghua/models/Qwen3-32B
./reproduce-results.sh
```

This writes new result JSONs under `results/` (size-based and 2paged, with current timestamp).

## 3. Compare new (issue/1004) vs old results

Auto-compare latest (new run) vs previous:

```bash
cd /home/zenghua/repos/InfiniLM-SVC/deployment/cases/cache-type-routing-validation
python compare-routing-strategies.py --auto-detect
```

To compare new issue/1004 run explicitly vs old baseline (e.g. 20260212):

```bash
# Replace NEW_* with the JSON filenames from your latest reproduce run
python compare-routing-strategies.py \
  --size-based results/size-based-routing-1.0qps-concurrency4-Qwen3-32B-NEW_TIMESTAMP.json \
  --2paged results/2paged-round-robin-1.0qps-concurrency4-Qwen3-32B-NEW_TIMESTAMP.json
```

Old baseline files (for reference):  
`results/size-based-routing-1.0qps-concurrency4-Qwen3-32B-20260212-172850.json`  
`results/2paged-round-robin-1.0qps-concurrency4-Qwen3-32B-20260212-174121.json`
