#!/usr/bin/env bash
# Install-time defaults for the cache-type-routing-validation case.
#
# This file is sourced by scripts/install.sh when:
#   --deployment-case cache-type-routing-validation
#
# Use it to pin optional installs, branches, and other toggles for reproducible images.

# Make sure /app layout is staged (needed for docker_entrypoint_rust.sh)
SETUP_APP_ROOT="${SETUP_APP_ROOT:-true}"

# Launch components configuration for this deployment case
# Options: "all", "none", "registry", "router", "babysitter", or comma-separated list
#   - "all": Launch registry, router, and babysitter (default for production)
#   - "none": Launch nothing (useful for daily development where services are started manually)
#   - Comma-separated: e.g., "registry,router" or "babysitter"
LAUNCH_COMPONENTS="${LAUNCH_COMPONENTS:-all}"

# Cache type routing validation deployments require python tooling in the image.
INSTALL_PYTHON_DEPS="${INSTALL_PYTHON_DEPS:-true}"

# Optional: enable these if you want the base image to include the python backends too.
# (Leave as-is if you want a minimal SVC-only base image.)
INSTALL_INFINICORE="${INSTALL_INFINICORE:-true}"
INSTALL_INFINILM="${INSTALL_INFINILM:-true}"

# Default refs (override via CLI flags if needed)
INFINICORE_BRANCH="${INFINICORE_BRANCH:-issue/951}"
INFINILM_BRANCH="${INFINILM_BRANCH:-issue/216}"

# InfiniCore must be configured for metax + ccl before building.
# This matches the deployment requirement:
#   python scripts/install.py --metax-gpu=y --ccl=y
# InfiniCore build configuration
# C++ targets (infiniop, infinirt, infiniccl, infinicore_cpp_api) - takes long time, can be cached
INFINICORE_BUILD_CPP="${INFINICORE_BUILD_CPP:-auto}"  # auto|true|false - auto: build if libs don't exist
# Python extension (_infinicore) - quick rebuild, must match Python version
INFINICORE_BUILD_PYTHON="${INFINICORE_BUILD_PYTHON:-auto}"  # auto|true|false - auto: always build
# Command to build C++ targets (runs before Python extension build)
INFINICORE_BUILD_CMD="${INFINICORE_BUILD_CMD:-python3 scripts/install.py --metax-gpu=y --ccl=y}"
