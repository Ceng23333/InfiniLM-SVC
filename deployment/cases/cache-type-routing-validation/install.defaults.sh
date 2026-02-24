#!/usr/bin/env bash
# Install-time defaults for the cache-type-routing-validation case.
#
# This file is sourced by scripts/install.sh when:
#   --deployment-case cache-type-routing-validation
#
# Use it to pin optional installs, branches, and other toggles for reproducible images.

# Base image for Docker builds (GPU factory image with HPCC, PyTorch, Python 3.10, Kylin Linux ARM64)
# This is used by build-image.sh when building Docker images
DEFAULT_BASE_IMAGE="${DEFAULT_BASE_IMAGE:-cr.metax-tech.com/public-ai-release-wb/x201/vllm:hpcc2.32.0.11-torch2.4-py310-kylin2309a-arm64}"
BASE_IMAGE="${BASE_IMAGE:-${DEFAULT_BASE_IMAGE}}"

# Docker image tag formats for this deployment case
# These are used by build-image.sh when building Docker images
# Format: <repository>:<prefix>-<deployment-case>[-<suffix>]
# Examples:
#   DEPS_IMAGE_TAG="infinilm-svc:deps-cache-type-routing-validation"
#   IMAGE_TAG="infinilm-svc:build-cache-type-routing-validation"
#   RUNTIME_TAG="infinilm-svc:runtime-cache-type-routing-validation"
DEFAULT_IMAGE_REPO="${DEFAULT_IMAGE_REPO:-infinilm-svc}"
IMAGE_REPO="${IMAGE_REPO:-${DEFAULT_IMAGE_REPO}}"
DEFAULT_DEPS_IMAGE_TAG="${DEFAULT_DEPS_IMAGE_TAG:-${IMAGE_REPO}:deps-cache-type-routing-validation}"
DEFAULT_IMAGE_TAG="${DEFAULT_IMAGE_TAG:-${IMAGE_REPO}:build-cache-type-routing-validation}"
DEFAULT_RUNTIME_TAG_FORMAT="${DEFAULT_RUNTIME_TAG_FORMAT:-${IMAGE_REPO}:runtime-cache-type-routing-validation}"
# These can be overridden via CLI arguments or environment variables
DEPS_IMAGE_TAG="${DEPS_IMAGE_TAG:-${DEFAULT_DEPS_IMAGE_TAG}}"
IMAGE_TAG="${IMAGE_TAG:-${DEFAULT_IMAGE_TAG}}"
# RUNTIME_TAG is auto-generated with timestamp, but can be overridden
# Format: <repo>:runtime-<deployment-case>-<timestamp> or custom
RUNTIME_TAG="${RUNTIME_TAG:-}"

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
INFINILM_BRANCH="${INFINILM_BRANCH:-issue/216-1}"

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
