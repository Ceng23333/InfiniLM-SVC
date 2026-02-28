#!/usr/bin/env bash
# Install-time defaults for the infinilm-metax-deployment-opt case.
#
# This file is sourced by scripts/install.sh when:
#   --deployment-case infinilm-metax-deployment-opt
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

# Metax deployments commonly require python tooling in the image.
# Override if still at default "auto" value
if [ "${INSTALL_PYTHON_DEPS:-auto}" = "auto" ]; then
    INSTALL_PYTHON_DEPS=true
fi

# Optional: enable these if you want the base image to include the python backends too.
# (Leave as-is if you want a minimal SVC-only base image.)
# Override if still at default "auto" value
if [ "${INSTALL_INFINICORE:-auto}" = "auto" ]; then
    INSTALL_INFINICORE=true
fi
if [ "${INSTALL_INFINILM:-auto}" = "auto" ]; then
    INSTALL_INFINILM=true
fi

# Default refs (override via CLI flags if needed)
INFINICORE_BRANCH="${INFINICORE_BRANCH:-issue/1004}"
INFINILM_BRANCH="${INFINILM_BRANCH:-issue/218}"

# Tag image with branch info (e.g. 1004_216-1 from issue/1004 and issue/216-1)
BRANCH_TAG="${BRANCH_TAG:-${INFINICORE_BRANCH##*/}_${INFINILM_BRANCH##*/}}"
IMAGE_TAG="${IMAGE_TAG:-infinilm-svc:metax-${BRANCH_TAG}}"
DEFAULT_RUNTIME_TAG_FORMAT="${DEFAULT_RUNTIME_TAG_FORMAT:-infinilm-svc:metax-hpcc-${BRANCH_TAG}}"

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
