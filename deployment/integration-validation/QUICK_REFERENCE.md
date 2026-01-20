# Quick Reference

## Architecture

```
Server 1 (Control):
  Registry:18000  Router:8000
  Babysitter A:8100 → Model 1
  Babysitter B:8200 → Model 2

Server 2 (Worker):
  Babysitter C:8100 → Model 1 (→ Server 1 Registry)
  Babysitter D:8200 → Model 2 (→ Server 1 Registry)
```

## Quick Commands

### Start Server 1
```bash
./start-server1.sh <SERVER1_IP>
```

### Start Server 2
```bash
./start-server2.sh <SERVER1_IP> <SERVER2_IP>
```

### Validate
```bash
./validate.sh <SERVER1_IP>
```

### Stop All
```bash
./stop-all.sh
```

### View Logs
```bash
docker logs -f infinilm-svc-server1
docker logs -f infinilm-svc-server2
```

## Endpoints

### Server 1
- Registry: `http://<SERVER1_IP>:18000`
- Router: `http://<SERVER1_IP>:8000`
- Babysitter A: `http://<SERVER1_IP>:8101`
- Babysitter B: `http://<SERVER1_IP>:8201`

### Server 2
- Babysitter C: `http://<SERVER2_IP>:8101`
- Babysitter D: `http://<SERVER2_IP>:8201`

## Test Commands

### Check Registry
```bash
curl http://<SERVER1_IP>:18000/health
curl http://<SERVER1_IP>:18000/services | jq '.'
```

### Check Router
```bash
curl http://<SERVER1_IP>:8000/health
curl http://<SERVER1_IP>:8000/models | jq '.'
curl http://<SERVER1_IP>:8000/services | jq '.'
```

### Test Chat Completions
```bash
# Model 1
curl -X POST http://<SERVER1_IP>:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "model-1", "messages": [{"role": "user", "content": "Hello"}]}'

# Model 2
curl -X POST http://<SERVER1_IP>:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "model-2", "messages": [{"role": "user", "content": "Hello"}]}'
```

## Ports

| Component | Port | Description |
|-----------|------|-------------|
| Registry | 18000 | Service registry |
| Router | 8000 | Load balancer/router |
| Babysitter A | 8100/8101 | Service port / Babysitter port |
| Babysitter B | 8200/8201 | Service port / Babysitter port |
| Babysitter C | 8100/8101 | Service port / Babysitter port |
| Babysitter D | 8200/8201 | Service port / Babysitter port |

## Environment Variables

### Server 1
```bash
LAUNCH_COMPONENTS=all
REGISTRY_PORT=18000
ROUTER_PORT=8000
BABYSITTER_CONFIGS="config/babysitter-a.toml config/babysitter-b.toml"
```

### Server 2
```bash
LAUNCH_COMPONENTS=babysitter
REGISTRY_URL=http://<SERVER1_IP>:18000
ROUTER_URL=http://<SERVER1_IP>:8000
BABYSITTER_REGISTRY_URL=http://<SERVER1_IP>:18000
BABYSITTER_ROUTER_URL=http://<SERVER1_IP>:8000
BABYSITTER_CONFIGS="config/babysitter-c.toml config/babysitter-d.toml"
```

## Validation Checklist

- [ ] Server 1 registry healthy
- [ ] Server 1 router healthy
- [ ] Server 2 can connect to Server 1
- [ ] All 4 babysitters registered
- [ ] Both models in aggregation
- [ ] Model 1 requests work
- [ ] Model 2 requests work
- [ ] Load balancing works
- [ ] Logs show correct routing

## Files

- `config/babysitter-*.toml` - Babysitter configurations
- `mock_service.py` - Mock service implementation
- `start-server1.sh` - Start Server 1
- `start-server2.sh` - Start Server 2
- `validate.sh` - Validation script
- `stop-all.sh` - Cleanup script
