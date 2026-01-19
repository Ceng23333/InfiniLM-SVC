# Troubleshooting Guide

Common issues and solutions for the integration validation demo.

## Container Won't Start

### Issue: Port Already in Use

**Error:**
```
Error: bind: address already in use
```

**Solution:**
```bash
# Check what's using the port
sudo lsof -i :18000
sudo lsof -i :8000

# Stop conflicting services or use different ports
```

### Issue: Container Name Already Exists

**Error:**
```
Error: container name "infinilm-svc-server1" is already taken
```

**Solution:**
```bash
# Remove existing container
docker rm -f infinilm-svc-server1
# or
docker rm -f infinilm-svc-server2
```

## Services Not Registering

### Issue: Server 2 Can't Connect to Server 1

**Symptoms:**
- Server 2 starts but babysitters don't register
- Logs show connection errors

**Solution:**
1. Verify Server 1 is running:
   ```bash
   docker ps | grep infinilm-svc-server1
   curl http://<SERVER1_IP>:18000/health
   ```

2. Check network connectivity:
   ```bash
   # From Server 2
   ping <SERVER1_IP>
   curl -v http://<SERVER1_IP>:18000/health
   ```

3. Verify firewall rules:
   ```bash
   # Allow ports on Server 1
   sudo ufw allow 18000/tcp
   sudo ufw allow 8000/tcp
   ```

4. Check Docker network:
   ```bash
   # If using Docker network, ensure containers are on same network
   docker network ls
   ```

### Issue: Wrong Registry URL

**Symptoms:**
- Services register but with wrong host/port
- Services show as unhealthy

**Solution:**
- Verify `REGISTRY_URL` in `start-server2.sh` matches Server 1 IP
- Check that `BABYSITTER_REGISTRY_URL` is set correctly in docker run command

## Model Aggregation Fails

### Issue: Models Not Showing in Router

**Symptoms:**
- `/models` endpoint returns empty or missing models
- Only some models appear

**Solution:**
1. Check all services are registered:
   ```bash
   curl http://<SERVER1_IP>:18000/services | jq '.services[] | {name, models: .metadata.models}'
   ```

2. Verify router is syncing with registry:
   ```bash
   curl http://<SERVER1_IP>:8000/services | jq '.services[] | .name'
   ```

3. Wait longer (registry sync may take time):
   ```bash
   sleep 30
   curl http://<SERVER1_IP>:8000/models
   ```

4. Check router logs:
   ```bash
   docker logs infinilm-svc-server1 | grep -i "registry\|sync\|model"
   ```

## Chat Completions Fail

### Issue: 404 or Service Not Found

**Symptoms:**
- Chat completions return 404
- Router can't find service for model

**Solution:**
1. Verify model exists:
   ```bash
   curl http://<SERVER1_IP>:8000/models
   ```

2. Check service health:
   ```bash
   curl http://<SERVER1_IP>:18000/services | jq '.services[] | {name, status, healthy}'
   ```

3. Verify model is in service metadata:
   ```bash
   curl http://<SERVER1_IP>:18000/services | jq '.services[] | {name, models: .metadata.models}'
   ```

### Issue: Wrong Service Responding

**Symptoms:**
- Requests for model-1 go to model-2 service or vice versa

**Solution:**
1. Check service metadata:
   ```bash
   curl http://<SERVER1_IP>:18000/services | jq '.services[] | {name, models: .metadata.models}'
   ```

2. Verify babysitter configs have correct models:
   ```bash
   cat config/babysitter-a.toml | grep models
   cat config/babysitter-b.toml | grep models
   ```

3. Restart services with correct configs

## Logs and Debugging

### View Logs

```bash
# Server 1 logs
docker logs -f infinilm-svc-server1

# Server 2 logs
docker logs -f infinilm-svc-server2

# Filter for specific component
docker logs infinilm-svc-server1 | grep -i "registry"
docker logs infinilm-svc-server1 | grep -i "router"
docker logs infinilm-svc-server1 | grep -i "babysitter"
```

### Check Service Status

```bash
# Registry services
curl http://<SERVER1_IP>:18000/services | jq '.'

# Router services
curl http://<SERVER1_IP>:8000/services | jq '.'

# Router models
curl http://<SERVER1_IP>:8000/models | jq '.'

# Router stats
curl http://<SERVER1_IP>:8000/stats | jq '.'
```

### Test Individual Services

```bash
# Test registry
curl http://<SERVER1_IP>:18000/health

# Test router
curl http://<SERVER1_IP>:8000/health

# Test babysitter (if accessible)
curl http://<SERVER1_IP>:8101/health  # Babysitter A
curl http://<SERVER1_IP>:8201/health  # Babysitter B
```

## Common Configuration Issues

### Issue: Mock Service Not Starting

**Symptoms:**
- Babysitter starts but mock service doesn't
- Logs show "command not found" or Python errors

**Solution:**
1. Verify Python 3 is available in container:
   ```bash
   docker exec infinilm-svc-server1 python3 --version
   ```

2. Check mock_service.py is mounted:
   ```bash
   docker exec infinilm-svc-server1 ls -la /app/mock_service.py
   ```

3. Verify aiohttp is installed (if needed):
   ```bash
   docker exec infinilm-svc-server1 python3 -m pip install aiohttp
   ```

### Issue: Config Files Not Found

**Symptoms:**
- Babysitter fails to start
- "Config file not found" errors

**Solution:**
1. Verify config files are mounted:
   ```bash
   docker exec infinilm-svc-server1 ls -la /app/config/
   ```

2. Check volume mount in docker run command:
   ```bash
   # Should include:
   -v $(pwd)/config:/app/config:ro
   ```

## Network Issues

### Issue: Can't Access Services from Outside

**Solution:**
1. Verify port mappings:
   ```bash
   docker ps | grep infinilm-svc
   # Should show port mappings like 18000:18000
   ```

2. Check firewall:
   ```bash
   sudo ufw status
   sudo ufw allow 18000/tcp
   sudo ufw allow 8000/tcp
   ```

3. Use correct IP:
   - Use public IP for remote access
   - Use localhost/127.0.0.1 for local access
   - Use container IP for Docker network access

## Clean Restart

If everything is broken, do a clean restart:

```bash
# Stop and remove all containers
./stop-all.sh

# Or manually:
docker stop infinilm-svc-server1 infinilm-svc-server2
docker rm infinilm-svc-server1 infinilm-svc-server2

# Restart Server 1
./start-server1.sh <SERVER1_IP>

# Wait for Server 1 to be ready
sleep 15

# Restart Server 2
./start-server2.sh <SERVER1_IP> <SERVER2_IP>

# Wait and validate
sleep 15
./validate.sh <SERVER1_IP>
```

## Getting Help

If issues persist:

1. Collect logs:
   ```bash
   docker logs infinilm-svc-server1 > server1.log
   docker logs infinilm-svc-server2 > server2.log
   ```

2. Check service status:
   ```bash
   curl http://<SERVER1_IP>:18000/services > registry-services.json
   curl http://<SERVER1_IP>:8000/services > router-services.json
   ```

3. Verify configuration:
   ```bash
   cat config/babysitter-*.toml
   ```

4. Review [README.md](README.md) for setup instructions
