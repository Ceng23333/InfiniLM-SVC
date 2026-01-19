# InfiniLM-SVC Build Guide

Quick reference for building InfiniLM-SVC in various environments.

## Quick Build Commands

### Using Install Script (Recommended)

```bash
# Full installation
./scripts/install.sh

# Build only (don't install)
./scripts/install.sh --build-only

# Skip Rust installation (if Rust already installed)
./scripts/install.sh --skip-rust-install

# Custom install path
./scripts/install.sh --install-path ~/.local/bin
```

### Manual Build

```bash
# Install Rust (if needed)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

# Build binaries
cd rust
cargo build --release --bin infini-registry --bin infini-router --bin infini-babysitter

# Binaries will be in: rust/target/release/
```

### Docker Build

```bash
# Multi-stage build (recommended - smaller image)
docker build -f docker/Dockerfile.rust -t infinilm-svc:latest .

# Using install script
docker build -f docker/Dockerfile.install-script -t infinilm-svc:latest .
```

## Build Options

### Release Build (Default)

```bash
cargo build --release --bin infini-registry --bin infini-router --bin infini-babysitter
```

### Debug Build

```bash
cargo build --bin infini-registry --bin infini-router --bin infini-babysitter
```

### Optimized Build

```bash
RUSTFLAGS="-C target-cpu=native" cargo build --release \
    --bin infini-registry --bin infini-router --bin infini-babysitter
```

### Build Single Binary

```bash
cargo build --release --bin infini-registry
```

## System Requirements

### Minimum Requirements

- **Rust**: 1.70+
- **Cargo**: Included with Rust
- **Build Tools**: gcc/clang, pkg-config, libssl-dev

### Ubuntu/Debian

```bash
sudo apt-get install -y \
    build-essential \
    pkg-config \
    libssl-dev \
    curl
```

### Alpine

```bash
apk add --no-cache \
    build-base \
    pkgconfig \
    openssl-dev \
    curl
```

### CentOS/RHEL

```bash
sudo yum install -y \
    gcc \
    pkgconfig \
    openssl-devel \
    curl
```

## Build Time

Typical build times on modern hardware:
- **First build**: 5-15 minutes (compiling dependencies)
- **Incremental build**: 1-3 minutes (code changes only)
- **Clean rebuild**: 3-10 minutes

## Output Location

Binaries are built to:
```
rust/target/release/
├── infini-registry
├── infini-router
└── infini-babysitter
```

## Verification

```bash
# Check binaries exist
ls -lh rust/target/release/infini-*

# Test registry
./rust/target/release/infini-registry --port 18000 &
sleep 2
curl http://localhost:18000/health
pkill infini-registry
```

## Troubleshooting

### Build Fails with OpenSSL Error

```bash
# Ubuntu/Debian
sudo apt-get install libssl-dev

# Alpine
apk add openssl-dev

# CentOS/RHEL
sudo yum install openssl-devel
```

### Build Fails with pkg-config Error

```bash
# Ubuntu/Debian
sudo apt-get install pkg-config

# Alpine
apk add pkgconfig

# CentOS/RHEL
sudo yum install pkgconfig
```

### Out of Memory During Build

```bash
# Reduce parallelism
CARGO_BUILD_JOBS=2 cargo build --release
```

### Clean Build

```bash
cd rust
cargo clean
cargo build --release
```

## See Also

- [QUICKSTART.md](QUICKSTART.md) - Complete installation guide
- [docker/README.md](docker/README.md) - Docker deployment guide
- [README.md](README.md) - Project overview
