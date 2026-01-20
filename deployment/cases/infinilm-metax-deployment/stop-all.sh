#!/usr/bin/env bash
# Stop all demo containers

set -e

echo "Stopping InfiniLM-SVC demo containers..."

if docker ps --format '{{.Names}}' | grep -q "infinilm-svc-infinilm-server1"; then
    echo "Stopping infinilm-svc-infinilm-server1..."
    docker stop infinilm-svc-infinilm-server1
    echo "Removing infinilm-svc-infinilm-server1..."
    docker rm infinilm-svc-infinilm-server1
fi

if docker ps --format '{{.Names}}' | grep -q "infinilm-svc-infinilm-server2"; then
    echo "Stopping infinilm-svc-server2..."
    docker stop infinilm-svc-infinilm-server2
    echo "Removing infinilm-svc-infinilm-server2..."
    docker rm infinilm-svc-infinilm-server2
fi

echo "✅ All containers stopped and removed"
