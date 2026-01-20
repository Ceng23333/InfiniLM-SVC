#!/usr/bin/env bash
# Install-time defaults for the integration-validation deployment case.
#
# This file is sourced by scripts/install.sh when:
#   --deployment-case integration-validation
#
# Use it to pin optional installs, branches, and other toggles for reproducible images.

# Make sure /app layout is staged (needed for docker_entrypoint_rust.sh)
SETUP_APP_ROOT="${SETUP_APP_ROOT:-true}"

# Demo/integration deployments commonly require python tooling in the image.
INSTALL_PYTHON_DEPS="${INSTALL_PYTHON_DEPS:-true}"

# Optional: enable these if you want the base image to include the python backends too.
# (Leave as-is if you want a minimal SVC-only base image.)
INSTALL_INFINICORE="${INSTALL_INFINICORE:-auto}"
INSTALL_INFINILM="${INSTALL_INFINILM:-auto}"

# Default refs (override via CLI flags if needed)
# INFINICORE_BRANCH="${INFINICORE_BRANCH:-main}"
# INFINILM_BRANCH="${INFINILM_BRANCH:-main}"
