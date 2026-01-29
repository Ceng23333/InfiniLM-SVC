# Debugging Installation Progress

This guide explains how to monitor and debug the installation process when building the Docker image.

## Quick Methods

### 1. Use Debug Dockerfile (Recommended)

Use the debug version of the Dockerfile which provides step-by-step output:

```bash
cd /path/to/InfiniLM-SVC/deployment/cases/infinilm-metax-deployment

# Build with debug Dockerfile
docker build --progress=plain \
    -f Dockerfile.gpu-factory.debug \
    -t infinilm-svc:debug .
```

The debug Dockerfile splits the installation into visible steps and shows progress at each stage.

### 2. Build with Plain Progress Output

Use `--progress=plain` to see all output without Docker's fancy formatting:

```bash
docker build --progress=plain \
    -f Dockerfile.gpu-factory \
    -t infinilm-svc:infinilm-demo .
```

### 3. Build Without Cache

Force a fresh build to see all steps:

```bash
docker build --no-cache --progress=plain \
    -f Dockerfile.gpu-factory \
    -t infinilm-svc:infinilm-demo .
```

### 4. Enable Verbose Shell Output

Modify the Dockerfile temporarily to add `set -x` for command tracing:

```dockerfile
RUN set -x && \
    ./scripts/install.sh \
        --install-path /usr/local/bin \
        --deployment-case infinilm-metax-deployment
```

## Advanced Debugging

### Method 1: Interactive Build Container

Build up to a certain point, then inspect:

```bash
# Build up to the install step
docker build --target <stage> -t infinilm-svc:partial .

# Run interactively to debug
docker run -it --rm infinilm-svc:partial bash

# Inside container, run install manually
./scripts/install.sh --install-path /usr/local/bin --deployment-case infinilm-metax-deployment
```

### Method 2: Save Build Output to File

```bash
docker build --progress=plain \
    -f Dockerfile.gpu-factory \
    -t infinilm-svc:infinilm-demo . \
    2>&1 | tee build.log

# Review the log
less build.log
```

### Method 3: Test Install Script Locally

Before building the Docker image, test the install script in a similar environment:

```bash
# Start a container from the base image
docker run -it --rm \
    -v $(pwd):/app \
    cr.metax-tech.com/public-ai-release-wb/x201/vllm:hpcc2.32.0.11-torch2.4-py310-kylin2309a-arm64 \
    bash

# Inside container
cd /app
export DEPLOYMENT_CASE=infinilm-metax-deployment
./scripts/install.sh --install-path /usr/local/bin --deployment-case infinilm-metax-deployment
```

### Method 4: Check Specific Installation Steps

The install.sh script performs these steps in order:

1. **Load deployment case defaults** (`load_deployment_case_preset`)
2. **Install system dependencies** (`install_system_deps`)
   - Detects OS
   - Installs build tools (gcc, pkg-config, libssl-dev, etc.)
3. **Install Rust** (`install_rust`)
   - Checks if Rust exists
   - Installs via rustup if needed
4. **Build binaries** (`build_binaries`)
   - Compiles infini-registry, infini-router, infini-babysitter
5. **Install binaries** (`install_binaries`)
   - Copies binaries to /usr/local/bin
6. **Install Python dependencies** (`install_python_deps`)
   - Installs from requirements files
7. **Install optional components** (InfiniCore, InfiniLM, etc.)

To see which step fails, look for these markers in the output:
- `[1/5] Installing system dependencies...`
- `[2/5] Installing Rust...`
- `[3/5] Building Rust binaries...`
- `[4/5] Installing binaries...`
- `[5/5] Setting up scripts and directories...`

### Method 5: Add Debug Output to Dockerfile

Temporarily modify the Dockerfile to add more verbose output:

```dockerfile
# Add before RUN ./scripts/install.sh
RUN echo "Environment:" && \
    env | grep -E "(DEPLOYMENT_CASE|INSTALL|PATH)" && \
    echo "" && \
    echo "OS Detection:" && \
    cat /etc/os-release 2>/dev/null || echo "No /etc/os-release" && \
    echo "" && \
    echo "Available tools:" && \
    which curl || echo "curl not found" && \
    which rustc || echo "rustc not found" && \
    echo ""

RUN ./scripts/install.sh \
    --install-path /usr/local/bin \
    --deployment-case infinilm-metax-deployment || \
    (echo "Installation failed! Exit code: $?" && exit 1)
```

## Common Issues and Solutions

### Issue: Installation hangs at Rust installation

**Solution**: Check if network is accessible:
```dockerfile
RUN curl -I https://sh.rustup.rs || echo "Network check failed"
```

### Issue: OS detection fails

**Solution**: Check OS release file:
```dockerfile
RUN cat /etc/os-release || echo "No os-release file"
```

### Issue: Build dependencies not found

**Solution**: Check what package manager is available:
```dockerfile
RUN which apt-get || which yum || which apk || echo "No package manager found"
```

### Issue: Python dependencies fail

**Solution**: Check Python environment:
```dockerfile
RUN python3 --version && \
    python3 -m pip --version || echo "pip not available"
```

## Monitoring Tips

1. **Use `--progress=plain`** - Always use this flag to see all output
2. **Build without cache first** - Use `--no-cache` to ensure fresh build
3. **Check intermediate layers** - Use `docker history <image>` to see layer sizes
4. **Save failed builds** - Don't remove failed containers immediately, inspect them:
   ```bash
   docker ps -a  # Find failed container
   docker commit <container-id> debug-image
   docker run -it debug-image bash
   ```

## Example: Full Debug Build Command

```bash
cd /path/to/InfiniLM-SVC/deployment/cases/infinilm-metax-deployment

# Full debug build with all monitoring
docker build \
    --progress=plain \
    --no-cache \
    --build-arg BASE_IMAGE=your-base-image:tag \
    -f Dockerfile.gpu-factory.debug \
    -t infinilm-svc:debug \
    . 2>&1 | tee build-debug.log

# Check the log for errors
grep -i error build-debug.log
grep -i "failed\|✗" build-debug.log
```

## Quick Reference

| Method | Command | Best For |
|--------|---------|----------|
| Debug Dockerfile | `docker build -f Dockerfile.gpu-factory.debug --progress=plain .` | Step-by-step monitoring |
| Plain output | `docker build --progress=plain .` | Seeing all output |
| No cache | `docker build --no-cache .` | Fresh build |
| Save logs | `docker build ... 2>&1 \| tee build.log` | Reviewing later |
| Interactive | `docker run -it <image> bash` | Manual testing |
