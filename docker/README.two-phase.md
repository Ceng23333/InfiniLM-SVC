# Phased Build Guide

This guide explains how to use the phased build approach for InfiniLM-SVC, which enables dependency caching and faster debugging iterations.

## Overview

The phased build splits the installation process into:

1. **Phase 1 (Dependencies)**: Install all dependencies requiring network/proxy, download Rust crates, commit intermediate image
2. **Phase 2 (Build)**: Build InfiniLM-SVC, InfiniCore, and InfiniLM from mounted/copied sources (no network needed)

## Benefits

- **Dependency Caching**: Phase 1 dependencies are cached in Docker layers, speeding up rebuilds
- **Faster Iterations**: Phase 2 can run offline and doesn't require network access
- **Reusable Images**: Phase 1 intermediate image can be reused for multiple Phase 2 builds
- **Better Debugging**: Separate phases make it easier to debug dependency vs. build issues

## Scripts

### Phase 1: `install-deps.sh`

Installs all dependencies and caches Rust crates:

```bash
./scripts/install-deps.sh [OPTIONS]
```

**Options:**
- `--skip-rust-install` - Skip Rust installation (assumes Rust is already installed)
- `--deployment-case NAME` - Deployment case preset name

**What it does:**
- Installs system dependencies
- Installs Rust toolchain
- Installs xmake
- Installs Python dependencies
- Downloads Rust crate dependencies (`cargo fetch`) - caches in `~/.cargo`

**What it does NOT do:**
- Clone InfiniCore/InfiniLM repos
- Build binaries

### Phase 2: `install-build.sh`

Builds from local sources (no network needed):

```bash
./scripts/install-build.sh [OPTIONS]
```

**Options:**
- `--skip-build` - Skip building binaries
- `--install-path PATH` - Installation path (default: /usr/local/bin)
- `--build-only` - Only build, don't install
- `--install-infinicore MODE` - auto|true|false
- `--install-infinilm MODE` - auto|true|false
- `--infinicore-src PATH` - **Required** - Path to InfiniCore repo
- `--infinilm-src PATH` - **Required** - Path to InfiniLM repo
- `--deployment-case NAME` - Deployment case preset name

**What it does:**
- Validates prerequisites (Rust, xmake)
- Validates InfiniCore/InfiniLM source directories exist
- Builds Rust binaries (uses cached cargo deps from Phase 1)
- Installs InfiniCore from mounted/copied source
- Installs InfiniLM from mounted/copied source
- Installs binaries and sets up scripts

**Requirements:**
- Rust must be installed (from Phase 1)
- xmake must be installed (from Phase 1)
- InfiniCore/InfiniLM repos must be mounted/copied (will NOT be cloned)

## Docker Usage

### Dockerfiles

There are two Dockerfiles for phased builds:

1. **`Dockerfile.build`**: For building Phase 1 only or both phases together
   - Defines both `deps` and `build` stages
   - Use for: `docker build --target deps` or `docker build --target build` (full build)

2. **`Dockerfile.build-only`**: For building Phase 2 separately using an existing deps image
   - Only defines the `build` stage
   - Use for: `docker build -f docker/Dockerfile.build-only --target build` with `--build-arg DEPS_IMAGE=infinilm-svc:deps`
   - Prevents Docker from rebuilding Phase 1 dependencies

### Build Phase 1 Only

Build and tag the intermediate dependency image:

```bash
docker build --target deps -t infinilm-svc:deps .
```

This image contains all dependencies and cached Rust crates. You can commit this image and reuse it for multiple Phase 2 builds.

### Build Phase 2 from Cached Phase 1

**IMPORTANT**: When building Phase 2 separately, you must use `Dockerfile.build-only` instead of `Dockerfile.build`.

**Why?** `Dockerfile.build` defines both `deps` and `build` stages. Even when using `--target build` with `--build-arg DEPS_IMAGE=infinilm-svc:deps`, Docker will still evaluate and potentially rebuild the `deps` stage. `Dockerfile.build-only` only defines the `build` stage, so it uses the provided `DEPS_IMAGE` directly without rebuilding Phase 1.

Build Phase 2 using the cached Phase 1 image:

```bash
# Use the build-only Dockerfile for Phase 2
docker build -f docker/Dockerfile.build-only \
    --target build \
    --build-arg DEPS_IMAGE=infinilm-svc:deps \
    --build-arg DEPLOYMENT_CASE=my-case \
    -t infinilm-svc:build .
```

**Note:** InfiniCore and InfiniLM should already be in the deps image (cloned during Phase 1). They are located at `/app/../InfiniCore` and `/app/../InfiniLM`. If you need to use different repos, you can pass them via build args, but they must be in the build context or mounted.

### Build Full Image (Both Phases)

Build the complete image:

```bash
docker build --target runtime \
    --build-arg DEPLOYMENT_CASE=my-case \
    --build-arg INFINICORE_SRC=/workspace/InfiniCore \
    --build-arg INFINILM_SRC=/workspace/InfiniLM \
    -t infinilm-svc:latest .
```

### Using the Original install.sh with --phase

You can also use the main install script with the `--phase` argument:

```bash
# In Dockerfile
RUN ./scripts/install.sh --phase=deps
# ... commit intermediate image ...
RUN ./scripts/install.sh --phase=build \
    --infinicore-src /workspace/InfiniCore \
    --infinilm-src /workspace/InfiniLM
```

## Manual Usage (Non-Docker)

### Step 1: Run Phase 1

```bash
./scripts/install-deps.sh --deployment-case my-case
```

This installs all dependencies and caches Rust crates in `~/.cargo`.

### Step 2: Run Phase 2

```bash
./scripts/install-build.sh \
    --deployment-case my-case \
    --infinicore-src /workspace/InfiniCore \
    --infinilm-src /workspace/InfiniLM
```

This builds from local sources using the cached dependencies.

## Using --phase Argument

The main `install.sh` script supports a `--phase` argument for backward compatibility:

```bash
# Phase 1 only
./scripts/install.sh --phase=deps

# Phase 2 only
./scripts/install.sh --phase=build \
    --infinicore-src /workspace/InfiniCore \
    --infinilm-src /workspace/InfiniLM

# Both phases (default behavior)
./scripts/install.sh --phase=all
```

## Cargo Dependency Caching

Phase 1 runs `cargo fetch` to download all Rust crate dependencies without building. This:

- Downloads dependencies to `~/.cargo/registry` and `~/.cargo/git`
- Caches them for Phase 2 builds
- Speeds up Phase 2 builds significantly (no network access needed)

## Validation

Phase 2 validates prerequisites before building:

- **Rust**: Checks for `cargo` and `rustc` commands
- **xmake**: Checks for `xmake` command
- **InfiniCore source**: Validates directory exists and is accessible
- **InfiniLM source**: Validates directory exists and is accessible

If any prerequisite is missing, Phase 2 will exit with a clear error message.

## Troubleshooting

### Phase 2 fails: "Rust is not installed"

**Solution**: Run Phase 1 first to install Rust:
```bash
./scripts/install-deps.sh
```

### Phase 2 fails: "InfiniCore source directory not found"

**Solution**: Provide the source path:
```bash
./scripts/install-build.sh --infinicore-src /path/to/InfiniCore
```

**Note**: In Phase 2, repos are NOT cloned. They must be mounted/copied.

### Phase 2 fails: "xmake is not installed"

**Solution**: Run Phase 1 first to install xmake:
```bash
./scripts/install-deps.sh
```

### Cargo fetch fails in Phase 1

**Solution**: Check network connectivity and proxy settings. Phase 1 requires network access.

## Best Practices

1. **Commit Phase 1 image**: Tag and commit the Phase 1 image for reuse
2. **Reuse intermediate images**: Use `--from` to build Phase 2 from cached Phase 1
3. **Mount repos in Phase 2**: Use bind mounts or COPY to provide InfiniCore/InfiniLM sources
4. **Use deployment cases**: Leverage `--deployment-case` for consistent builds
5. **Cache cargo directory**: In Docker, consider caching `~/.cargo` as a volume

## See Also

- [BUILD.md](../BUILD.md) - General build guide
- [QUICKSTART.md](../QUICKSTART.md) - Quick start guide
- [README.md](../README.md) - Project overview
