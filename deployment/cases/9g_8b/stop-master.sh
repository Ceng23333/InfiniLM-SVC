#!/usr/bin/env bash
# Stop the InfiniLM-SVC Master container (9g_8b case)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOVE=""

# Load .env and install.defaults.sh (same as start-master.sh)
if [ -f "${SCRIPT_DIR}/.env" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/.env"
fi
if [ -f "${SCRIPT_DIR}/install.defaults.sh" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/install.defaults.sh"
fi

while [[ $# -gt 0 ]]; do
  case $1 in
    -r|--remove)
      REMOVE=1
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [-r|--remove]"
      echo "  Stop the master container. Use -r/--remove to also remove it."
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

CONTAINER_NAME="${CONTAINER_NAME:-infinilm-svc-master}"

if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "Container ${CONTAINER_NAME} not found."
  exit 0
fi

if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "Stopping ${CONTAINER_NAME} ..."
  docker stop "${CONTAINER_NAME}"
  echo "Stopped."
else
  echo "Container ${CONTAINER_NAME} is already stopped."
fi

if [ -n "${REMOVE}" ]; then
  echo "Removing ${CONTAINER_NAME} ..."
  docker rm "${CONTAINER_NAME}"
  echo "Removed."
fi
