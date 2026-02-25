#!/usr/bin/env bash
# Quick check of container status and recent logs (for size-based, 2paged, or 2vllm master).
# Usage: ./check-container.sh [qwen3-32b|2paged|2vllm]
# With no arg, shows both size-based and 2paged containers (whichever exist).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

SIZE_BASED_CONTAINER="${SIZE_BASED_CONTAINER:-infinilm-svc-master-qwen3-32b}"
PAGED_2_CONTAINER="${PAGED_2_CONTAINER:-infinilm-svc-master-2paged-qwen3-32b}"
VLLM_2_CONTAINER="${VLLM_2_CONTAINER:-infinilm-svc-master-2vllm-qwen3-32b}"

show_one() {
  local name="$1"
  echo "=========================================="
  echo "Container: ${name}"
  echo "=========================================="
  docker ps -a --filter "name=${name}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${name}$"; then
    echo ""
    echo "Last 40 log lines:"
    echo "---"
    docker logs "${name}" --tail 40 2>&1 || true
  else
    echo "(container not found)"
  fi
  echo ""
}

case "${1:-}" in
  qwen3-32b|size-based|sizebased)
    show_one "${SIZE_BASED_CONTAINER}"
    ;;
  2paged|2paged-qwen3-32b)
    show_one "${PAGED_2_CONTAINER}"
    ;;
  2vllm|2vllm-qwen3-32b)
    show_one "${VLLM_2_CONTAINER}"
    ;;
  *)
    show_one "${SIZE_BASED_CONTAINER}"
    show_one "${PAGED_2_CONTAINER}"
    ;;
esac
