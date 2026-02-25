#!/usr/bin/env bash
# Display or offload logs from infinilm-metax-deployment-opt containers by prefix
#
# Usage:
#   ./logs.sh display [PREFIX] [--follow|-f]   # Show logs matching PREFIX
#   ./logs.sh offload [PREFIX] [OUTPUT_DIR]    # Copy logs matching PREFIX to host
#
# PREFIX selects which logs. Container inferred from prefix (slave* -> slave, else master).
#   docker              - Container stdout/stderr
#   registry            - Registry log
#   router              - Router log
#   babysitter_master-* - e.g. babysitter_master-embeddings, babysitter_master-9g_8b_thinking
#   babysitter_slave-*  - e.g. babysitter_slave-static-qwen3-32b
#   embeddings_server   - Embedding server log
#   (empty)             - All logs
#
# Examples:
#   ./logs.sh display                          # All (docker logs)
#   ./logs.sh display docker -f                # Follow docker stdout
#   ./logs.sh display babysitter_master-embeddings -f
#   ./logs.sh offload babysitter_master-embeddings /tmp/emb-logs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load .env if present
if [ -f "${SCRIPT_DIR}/.env" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/.env"
fi

CONTAINER_MASTER="${CONTAINER_NAME:-infinilm-svc-master-opt}"
CONTAINER_SLAVE="${CONTAINER_NAME_SLAVE:-infinilm-svc-slave-opt}"

get_container_for_prefix() {
  local prefix="$1"
  if [[ "$prefix" == *slave* ]]; then
    echo "${CONTAINER_SLAVE}"
  else
    echo "${CONTAINER_MASTER}"
  fi
}

container_exists() {
  docker ps -a --format '{{.Names}}' | grep -q "^${1}$"
}

usage() {
  cat <<EOF
Usage: $0 <display|offload> [PREFIX] [OPTIONS]

Commands:
  display [PREFIX] [--follow|-f]   Display logs matching PREFIX (default: docker)
  offload [PREFIX] [OUTPUT_DIR]    Copy logs matching PREFIX to host

PREFIX (container inferred: slave* -> slave, else master):
  docker                    Container stdout/stderr
  registry                  Registry log
  router                    Router log
  babysitter_master-embeddings
  babysitter_master-9g_8b_thinking
  babysitter_master-qwen3-32b-paged
  babysitter_slave-static-qwen3-32b
  babysitter_slave-static-qwen3-32b-2
  embeddings_server         Embedding server log
  (empty)                   All logs

Examples:
  $0 display docker -f
  $0 display babysitter_master-embeddings --follow
  $0 offload babysitter_master-embeddings /tmp/emb
  $0 offload                              # All logs to ./logs-<timestamp>
EOF
  exit 1
}

cmd_display() {
  local prefix="docker"
  local follow=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --follow|-f) follow="1"; shift ;;
      *)
        if [ -n "$1" ] && [[ "$1" != -* ]]; then
          prefix="$1"
        fi
        shift
        ;;
    esac
  done

  local container
  container="$(get_container_for_prefix "$prefix")"
  if ! container_exists "$container"; then
    echo "Error: Container $container not found"
    exit 1
  fi

  if [ "$prefix" = "docker" ] || [ -z "$prefix" ]; then
    if [ -n "$follow" ]; then
      docker logs -f "$container" 2>&1
    else
      docker logs "$container" 2>&1
    fi
    return
  fi

  # File-based log(s)
  local files
  if [ -z "$prefix" ]; then
    files="$(docker exec "$container" ls /app/logs/*.log 2>/dev/null) $(docker exec "$container" sh -c 'ls /app/embeddings_server_*.log 2>/dev/null')"
  else
    case "$prefix" in
      registry) files=$(docker exec "$container" ls /app/logs/registry_*.log 2>/dev/null) ;;
      router)   files=$(docker exec "$container" ls /app/logs/router_*.log 2>/dev/null) ;;
      embeddings_server)
        files=$(docker exec "$container" sh -c 'ls /app/embeddings_server_*.log 2>/dev/null')
        ;;
      babysitter_master-*|babysitter_slave-*)
        files=$(docker exec "$container" sh -c "ls /app/logs/${prefix}_*.log 2>/dev/null || ls /app/logs/${prefix}*.log 2>/dev/null")
        ;;
      *)
        files=$(docker exec "$container" sh -c "ls /app/logs/${prefix}*.log 2>/dev/null; ls /app/${prefix}*.log 2>/dev/null")
        ;;
    esac
  fi

  if [ -z "$files" ]; then
    echo "Error: No logs found for prefix '$prefix' in $container"
    exit 1
  fi

  for f in $files; do
    [ -z "$f" ] && continue
    if [ -n "$follow" ]; then
      docker exec -it "$container" tail -f "$f" 2>/dev/null
      break
    else
      docker exec "$container" cat "$f" 2>/dev/null
    fi
  done
}

cmd_offload() {
  local prefix=""
  local output_dir=""
  while [ $# -gt 0 ]; do
    if [ -n "$1" ] && [[ "$1" != -* ]]; then
      if [ -z "$prefix" ]; then
        prefix="$1"
      else
        output_dir="$1"
      fi
    fi
    shift
  done

  local container
  container="$(get_container_for_prefix "$prefix")"
  if ! container_exists "$container"; then
    echo "Error: Container $container not found"
    exit 1
  fi

  if [ -z "$output_dir" ]; then
    local name="${prefix:-all}"
    name=$(echo "$name" | tr '/' '_')
    output_dir="${SCRIPT_DIR}/logs-${name}-$(date +%Y%m%d_%H%M%S)"
  fi

  mkdir -p "$output_dir"
  echo "Offloading logs from $container (prefix=${prefix:-all}) to $output_dir ..."

  local count=0

  # Docker stdout
  if [ -z "$prefix" ] || [ "$prefix" = "docker" ]; then
    docker logs "$container" 2>&1 > "${output_dir}/docker.log" || true
    echo "  - docker.log"
    count=$((count + 1))
  fi

  # /app/logs/ files
  if [ -z "$prefix" ]; then
    mkdir -p "${output_dir}/app_logs"
    docker cp "${container}:/app/logs/." "${output_dir}/app_logs/" 2>/dev/null || true
    for f in "${output_dir}"/app_logs/*.log; do
      [ -f "$f" ] && echo "  - app_logs/$(basename "$f")" && count=$((count + 1))
    done 2>/dev/null || true
  else
    case "$prefix" in
      registry)
        for f in $(docker exec "$container" ls /app/logs/registry_*.log 2>/dev/null); do
          [ -z "$f" ] && continue
          docker cp "${container}:${f}" "${output_dir}/$(basename "$f")" 2>/dev/null && echo "  - $(basename "$f")" && count=$((count + 1))
        done
        ;;
      router)
        for f in $(docker exec "$container" ls /app/logs/router_*.log 2>/dev/null); do
          [ -z "$f" ] && continue
          docker cp "${container}:${f}" "${output_dir}/$(basename "$f")" 2>/dev/null && echo "  - $(basename "$f")" && count=$((count + 1))
        done
        ;;
      babysitter_*)
        for f in $(docker exec "$container" sh -c "ls /app/logs/${prefix}*.log 2>/dev/null"); do
          [ -z "$f" ] && continue
          docker cp "${container}:${f}" "${output_dir}/$(basename "$f")" 2>/dev/null && echo "  - $(basename "$f")" && count=$((count + 1))
        done
        ;;
      *)
        for f in $(docker exec "$container" sh -c "ls /app/logs/${prefix}*.log 2>/dev/null"); do
          [ -z "$f" ] && continue
          docker cp "${container}:${f}" "${output_dir}/$(basename "$f")" 2>/dev/null && echo "  - $(basename "$f")" && count=$((count + 1))
        done
        ;;
    esac
  fi

  # Embeddings server logs
  if [ -z "$prefix" ] || [ "$prefix" = "embeddings_server" ]; then
    for f in $(docker exec "$container" sh -c 'ls /app/embeddings_server_*.log 2>/dev/null'); do
      [ -z "$f" ] && continue
      mkdir -p "${output_dir}/embed_logs"
      docker cp "${container}:${f}" "${output_dir}/embed_logs/$(basename "$f")" 2>/dev/null && echo "  - embed_logs/$(basename "$f")" && count=$((count + 1))
    done
  fi

  if [ $count -eq 0 ] && [ -n "$prefix" ] && [ "$prefix" != "docker" ]; then
    echo "Error: No logs found for prefix '$prefix'"
    exit 1
  fi

  echo ""
  echo "Logs saved to: $output_dir"
}

# Main
if [ $# -lt 1 ]; then
  usage
fi

CMD="$1"
shift || true

case "$CMD" in
  display)
    cmd_display "$@"
    ;;
  offload)
    cmd_offload "$@"
    ;;
  -h|--help)
    usage
    ;;
  *)
    echo "Error: Unknown command '$CMD'"
    usage
    ;;
esac
