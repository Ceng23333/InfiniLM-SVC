# InfiniLM Multi-Service Setup

This setup allows you to run multiple InfiniLM service instances with load balancing to overcome concurrency limitations in a single process.

## Features

- **Multiple Service Instances**: Run multiple InfiniLM services on different ports
- **Load Balancing**: Distribute requests across healthy service instances
- **Health Monitoring**: Automatic health checks and service recovery
- **Two Router Options**: Custom Python router or nginx-based load balancing
- **Graceful Shutdown**: Proper cleanup of all services
- **Comprehensive Logging**: Detailed logs for monitoring and debugging

## Quick Start

### Option 1: Using Custom Router (Recommended)

```bash
# Start with default configuration (3 services on ports 5001, 5002, 5003)
./start_multi_service.sh

# Start with custom configuration
./start_multi_service.sh -s 5001,5002,5003,5004 -c service.toml,service_ds.toml,service.toml,service.toml

# Start only the router (for testing)
./start_multi_service.sh --router-only
```

### Option 2: Using Nginx

```bash
# Start with nginx load balancing
./start_multi_service.sh --use-nginx

# Make sure nginx is installed
sudo apt-get install nginx  # Ubuntu/Debian
# or
sudo yum install nginx      # CentOS/RHEL
```

## Configuration

### Service Configuration Files

Create separate configuration files for each service instance:

- `service_instance1.toml` - First service instance
- `service_instance2.toml` - Second service instance
- `service_instance3.toml` - Third service instance

Each configuration should specify different GPU assignments to avoid conflicts.

### Router Configuration

The router runs on port 8080 by default and provides:

- **Load Balancing**: Round-robin distribution across healthy services
- **Health Checks**: Automatic monitoring of service health
- **Request Routing**: Transparent proxying to backend services
- **Statistics**: Real-time monitoring of service status

## API Endpoints

### Router Endpoints

- `GET /health` - Router health status
- `GET /stats` - Service statistics
- `GET /services` - Individual service information
- `* /{path}` - Proxied to backend services

### Service Endpoints

- `GET /health` - Individual service health
- All other endpoints are forwarded from the router

## Monitoring

### Health Monitor

Run the health monitor to track service status:

```bash
python3 health_monitor.py --service-urls http://127.0.0.1:5001,http://127.0.0.1:5002,http://127.0.0.1:5003
```

### Logs

All logs are stored in the `logs/` directory:

- `router.log` - Router service logs
- `service_*.log` - Individual service logs
- `health_monitor.log` - Health monitoring logs
- `nginx_*.log` - Nginx logs (if using nginx)

## Advanced Usage

### Custom Service Ports

```bash
./start_multi_service.sh -s 6001,6002,6003 -r 9000
```

### Custom Configuration Files

```bash
./start_multi_service.sh -c config1.toml,config2.toml,config3.toml
```

### Nginx Configuration

The nginx configuration is automatically generated in `nginx.conf` with:

- Load balancing using `least_conn` method
- Health checks and failover
- Rate limiting (10 requests/second)
- Proper timeout settings
- Security headers

### Router Configuration

The custom router supports:

- Round-robin load balancing
- Health check intervals (default: 30s)
- Service timeout settings (default: 5s)
- Error threshold (default: 3 errors)
- Real-time statistics

## Troubleshooting

### Service Won't Start

1. Check if ports are available:
   ```bash
   netstat -tlnp | grep :5001
   ```

2. Check GPU availability:
   ```bash
   nvidia-smi
   ```

3. Check configuration files:
   ```bash
   cat service_instance1.toml
   ```

### Router Issues

1. Check router logs:
   ```bash
   tail -f logs/router.log
   ```

2. Test router health:
   ```bash
   curl http://localhost:8080/health
   ```

3. Check service statistics:
   ```bash
   curl http://localhost:8080/stats
   ```

### Nginx Issues

1. Check nginx configuration:
   ```bash
   nginx -t -c nginx.conf
   ```

2. Check nginx logs:
   ```bash
   tail -f logs/nginx_error.log
   ```

3. Restart nginx:
   ```bash
   nginx -s reload
   ```

## Performance Tuning

### Service Configuration

- Adjust `max-sessions` based on GPU memory
- Tune `gpu-memory-utilization` for optimal performance
- Use different GPU sets for each service instance

### Router Configuration

- Adjust health check intervals
- Tune timeout settings
- Monitor error rates and response times

### Nginx Configuration

- Adjust worker connections
- Tune buffer sizes
- Configure rate limiting

## Stopping Services

Press `Ctrl+C` to gracefully stop all services. The script will:

1. Stop the router
2. Stop all service instances
3. Clean up process files
4. Stop nginx (if used)

## File Structure

```
InfiniLM/
├── start_multi_service.sh      # Multi-service launcher
├── router.py                   # Custom router service
├── health_monitor.py           # Health monitoring
├── nginx.conf                  # Nginx configuration
├── service_instance*.toml      # Service configurations
├── logs/                       # Log directory
│   ├── router.log
│   ├── service_*.log
│   └── health_monitor.log
└── MULTI_SERVICE_README.md     # This file
```

## Dependencies

- Python 3.7+
- aiohttp
- nginx (optional, for nginx-based load balancing)

Install Python dependencies:

```bash
pip install aiohttp
```

## Examples

### Basic Setup

```bash
# Start 3 services with custom router
./start_multi_service.sh

# Access the service
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "Hello!"}]}'
```

### Nginx Setup

```bash
# Start with nginx
./start_multi_service.sh --use-nginx

# Check nginx status
curl http://localhost:8080/health
```

### Monitoring

```bash
# Start health monitor
python3 health_monitor.py --service-urls http://127.0.0.1:5001,http://127.0.0.1:5002,http://127.0.0.1:5003

# Check service statistics
curl http://localhost:8080/stats
```

This setup provides a robust, scalable solution for running multiple InfiniLM services with proper load balancing and monitoring.
