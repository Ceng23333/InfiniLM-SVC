#!/usr/bin/env bash
# Start Single Instance: Registry, Router, and only master-9g_8b_thinking instance
# This is a convenience wrapper for start-master.sh with SINGLE_INSTANCE=true

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set SINGLE_INSTANCE flag and call start-master.sh
export SINGLE_INSTANCE=true
exec "${SCRIPT_DIR}/start-master.sh" "$@"
