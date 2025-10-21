# InfiniLM-SVC Maintenance Guide

This document provides comprehensive instructions for maintaining and operating the InfiniLM Service Virtualization and Control (SVC) system. The system implements a distributed architecture with centralized service discovery and load balancing.

## Architecture Overview

The InfiniLM-SVC system consists of three main components deployed across local and remote servers:

```
┌─────────────────────────────────────────────────────────────────┐
│                        Local Server                             │
│  ┌─────────────────┐    ┌─────────────────┐                    │
│  │ Service Registry│    │ Distributed     │                    │
│  │ (Port 8081)     │    │ Router          │                    │
│  │                 │    │ (Port 8080)     │                    │
│  └─────────────────┘    └─────────────────┘                    │
└─────────────────────────────────────────────────────────────────┘
                                │
                                │ Service Discovery & Routing
                                │
┌─────────────────────────────────────────────────────────────────┐
│                    Local & Remote Servers                       │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────┐ │
│  │ Enhanced        │    │ Enhanced        │    │ Enhanced    │ │
│  │ Babysitter 1    │    │ Babysitter 2    │    │ Babysitter N│ │
│  │ + xtask         │    │ + xtask         │    │ + xtask     │ │
│  │ (Port 5002/5003)│    │ (Port 5004/5005)│    │ (Port 5xxx) │ │
│  └─────────────────┘    └─────────────────┘    └─────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Component Roles

1. **Service Registry** (Local Server)
   - Centralized service discovery and health monitoring
   - Manages service metadata and routing information
   - Provides REST API for service management

2. **Distributed Router** (Local Server)
   - Load balancer that routes OpenAI API requests to healthy services
   - Only routes to services with `type: "openai-api"` (xtask instances)
   - Supports both streaming and non-streaming responses

3. **Enhanced Babysitter** (Local & Remote Servers)
   - Service management wrapper for InfiniLM-Rust services
   - Health checker and interaction wrapper for xtask
   - Registers both itself and xtask in the registry
   - **Does NOT proxy OpenAI requests** (architectural separation)

4. **xtask** (Local & Remote Servers)
   - Provides OpenAI API interface (`/chat/completions`, `/models`)
   - Registered separately with `type: "openai-api"`
   - Receives requests directly from router

## System Maintenance

### 1. Service Registry Management

#### Starting the Registry
```bash
cd /root/zenghua/repos/InfiniLM-SVC
source /root/miniconda3/etc/profile.d/conda.sh
conda activate infinilm-distributed
python3 service_registry.py --port 8081
```

#### Registry Health Check
```bash
curl http://localhost:8081/health
```

#### List Registered Services
```bash
curl http://localhost:8081/services
```

#### Registry Statistics
```bash
curl http://localhost:8081/stats
```

### 2. Distributed Router Management

#### Starting the Router
```bash
cd /root/zenghua/repos/InfiniLM-SVC
source /root/miniconda3/etc/profile.d/conda.sh
conda activate infinilm-distributed
python3 distributed_router.py --router-port 8080 --registry-url http://localhost:8081
```

#### Router Health Check
```bash
curl http://localhost:8080/health
```

#### Router Statistics
```bash
curl http://localhost:8080/stats
```

#### Test Router Functionality
```bash
# Test models endpoint
curl http://localhost:8080/models

# Test chat completions (non-streaming)
curl -X POST http://localhost:8080/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "Qwen3-32B", "messages": [{"role": "user", "content": "Hello"}]}'
```

### 3. Service Instance Management

#### Starting Enhanced Babysitter
```bash
source /root/miniconda3/etc/profile.d/conda.sh
conda activate infinilm-distributed

# Generate service configuration
cd /root/zenghua/repos/InfiniLM-SVC
python3 render_service_config.py \
  --config test_services.json \
  --output service_generated.toml

# Start enhanced babysitter
cd /root/zenghua/repos/InfiniLM-Rust
python3 enhanced_babysitter.py service_generated.toml \
  --port 5002 \
  --name real-service \
  --registry http://localhost:8081 \
  --router http://localhost:8080 \
  --host localhost
```

#### Service Health Checks
```bash
# Check babysitter health
curl http://localhost:5002/health

# Check xtask health (via babysitter)
curl http://localhost:5002/models

# Check xtask directly
curl http://localhost:5003/health
```

### 4. Network Status

#### Firewall Configuration
The system requires specific ports to be open for proper operation. Use `firewall-cmd` to manage firewall rules:

```bash
# List currently open ports
firewall-cmd --list-ports

# Add required ports for InfiniLM services
firewall-cmd --permanent --add-port=8080/tcp  # Router service
firewall-cmd --permanent --add-port=8081/tcp  # Registry service
firewall-cmd --permanent --add-port=5002/tcp  # Babysitter service
firewall-cmd --permanent --add-port=5003/tcp  # Main service (xtask)

# Reload firewall rules
firewall-cmd --reload

# Verify ports are open
firewall-cmd --list-ports
```

### 4. Configuration Management

#### Service Configuration Template
The system uses Jinja2-like templates for generating service configurations:

**Template Location:** `templates/service.toml.template`
**Configuration Source:** `deployment_configs/test_services.json`

#### Generating Service Configuration
```bash
python3 render_service_config.py \
  --config deployment_configs/test_services.json \
  --output service_generated.toml
```

#### Example Configuration (test_services.json)
```json
{
  "services": [
    {
      "name": "Qwen3-32B",
      "model": {
        "path": "/root/zenghua/Qwen3-F16.gguf",
        "max_tokens": 2048,
        "temperature": 0.7,
        "top_p": 0.9,
        "top_k": 40,
        "repetition_penalty": 1.1,
        "think": false,
        "max_sessions": 100
      },
      "gpu": {
        "devices": [4, 5, 6, 7]
      }
    }
  ]
}
```

## Monitoring and Troubleshooting

### 1. System Validation

#### Run Complete Validation Pipeline
```bash
cd /root/zenghua/repos/InfiniLM-SVC
source /root/miniconda3/etc/profile.d/conda.sh
conda activate infinilm-distributed
python3 validate_integration.py
```

The validation pipeline tests:
1. Registry startup and health
2. Router startup and health
3. Mock service startup and registration
4. Real service (babysitter + xtask) startup
5. Router integration with round-robin testing
6. Service deregistration and cleanup

#### Round-Robin Pattern Testing
The validation includes a specific round-robin test pattern:
- **Pattern:** [non-stream, non-stream, stream, stream]
- **Expected:** 1st and 3rd to real service, 2nd and 4th to mock service
- **Purpose:** Verify load balancing works correctly across services

### 2. Log Management

#### Log Locations
- **Registry:** `logs/service_registry.log`
- **Router:** `logs/distributed_router.log`
- **Babysitter:** `enhanced_babysitter_YYYYMMDD_HHMMSS.log`
- **Validation:** Console output with detailed step-by-step results

#### Log Monitoring
```bash
# Monitor registry logs
tail -f logs/service_registry.log

# Monitor router logs
tail -f logs/distributed_router.log

# Monitor babysitter logs
tail -f enhanced_babysitter_*.log
```

### 3. Common Issues and Solutions

#### Issue: Router Returns 503 "No OpenAI API services available"
**Cause:** No services with `type: "openai-api"` are registered or healthy
**Solution:**
1. Check registry: `curl http://localhost:8081/services`
2. Verify xtask services are registered with correct type
3. Check service health: `curl http://localhost:5003/health`

#### Issue: Streaming Responses Fail
**Cause:** Router not properly handling Server-Sent Events (SSE)
**Solution:**
1. Verify router is updated with streaming support
2. Check that router properly forwards chunked responses
3. Test with non-streaming first, then streaming

#### Issue: Service Registration Fails
**Cause:** Registry not running or network connectivity issues
**Solution:**
1. Check registry health: `curl http://localhost:8081/health`
2. Verify network connectivity between services
3. Check service configuration and metadata

#### Issue: Model Loading Fails
**Cause:** Incorrect model path or insufficient GPU memory
**Solution:**
1. Verify model file exists: `ls -la /root/zenghua/Qwen3-F16.gguf`
2. Check GPU availability: `ht-smi`
3. Update configuration with correct model path

### 4. Performance Monitoring

#### Service Statistics
```bash
# Registry statistics
curl http://localhost:8081/stats

# Router statistics
curl http://localhost:8080/stats

# Service-specific statistics
curl http://localhost:8080/services
```

#### Health Monitoring
```bash
# Check all service health
curl http://localhost:8081/services?healthy=true

# Monitor service response times
curl http://localhost:8080/stats | jq '.services[].response_time'
```

## Deployment Procedures

### 1. Initial System Setup

1. **Start Registry**
   ```bash
   python3 service_registry.py --port 8081
   ```

2. **Start Router**
   ```bash
   python3 distributed_router.py --router-port 8080 --registry-url http://localhost:8081
   ```

3. **Deploy Service Instances**
   ```bash
   # On each server (local and remote)
   python3 enhanced_babysitter.py service_generated.toml \
     --port <PORT> \
     --name <SERVICE_NAME> \
     --registry http://<REGISTRY_HOST>:8081 \
     --router http://<ROUTER_HOST>:8080
   ```

### 2. Adding New Service Instances

1. **Prepare Configuration**
   - Update `deployment_configs/test_services.json` if needed
   - Generate new TOML configuration

2. **Deploy Service**
   ```bash
   python3 enhanced_babysitter.py service_generated.toml \
     --port <NEW_PORT> \
     --name <NEW_SERVICE_NAME> \
     --registry http://<REGISTRY_HOST>:8081 \
     --router http://<ROUTER_HOST>:8080
   ```

3. **Verify Registration**
   ```bash
   curl http://localhost:8081/services
   curl http://localhost:8080/stats
   ```

### 3. Removing Service Instances

1. **Graceful Shutdown**
   ```bash
   # Send SIGTERM to babysitter process
   kill -TERM <BABYSITTER_PID>
   ```

2. **Verify Deregistration**
   ```bash
   curl http://localhost:8081/services
   ```

3. **Cleanup**
   - Remove configuration files
   - Clean up logs

## Security Considerations

### 1. Network Security
- Registry and router should be deployed on trusted networks
- Consider firewall rules for service ports
- Use HTTPS for production deployments

### 2. Service Authentication
- Implement API key authentication for production
- Use service tokens for registry communication
- Secure service-to-service communication

### 3. Resource Management
- Monitor GPU memory usage
- Implement resource limits per service
- Use process monitoring and restart mechanisms

## Backup and Recovery

### 1. Configuration Backup
```bash
# Backup configuration files
tar -czf config_backup_$(date +%Y%m%d).tar.gz \
  deployment_configs/ \
  templates/ \
  *.json \
  *.toml
```

### 2. Service Recovery
1. **Registry Recovery**
   - Restart registry service
   - Services will re-register automatically

2. **Router Recovery**
   - Restart router service
   - Router will re-discover services from registry

3. **Service Instance Recovery**
   - Restart babysitter service
   - Service will re-register with registry

## Maintenance Schedule

### Daily
- Check service health status
- Monitor log files for errors
- Verify service registration

### Weekly
- Review service statistics
- Clean up old log files
- Update service configurations if needed

### Monthly
- Full system validation test
- Performance analysis
- Security review
- Backup configuration files

## Support and Documentation

### Key Files
- `validate_integration.py` - Complete system validation
- `distributed_router.py` - Router implementation
- `service_registry.py` - Registry implementation
- `enhanced_babysitter.py` - Service management wrapper
- `render_service_config.py` - Configuration generation

### Dependencies
- Python 3.8+
- aiohttp
- requests
- openai (for client testing)
- InfiniLM-Rust (for xtask services)

### Environment Setup

#### Option 1: Using Conda (Recommended)
```bash
# Create conda environment
conda create -n infinilm-distributed python=3.11
conda activate infinilm-distributed

# Install dependencies
pip install -r requirements.txt
```
