# Troubleshooting Guide

Common issues and solutions when building and installing InfiniLM-SVC.

## OpenSSL Build Errors

### Problem

Build fails with error:
```
Could not find directory of OpenSSL installation
The system library `openssl` required by crate `openssl-sys` was not found.
```

### Solution

Install OpenSSL development libraries:

**Ubuntu/Debian/Kylin Linux:**
```bash
sudo apt-get update
sudo apt-get install libssl-dev pkg-config
```

**CentOS/RHEL/Fedora:**
```bash
sudo yum install openssl-devel pkgconfig
# or
sudo dnf install openssl-devel pkgconfig
```

**Alpine Linux:**
```bash
apk add openssl-dev pkgconfig
```

**Verify installation:**
```bash
pkg-config --exists openssl && echo "✓ OpenSSL found" || echo "✗ OpenSSL not found"
```

**If OpenSSL is in non-standard location:**
```bash
export OPENSSL_DIR=/path/to/openssl
export PKG_CONFIG_PATH=/path/to/openssl/lib/pkgconfig
./scripts/install.sh
```

## OS Detection Issues

### Problem

Script shows "Unknown OS" and skips system dependencies.

### Solution

The script now includes improved OS detection that:
1. Detects Kylin Linux and other Debian/Ubuntu-based distributions
2. Falls back to package manager detection (apt-get, yum, apk)
3. Attempts installation even if OS is unknown

**Manual installation if auto-detection fails:**
```bash
# For Debian/Ubuntu/Kylin-based systems
sudo apt-get install build-essential pkg-config libssl-dev curl bash

# For CentOS/RHEL
sudo yum install gcc pkgconfig openssl-devel curl bash

# For Alpine
apk add build-base pkgconfig openssl-dev curl bash
```

## Rust Installation Issues

### Problem

Rust installation fails or cargo command not found.

### Solution

**Reinstall Rust:**
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

**Verify installation:**
```bash
rustc --version
cargo --version
```

**Update Rust:**
```bash
rustup update
```

## Build Out of Memory

### Problem

Build fails due to insufficient memory.

### Solution

**Reduce build parallelism:**
```bash
CARGO_BUILD_JOBS=2 cargo build --release
```

**Or in install script:**
```bash
export CARGO_BUILD_JOBS=2
./scripts/install.sh
```

## Permission Denied Errors

### Problem

Script fails with "Permission denied" when installing binaries.

### Solution

**Use sudo for system installation:**
```bash
sudo ./scripts/install.sh
```

**Or install to user directory:**
```bash
./scripts/install.sh --install-path ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"
```

## Docker Build Issues

### Problem

Docker build fails with OpenSSL errors.

### Solution

**Ensure base image has OpenSSL dev packages:**

```dockerfile
# For Ubuntu/Debian base
RUN apt-get update && apt-get install -y \
    build-essential \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# For Alpine base
RUN apk add --no-cache \
    build-base \
    pkgconfig \
    openssl-dev
```

**Or use the provided Dockerfiles:**
```bash
docker build -f docker/Dockerfile.rust -t infinilm-svc:latest .
```

## Verification

After installation, verify everything works:

```bash
# Check binaries exist
which infini-registry
which infini-router
which infini-babysitter

# Test registry
infini-registry --port 18000 &
sleep 2
curl http://localhost:18000/health
pkill infini-registry
```

## Getting Help

If issues persist:

1. Check the build log for specific error messages
2. Verify all prerequisites are installed
3. Try a clean build:
   ```bash
   cd rust
   cargo clean
   cargo build --release
   ```
4. Check system resources (memory, disk space)
5. Review [QUICKSTART.md](QUICKSTART.md) for detailed installation steps
