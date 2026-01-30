# Troubleshooting Guide for InfiniLM-SVC Deployment

This document contains troubleshooting information for common issues encountered during InfiniLM-SVC deployment.

## Table of Contents

1. [Device Access Issues During Build](#device-access-issues-during-build)
2. [InfiniCore Import Errors](#infinicore-import-errors)
3. [Service Discovery Issues](#service-discovery-issues)
4. [Network and Proxy Issues](#network-and-proxy-issues)
5. [Build Cache and Performance](#build-cache-and-performance)

---

## Device Access Issues During Build

### Problem

During Docker image build, verification of InfiniCore installation may fail with errors like:

```
Error Code 3 in `hcGetDeviceCount(count)` from getDeviceCount at src/infinirt/metax/infinirt_metax.cc:15
RuntimeError: `infinirtGetAllDeviceCount(device_counter.data())` failed with error: Internal Error
```

### Root Cause

The InfiniCore Python package attempts to query device counts during import initialization. This requires access to HPCC devices (`/dev/dri`, `/dev/htcd`, `/dev/infiniband`), which are **not available during Docker build phase**.

### Solution

**This is expected behavior and does not indicate a problem.** The verification step has been updated to:

1. **Detect device-related errors** and treat them as expected during build
2. **Skip device count checks** during Docker build phase
3. **Verify installation** will work correctly at runtime when devices are properly mounted

### Verification at Runtime

Devices are properly mounted when using `start-master.sh` or `start-slave.sh`:

```bash
--device /dev/dri
--device /dev/htcd
--device /dev/infiniband
--group-add video
--privileged=true
```

To verify devices are accessible at runtime:

```bash
# Check device access inside container
docker exec infinilm-svc-master ls -la /dev/dri /dev/htcd /dev/infiniband

# Test InfiniCore import
docker exec infinilm-svc-master python3 -c "import infinicore; print(infinicore.get_device_count('metax'))"
```

### Related Files

- `scripts/install.sh`: Verification logic (lines ~1636-1700)
- `start-master.sh`: Device mounting (lines 110-113)
- `start-slave.sh`: Device mounting (lines 257-260)

---

## InfiniCore Import Errors

### Problem: `ImportError: cannot import name '_infinicore' from 'infinicore.lib'`

This error occurs when the `_infinicore` shared library is not found or not properly built.

### Solutions

1. **Check INFINI_ROOT**: Ensure `INFINI_ROOT` is set correctly (default: `/root/.infini`)
   ```bash
   export INFINI_ROOT=/root/.infini
   ```

2. **Verify library exists**:
   ```bash
   find ${INFINI_ROOT}/lib -name "*infinicore*.so"
   ```

3. **Check LD_LIBRARY_PATH**: Ensure library paths are in `LD_LIBRARY_PATH`
   ```bash
   export LD_LIBRARY_PATH="${INFINI_ROOT}/lib:${HPCC_PATH}/lib:${LD_LIBRARY_PATH}"
   ```

4. **Rebuild _infinicore**: If missing, rebuild explicitly:
   ```bash
   cd /workspace/InfiniCore
   xmake build _infinicore
   xmake install _infinicore
   ```

### Environment Setup

The `env-set.sh` script sets up required environment variables:

```bash
export INFINI_ROOT=/root/.infini
export HPCC_PATH=/opt/hpcc
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$INFINI_ROOT/lib:$HPCC_PATH/lib
```

Ensure this script is sourced before importing InfiniCore.

---

## Service Discovery Issues

### Problem: Services not appearing in `/services` endpoint

During validation, services may not appear in the registry's `/services` endpoint even though models are functional.

### Root Cause

Services may be registered with different naming conventions or may take time to register after container startup.

### Verification

Even if services don't appear in `/services`, check:

1. **Models are available**:
   ```bash
   curl http://localhost:8000/models
   ```

2. **Chat completions work**:
   ```bash
   curl -X POST http://localhost:8000/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"model": "9g_8b_thinking", "messages": [{"role": "user", "content": "Hello"}]}'
   ```

3. **Check container logs**:
   ```bash
   docker logs infinilm-svc-master | grep -i "babysitter\|service"
   ```

### Solution

This is typically a non-critical issue. If models are responding, the deployment is functional. Service registration may improve with:

- Longer wait time after container startup (60+ seconds)
- Checking babysitter logs for registration status
- Verifying registry URL in babysitter configs

---

## Network and Proxy Issues

### Problem: Build fails with TLS/SSL errors or connection timeouts

### Solutions

1. **Set proxy for Docker build**:
   ```bash
   ./build-image.sh --proxy http://127.0.0.1:7890
   ```

2. **Use host network for localhost proxy**:
   The build script automatically detects localhost proxies and uses `--network host`.

3. **Check proxy accessibility**:
   ```bash
   curl -v --proxy http://127.0.0.1:7890 https://pypi.org/simple
   ```

4. **Fallback to PyPI**: The install script automatically falls back to PyPI if mirror fails.

### Proxy Configuration

Proxy settings are passed via build args:
- `HTTP_PROXY`
- `HTTPS_PROXY`
- `ALL_PROXY`
- `NO_PROXY`

These are set as environment variables in the container.

---

## Build Cache and Performance

### Problem: Slow rebuilds due to redundant downloads

### Solutions

1. **Use BuildKit cache mounts** (Docker 19.03+):
   ```bash
   DOCKER_BUILDKIT=1 docker build \
     --mount=type=cache,target=/root/.cargo \
     --mount=type=cache,target=/root/.cache/pip \
     -f Dockerfile.gpu-factory -t infinilm-svc:demo .
   ```

2. **Cache directories prepared**:
   Cache directories are created at `~/.docker-build-cache/infinilm-svc/`:
   - `cargo/`: Rust crate cache
   - `pip/`: Python package cache
   - `cache/`: General cache
   - `tmp/`: Temporary files

3. **For Docker 18.09**: Cache directories are prepared but require manual management or BuildKit upgrade.

### Performance Tips

- Use `--no-cache` only when necessary
- Keep base image layers cached
- Use multi-stage builds for large dependencies
- Mount InfiniCore/InfiniLM from host if rebuilding frequently

---

## Additional Resources

- [InfiniCore README](https://github.com/InfiniTensor/InfiniCore)
- [InfiniLM README](https://github.com/InfiniTensor/InfiniLM)
- [Docker BuildKit Documentation](https://docs.docker.com/build/buildkit/)

---

## Contributing

If you encounter issues not covered here, please:

1. Check container logs: `docker logs <container-name>`
2. Check build logs: `build-*.log` files
3. Verify environment variables: `docker exec <container> env | grep -E "INFINI|HPCC|LD_LIBRARY"`
4. Document the issue and solution for future reference
