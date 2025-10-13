# Distributed InfiniLM Services Deployment

This document describes the distributed deployment architecture for InfiniLM services, allowing you to deploy services across multiple servers with centralized routing and service discovery.

## Architecture Overview

The distributed architecture consists of three main components:

1. **Service Registry** - Centralized service discovery and health monitoring
2. **Distributed Router** - Load balancer that routes requests to healthy services
3. **Service Instances** - Individual InfiniLM service instances running on different servers

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Server 1      │    │   Server 2      │    │   Router Server │
│                 │    │                 │    │                 │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │ Service     │ │    │ │ Service     │ │    │ │ Distributed │ │
│ │ Instance 1  │ │    │ │ Instance 3  │ │    │ │ Router      │ │
│ └─────────────┘ │    │ └─────────────┘ │    │ └─────────────┘ │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │ Service     │ │    │ │ Service     │ │    │ │ Service     │ │
│ │ Instance 2  │ │    │ │ Instance 4  │ │    │ │ Registry    │ │
│ └─────────────┘ │    │ └─────────────┘ │    │ └─────────────┘ │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │   Client        │
                    │   Requests      │
                    └─────────────────┘
```

## Components

### 1. Service Registry (`service_registry.py`)

The service registry provides:
- Service registration and discovery
- Health monitoring of registered services
- Automatic cleanup of stale services
- REST API for service management

**Key Features:**
- Automatic service discovery
- Health check monitoring
- Service metadata support
- Heartbeat mechanism
- RESTful API endpoints

**Endpoints:**
- `GET /health` - Registry health status
- `GET /services` - List all registered services
- `POST /services` - Register a new service
- `PUT /services/{name}` - Update service information
- `DELETE /services/{name}` - Unregister a service
- `GET /services/{name}/health` - Check specific service health
- `POST /services/{name}/heartbeat` - Service heartbeat
- `GET /stats` - Registry statistics

### 2. Distributed Router (`distributed_router.py`)

The distributed router provides:
- Load balancing across multiple servers
- Service discovery integration
- Health monitoring
- Request proxying

**Key Features:**
- Dynamic service discovery from registry
- Weighted round-robin load balancing
- Health check monitoring
- Static service configuration support
- Automatic failover

### 3. Service Instance Launcher (`start_service_instance.sh`)

Individual service launcher that:
- Starts a single InfiniLM service instance
- Auto-registers with the service registry
- Provides health monitoring
- Supports graceful shutdown

## Deployment Configuration

### Configuration Files

The deployment uses JSON configuration files in the `deployment_configs/` directory:

#### `registry_config.json`
```json
{
  "registry": {
    "port": 8081,
    "health_interval": 30,
    "health_timeout": 5,
    "cleanup_interval": 60
  },
  "servers": [
    {
      "name": "server1",
      "host": "192.168.1.10",
      "services": ["infinilm-gpu1", "infinilm-gpu2"]
    }
  ]
}
```

#### `router_config.json`
```json
{
  "router": {
    "port": 8080,
    "registry_url": "http://192.168.1.100:8081",
    "load_balancing_method": "round_robin",
    "proxy_timeout": 300,
    "proxy_connect_timeout": 60
  },
  "static_services": {
    "services": [
      {
        "name": "infinilm-backup1",
        "host": "192.168.1.12",
        "port": 5001,
        "weight": 1,
        "metadata": {
          "static": true,
          "backup": true
        }
      }
    ]
  }
}
```

#### `server1_services.json`
```json
{
  "services": [
    {
      "name": "infinilm-gpu1",
      "host": "192.168.1.10",
      "port": 5001,
      "weight": 1,
      "max_fails": 3,
      "fail_timeout": "30s",
      "metadata": {
        "gpu_count": 4,
        "model": "Qwen3-32B",
        "server_role": "primary"
      }
    }
  ]
}
```

## Deployment Instructions

### 1. Setup on Router Server

The router server runs the service registry and distributed router:

```bash
# Start service registry
./deploy_services.sh start-registry

# Start distributed router
./deploy_services.sh start-router

# Check status
./deploy_services.sh status
```

### 2. Setup on Service Servers

On each server that will run InfiniLM services:

```bash
# Start local services (auto-registers with registry)
./deploy_services.sh start-services

# Check status
./deploy_services.sh status
```

### 3. Generate Nginx Configuration

Generate nginx configuration for additional load balancing:

```bash
# Generate nginx config from registry
./deploy_services.sh generate-config

# Use the generated nginx_distributed.conf
nginx -c /path/to/nginx_distributed.conf
```

## Management Commands

### Using the Deployment Script

```bash
# Start service registry
./deploy_services.sh start-registry

# Start distributed router
./deploy_services.sh start-router

# Start local services
./deploy_services.sh start-services

# Stop all services
./deploy_services.sh stop-all

# Show status
./deploy_services.sh status

# Generate nginx configuration
./deploy_services.sh generate-config
```

### Manual Service Management

#### Start Service Registry
```bash
python3 service_registry.py --port 8081
```

#### Start Distributed Router
```bash
python3 distributed_router.py \
    --router-port 8080 \
    --registry-url http://192.168.1.100:8081 \
    --static-services deployment_configs/router_config.json
```

#### Start Individual Service
```bash
./start_service_instance.sh \
    --port 5001 \
    --config service_instance1.toml \
    --name infinilm-gpu1 \
    --registry http://192.168.1.100:8081/services
```

## Service Discovery

Services automatically register with the registry and provide:

1. **Automatic Registration** - Services register themselves on startup
2. **Health Monitoring** - Registry monitors service health
3. **Heartbeat Mechanism** - Services send periodic heartbeats
4. **Automatic Cleanup** - Stale services are automatically removed

## Load Balancing

The distributed router supports multiple load balancing strategies:

- **Round Robin** (default) - Distributes requests evenly
- **Least Connections** - Routes to service with fewest active connections
- **IP Hash** - Routes based on client IP for session affinity
- **Weighted** - Routes based on service weights

## Health Monitoring

### Service Health Checks

- Registry performs periodic health checks on all services
- Services are marked unhealthy after consecutive failures
- Unhealthy services are excluded from load balancing
- Services are automatically re-included when they recover

### Health Check Endpoints

- `GET /health` - Router health status
- `GET /services` - List all services with health status
- `GET /stats` - Detailed statistics

## Scaling

### Adding New Servers

1. Create service configuration file for the new server
2. Deploy the service launcher script
3. Start services on the new server
4. Services automatically register with the registry
5. Router automatically discovers and routes to new services

### Adding New Services

1. Add service configuration to the appropriate server config file
2. Restart services on that server
3. New services automatically register and become available

## Monitoring and Troubleshooting

### Log Files

- `logs/registry.log` - Service registry logs
- `logs/distributed_router.log` - Router logs
- `logs/{service_name}.log` - Individual service logs

### Status Checking

```bash
# Check overall status
./deploy_services.sh status

# Check registry status
curl http://localhost:8081/health

# Check router status
curl http://localhost:8080/health

# List all services
curl http://localhost:8081/services

# Get router statistics
curl http://localhost:8080/stats
```

### Common Issues

1. **Services not registering** - Check registry URL and network connectivity
2. **Router not finding services** - Verify registry is running and accessible
3. **Health check failures** - Check service endpoints and network connectivity
4. **Load balancing issues** - Verify service weights and health status

## Security Considerations

- Services communicate over HTTP (consider HTTPS for production)
- Registry and router should be behind a firewall
- Consider authentication for registry endpoints
- Monitor service registration for unauthorized access

## Performance Tuning

### Registry Settings
- Adjust health check intervals based on network latency
- Tune cleanup intervals for service churn
- Monitor registry performance under load

### Router Settings
- Adjust proxy timeouts based on service response times
- Tune load balancing weights based on service capacity
- Monitor router performance and scaling needs

### Service Settings
- Configure appropriate restart policies
- Tune heartbeat intervals
- Monitor service resource usage

## Migration from Single-Server Setup

To migrate from the existing single-server setup:

1. **Backup existing configuration**
2. **Deploy registry on a dedicated server**
3. **Update router to use distributed router**
4. **Deploy services on multiple servers**
5. **Update client configurations to use new router endpoint**
6. **Test and validate the new setup**
7. **Decommission old single-server setup**

This distributed architecture provides better scalability, fault tolerance, and management capabilities for large-scale InfiniLM deployments.
