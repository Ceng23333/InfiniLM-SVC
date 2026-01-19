# InfiniLM-SVC Quick Start Guide

This guide will help you build and install InfiniLM-SVC in a base Docker image or on a system.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Installation](#quick-installation)
- [Building in Docker](#building-in-docker)
- [Manual Installation](#manual-installation)
- [Verification](#verification)
- [Next Steps](#next-steps)

## Prerequisites

### System Requirements

- **Rust**: 1.70+ (stable or nightly)
- **Cargo**: Included with Rust
- **Python**: 3.8+ (optional, for Python version)
- **Build Tools**:
  - `curl` or `wget`
  - `bash`
  - `gcc` / `clang` (for Rust compilation)
  - `pkg-config` (for some dependencies)
  - `libssl-dev` / `openssl-devel` (for HTTPS support)

### Base Image Options

InfiniLM-SVC can be installed on various base images:

- **Ubuntu/Debian**: `ubuntu:22.04`, `debian:bullseye`
- **Kylin Linux**: Kylin Linux (Debian/Ubuntu-based, automatically detected)
- **Alpine**: `alpine:latest` (requires additional dependencies)
- **Rust Official**: `rust:1.75-slim` (Rust pre-installed)
- **Python**: `python:3.11-slim` (for Python version)

## Quick Installation

### Using the Install Script

The easiest way to install InfiniLM-SVC:

```bash
# Download and run the install script
curl -fsSL https://raw.githubusercontent.com/your-repo/InfiniLM-SVC/main/scripts/install.sh | bash

# Or clone the repo and run locally
git clone <repository-url>
cd InfiniLM-SVC
./scripts/install.sh
```

### Docker Build

```bash
# Build using the provided Dockerfile
docker build -f docker/Dockerfile.rust -t infinilm-svc:latest .

# Or use the install script in your Dockerfile
FROM ubuntu:22.04
COPY scripts/install.sh /tmp/
RUN /tmp/install.sh
```

## Building in Docker

### Option 1: Multi-Stage Build (Recommended)

Create a `Dockerfile`:

```dockerfile
# Stage 1: Build binaries
FROM rust:1.75-slim AS builder

WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy source code
COPY rust/ ./rust/
COPY Cargo.toml ./rust/

# Build release binaries
WORKDIR /build/rust
RUN cargo build --release --bin infini-registry --bin infini-router --bin infini-babysitter

# Stage 2: Runtime image
FROM ubuntu:22.04

WORKDIR /app

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    bash \
    && rm -rf /var/lib/apt/lists/*

# Copy binaries from builder
COPY --from=builder /build/rust/target/release/infini-registry /usr/local/bin/
COPY --from=builder /build/rust/target/release/infini-router /usr/local/bin/
COPY --from=builder /build/rust/target/release/infini-babysitter /usr/local/bin/

# Copy scripts and configs
COPY script/ ./script/
COPY config/ ./config/
COPY docker/docker_entrypoint_rust.sh ./docker_entrypoint.sh

# Make scripts executable
RUN chmod +x ./script/*.sh ./docker_entrypoint.sh

# Create directories
RUN mkdir -p logs config

# Set entrypoint
ENTRYPOINT ["/bin/bash", "/app/docker_entrypoint.sh"]

# Expose ports
EXPOSE 18000 8000
```

Build and run:

```bash
docker build -t infinilm-svc:latest .
docker run -d \
  --name infinilm-svc \
  -e LAUNCH_COMPONENTS=all \
  -e REGISTRY_PORT=18000 \
  -e ROUTER_PORT=8000 \
  -p 18000:18000 \
  -p 8000:8000 \
  infinilm-svc:latest
```

### Option 2: Using Install Script in Dockerfile

```dockerfile
FROM ubuntu:22.04

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    build-essential \
    pkg-config \
    libssl-dev \
    ca-certificates \
    bash \
    && rm -rf /var/lib/apt/lists/*

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Copy project files
COPY . .

# Run install script
RUN ./scripts/install.sh

# Set entrypoint
ENTRYPOINT ["/bin/bash", "/app/docker/docker_entrypoint_rust.sh"]

EXPOSE 18000 8000
```

## Manual Installation

### Step 1: Install Rust

```bash
# Install Rust using rustup
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

# Verify installation
rustc --version
cargo --version
```

### Step 2: Install System Dependencies

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    pkg-config \
    libssl-dev \
    curl \
    bash
```

**Alpine:**
```bash
apk add --no-cache \
    build-base \
    pkgconfig \
    openssl-dev \
    curl \
    bash
```

**CentOS/RHEL:**
```bash
sudo yum install -y \
    gcc \
    pkgconfig \
    openssl-devel \
    curl \
    bash
```

### Step 3: Build Binaries

```bash
# Clone repository (or use existing)
cd InfiniLM-SVC/rust

# Build release binaries
cargo build --release --bin infini-registry --bin infini-router --bin infini-babysitter

# Binaries will be in: rust/target/release/
```

### Step 4: Install Binaries

```bash
# Option A: Copy to system PATH
sudo cp rust/target/release/infini-* /usr/local/bin/

# Option B: Add to local bin directory
mkdir -p ~/.local/bin
cp rust/target/release/infini-* ~/.local/bin/
export PATH="$HOME/.local/bin:$PATH"
```

### Step 5: Set Up Scripts and Configs

```bash
# Make scripts executable
chmod +x script/*.sh
chmod +x docker/docker_entrypoint_rust.sh

# Create necessary directories
mkdir -p logs config
```

## Verification

### Check Binaries

```bash
# Verify binaries exist and are executable
which infini-registry
which infini-router
which infini-babysitter

# Check versions (if implemented)
infini-registry --version
infini-router --version
infini-babysitter --version
```

### Test Build

```bash
# Quick test: Start registry
infini-registry --port 18000 &
sleep 2
curl http://localhost:18000/health
pkill infini-registry
```

### Docker Test

```bash
# Test Docker image
docker run --rm \
  -e LAUNCH_COMPONENTS=registry \
  -e REGISTRY_PORT=18000 \
  -p 18000:18000 \
  infinilm-svc:latest &

sleep 3
curl http://localhost:18000/health
docker stop $(docker ps -q --filter ancestor=infinilm-svc:latest)
```

## Next Steps

1. **Configure Services**: See [docker/README.md](docker/README.md) for environment configuration
2. **Create Babysitter Configs**: See [rust/src/bin/README.md](rust/src/bin/README.md) for configuration examples
3. **Deploy Multi-Server**: See [docs/DISTRIBUTED_DEPLOYMENT_README.md](docs/DISTRIBUTED_DEPLOYMENT_README.md) for distributed setup
4. **Run Integration Tests**: See [rust/tests/integration/README.md](rust/tests/integration/README.md)

## Troubleshooting

### Rust Installation Issues

```bash
# Update Rust
rustup update

# Check Rust version
rustc --version  # Should be 1.70+

# Clean and rebuild
cd rust
cargo clean
cargo build --release
```

### Build Errors

#### OpenSSL Not Found

This is the most common issue. The build requires OpenSSL development libraries.

```bash
# Ubuntu/Debian/Kylin:
sudo apt-get update
sudo apt-get install libssl-dev pkg-config

# Alpine:
apk add openssl-dev pkgconfig

# CentOS/RHEL:
sudo yum install openssl-devel pkgconfig

# If OpenSSL is in non-standard location:
export OPENSSL_DIR=/path/to/openssl
export PKG_CONFIG_PATH=/path/to/openssl/lib/pkgconfig
```

#### Missing pkg-config

```bash
# Ubuntu/Debian/Kylin:
sudo apt-get install pkg-config

# Alpine:
apk add pkgconfig

# CentOS/RHEL:
sudo yum install pkgconfig
```

#### OS Detection Issues (Kylin Linux, etc.)

The script now automatically detects Kylin Linux and other Debian/Ubuntu-based distributions.
If detection fails, the script will try to use available package managers (apt-get, yum, apk) as fallback.

### Permission Issues

```bash
# Make scripts executable
chmod +x script/*.sh
chmod +x docker/*.sh

# Fix binary permissions
chmod +x rust/target/release/infini-*
```

## Advanced Configuration

### Custom Build Options

```bash
# Build with optimizations
cd rust
RUSTFLAGS="-C target-cpu=native" cargo build --release

# Build specific binary only
cargo build --release --bin infini-registry

# Build with debug symbols
cargo build --release --bin infini-registry --features debug
```

### Cross-Compilation

```bash
# Install cross-compilation target
rustup target add x86_64-unknown-linux-musl

# Build for target
cargo build --release --target x86_64-unknown-linux-musl
```

## Support

For more information:
- **Documentation**: [docs/README.md](docs/README.md)
- **API Reference**: [API_DOCUMENTATION.md](API_DOCUMENTATION.md)
- **Issues**: [GitHub Issues](https://github.com/your-repo/issues)
