#!/usr/bin/env bash
# Stop all infinilm-metax-deployment-opt containers (master + slave)

set -e

echo "Stopping InfiniLM-SVC infinilm-metax-deployment-opt containers..."

if docker ps -a --format '{{.Names}}' | grep -q "^infinilm-svc-master-opt$"; then
  echo "Stopping infinilm-svc-master-opt..."
  docker stop infinilm-svc-master-opt >/dev/null 2>&1 || true
  echo "Removing infinilm-svc-master-opt..."
  docker rm -f infinilm-svc-master-opt >/dev/null 2>&1 || true
fi

if docker ps -a --format '{{.Names}}' | grep -q "^infinilm-svc-slave-opt$"; then
  echo "Stopping infinilm-svc-slave-opt..."
  docker stop infinilm-svc-slave-opt >/dev/null 2>&1 || true
  echo "Removing infinilm-svc-slave-opt..."
  docker rm -f infinilm-svc-slave-opt >/dev/null 2>&1 || true
fi

echo "All containers stopped and removed"
