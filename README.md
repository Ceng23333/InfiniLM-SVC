# InfiniLM-SVC

A distributed service virtualization and control system for InfiniLM, providing centralized service discovery, load balancing, and health monitoring.

## Overview

InfiniLM-SVC implements a distributed architecture with three core components:

- **Service Registry** - Centralized service discovery and health monitoring
- **Distributed Router** - Model-aware load balancer with request proxying
- **Enhanced Babysitter** - Service lifecycle management wrapper

## Features

- ✅ **Model-Aware Routing** - Routes requests to services based on requested model
- ✅ **Service Discovery** - Automatic registration and health monitoring
- ✅ **Load Balancing** - Weighted round-robin across healthy services
- ✅ **Streaming Support** - Full support for Server-Sent Events (SSE)
- ✅ **Health Monitoring** - Automatic health checks and service recovery
- ✅ **Multi-Instance Support** - Deploy multiple service instances easily

## Quick Start

### Rust Version (Recommended)

```bash
# Build binaries
cd rust
cargo build --release --bin infini-registry --bin infini-router --bin infini-babysitter

# Launch all services
cd ..
export BABYSITTER_CONFIGS=("config/babysitter1.toml" "config/babysitter2.toml")
./script/launch_all_rust.sh
```

### Python Version

```bash
# Launch all services
./script/launch_all.sh
```

## Project Structure

```
InfiniLM-SVC/
├── rust/              # Rust implementation (recommended)
│   ├── src/           # Source code
│   └── tests/         # Integration tests
├── python/            # Python implementation
├── script/            # Launch scripts
├── config/            # Configuration files
├── docker/            # Docker files
└── docs/              # Documentation
```

## Documentation

- **[Maintenance Guide](docs/README.md)** - Complete usage and configuration guide
- **[Integration Tests](rust/tests/integration/README.md)** - Testing documentation
- **[Babysitter Guide](rust/src/bin/README.md)** - Babysitter configuration
- **[Distributed Deployment](docs/DISTRIBUTED_DEPLOYMENT_README.md)** - Multi-server deployment

## Requirements

### Rust Version
- Rust 1.70+ (nightly recommended)
- Cargo

### Python Version
- Python 3.8+
- Dependencies: `aiohttp`, `requests`

## CI/CD

The project includes GitHub Actions CI/CD pipeline:
- Automated builds and linting
- Integration tests
- See [`.github/workflows/`](.github/workflows/) for details

## License

[Add your license here]

## Contributing

[Add contribution guidelines here]
