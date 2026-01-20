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
INSTALL_INFINICORE="true"
INSTALL_INFINILM="true"

# Default refs (override via CLI flags if needed)
INFINICORE_BRANCH="issue/951"
INFINILM_BRANCH="issue/193"
