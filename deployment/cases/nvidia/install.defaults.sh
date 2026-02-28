#!/usr/bin/env bash
# Install-time defaults for the nvidia case.
#
# This file is sourced by scripts/install.sh when:
#   --deployment-case nvidia
#
# Use it to pin optional installs, branches, and other toggles for reproducible images.
# Base image: nvcr.io/nvidia/pytorch:25.12-py3 (NVIDIA CUDA, no Metax/HPCC)

# Make sure /app layout is staged (needed for docker_entrypoint_rust.sh)
SETUP_APP_ROOT="${SETUP_APP_ROOT:-true}"

# Launch components configuration for this deployment case
# Options: "all", "none", "registry", "router", "babysitter", or comma-separated list
LAUNCH_COMPONENTS="${LAUNCH_COMPONENTS:-all}"

# NVIDIA deployments require python tooling in the image
if [ "${INSTALL_PYTHON_DEPS:-auto}" = "auto" ]; then
    INSTALL_PYTHON_DEPS=true
fi

# Enable InfiniCore and InfiniLM (required for InfiniLM inference_server with --nvidia)
if [ "${INSTALL_INFINICORE:-auto}" = "auto" ]; then
    INSTALL_INFINICORE=true
fi
if [ "${INSTALL_INFINILM:-auto}" = "auto" ]; then
    INSTALL_INFINILM=true
fi

# Default refs (override via CLI flags if needed)
INFINICORE_BRANCH="${INFINICORE_BRANCH:-issue/1032}"
INFINILM_BRANCH="${INFINILM_BRANCH:-issue/245}"

# InfiniCore must be configured for NVIDIA GPU (not Metax)
#   python scripts/install.py --nv-gpu=y
INFINICORE_BUILD_CPP="${INFINICORE_BUILD_CPP:-auto}"
INFINICORE_BUILD_PYTHON="${INFINICORE_BUILD_PYTHON:-auto}"
INFINICORE_BUILD_CMD="${INFINICORE_BUILD_CMD:-python3 scripts/install.py --nv-gpu=y --graph=y}"
