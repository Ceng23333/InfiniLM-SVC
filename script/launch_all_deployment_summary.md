# Current single-server deployment (legacy `script/launch_all.sh`) — Summary

This document summarizes what the **current** deployment script (`script/launch_all.sh`) does on a **single server**.

## What it launches (fixed order)

`launch_all.sh` orchestrates **4 services** in sequence:

1. **Service Registry** (via `./launch_registry.sh`)
2. **Distributed Router** (via `./launch_router.sh`)
3. **Babysitter (9g8b)** (via `./launch_babysitter_9g8b.sh`)
4. **Babysitter (Qwen)** (via `./launch_babysitter_qwen_rust.sh`)

## Process management + logging

- Each service is started in the background and tracked via a **PID file** under `script/logs/`:
  - `logs/registry.pid`
  - `logs/router.pid`
  - `logs/babysitter_9g8b_8100.pid`
  - `logs/babysitter_qwen_8200.pid`
- It also expects per-service log files under `script/logs/` (e.g. `registry_*.log`, `router_*.log`, `babysitter_*.log`).
- If a PID file exists and the PID is running, the service is treated as **already running** and skipped.

## Health checks / readiness

- Registry readiness: `GET http://localhost:${REGISTRY_PORT}/health`
- Router readiness: `GET http://localhost:${ROUTER_PORT}/health`
- Babysitters are started without blocking on readiness; at the end it performs a **quick** check:
  - 9g8b babysitter health: `GET http://localhost:8101/health`
  - Qwen babysitter health: `GET http://localhost:8201/health`

Timeouts used by the orchestrator:

- Registry wait timeout: `REGISTRY_WAIT_TIMEOUT=60s`
- Router wait timeout: `ROUTER_WAIT_TIMEOUT=60s`
- Babysitter wait timeout: `BABYSITTER_WAIT_TIMEOUT=300s` (used only for process-start checks; model loading can take longer)

## Ports (defaults)

Ports are read from the per-service launch scripts (falling back to defaults):

- Registry: `REGISTRY_PORT` from `launch_registry.sh` (default `18000`)
- Router: `ROUTER_PORT` from `launch_router.sh` (default `8000`)

Babysitter + backend expectations:

- 9g8b service port: `8100`, babysitter health port: `8101`
- Qwen service port: `8200`, babysitter health port: `8201`

At the end, `launch_all.sh` prints curl hints including:

- `curl http://localhost:${ROUTER_PORT}/models` (router aggregated models)
- `curl http://localhost:8100/models` and `curl http://localhost:8200/models` (backend servers behind babysitters)

## Key coupling / assumptions

- `launch_registry.sh` and `launch_router.sh` are **Python-based** launchers (they run `python/service_registry.py` and `python/distributed_router.py`).
- The babysitters are expected to manage / expose a backend that responds to a `/models` (or OpenAI `/v1/models`) endpoint so the router can aggregate models.
- The deployment is **single host only** (all components bind on localhost/host ports; no remote registry/router wiring).
