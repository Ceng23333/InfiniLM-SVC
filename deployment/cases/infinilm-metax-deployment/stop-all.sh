#!/usr/bin/env bash
# Stop all demo containers

set -e

echo "Stopping InfiniLM-SVC demo containers..."

if docker ps -a --format '{{.Names}}' | grep -q "^infinilm-svc-master$"; then
    echo "Stopping infinilm-svc-master (includes embedding server)..."
    docker stop infinilm-svc-master >/dev/null 2>&1 || true
    echo "Removing infinilm-svc-master..."
    docker rm -f infinilm-svc-master >/dev/null 2>&1 || true
fi

if docker ps -a --format '{{.Names}}' | grep -q "^infinilm-svc-slave$"; then
    echo "Stopping infinilm-svc-slave..."
    docker stop infinilm-svc-slave >/dev/null 2>&1 || true
    echo "Removing infinilm-svc-slave..."
    docker rm -f infinilm-svc-slave >/dev/null 2>&1 || true
fi

# Also stop/remove slave containers with numeric suffixes (slave2, slave3, ...)
for name in $(docker ps -a --format '{{.Names}}' | grep -E '^infinilm-svc-slave[0-9]+$' || true); do
    echo "Stopping ${name}..."
    docker stop "${name}" >/dev/null 2>&1 || true
    echo "Removing ${name}..."
    docker rm -f "${name}" >/dev/null 2>&1 || true
done

echo "✅ All containers stopped and removed"
