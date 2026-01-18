#!/usr/bin/env python3
"""
Service Registry for InfiniLM Distributed Services
Provides service discovery and registration for distributed InfiniLM deployments
"""

import asyncio
import aiohttp
import json
import time
import logging
import signal
import sys
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Set
from dataclasses import dataclass, asdict
from aiohttp import web, ClientSession, ClientTimeout
import argparse

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/registry.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

@dataclass
class ServiceInfo:
    name: str
    host: str
    port: int
    hostname: str
    url: str
    status: str
    timestamp: str
    last_heartbeat: float = 0
    health_status: str = "unknown"
    metadata: Dict = None

    def __post_init__(self):
        if self.metadata is None:
            self.metadata = {}
        self.last_heartbeat = time.time()

    def is_healthy(self) -> bool:
        """Check if service is healthy based on heartbeat and status"""
        if self.status != "running":
            return False

        # Consider service unhealthy if no heartbeat for 2 minutes
        time_since_heartbeat = time.time() - self.last_heartbeat
        return time_since_heartbeat < 120

    def to_dict(self) -> Dict:
        """Convert to dictionary for JSON serialization"""
        data = asdict(self)
        data['is_healthy'] = self.is_healthy()
        return data

class ServiceRegistry:
    def __init__(self, registry_port: int = 8081):
        self.registry_port = registry_port
        self.services: Dict[str, ServiceInfo] = {}
        self.app = web.Application()
        self.health_check_interval = 30  # seconds
        self.health_check_timeout = 5   # seconds
        self.cleanup_interval = 60      # seconds
        self.running = False

        # Setup routes
        self.setup_routes()

        # Setup signal handlers
        signal.signal(signal.SIGINT, self.signal_handler)
        signal.signal(signal.SIGTERM, self.signal_handler)

    def signal_handler(self, signum, frame):
        """Handle shutdown signals gracefully"""
        logger.info(f"Received signal {signum}, shutting down registry...")
        self.running = False

    def setup_routes(self):
        """Setup HTTP routes"""
        self.app.router.add_get('/health', self.health_handler)
        self.app.router.add_get('/services', self.services_handler)
        self.app.router.add_get('/services/{service_name}', self.get_service_handler)
        self.app.router.add_post('/services', self.register_service_handler)
        self.app.router.add_put('/services/{service_name}', self.update_service_handler)
        self.app.router.add_delete('/services/{service_name}', self.unregister_service_handler)
        self.app.router.add_get('/services/{service_name}/health', self.service_health_handler)
        self.app.router.add_post('/services/{service_name}/heartbeat', self.heartbeat_handler)
        self.app.router.add_get('/stats', self.stats_handler)

    async def health_handler(self, request):
        """Health check endpoint for the registry"""
        healthy_services = sum(1 for s in self.services.values() if s.is_healthy())
        total_services = len(self.services)

        return web.json_response({
            "status": "healthy",
            "registry": "running",
            "registered_services": total_services,
            "healthy_services": healthy_services,
            "timestamp": datetime.now().isoformat()
        })

    async def services_handler(self, request):
        """Get all registered services"""
        services_list = [service.to_dict() for service in self.services.values()]

        # Filter by status if requested
        status_filter = request.query.get('status')
        if status_filter:
            services_list = [s for s in services_list if s['status'] == status_filter]

        # Filter by health if requested
        health_filter = request.query.get('healthy')
        if health_filter:
            healthy_only = health_filter.lower() == 'true'
            services_list = [s for s in services_list if s['is_healthy'] == healthy_only]

        return web.json_response({
            "services": services_list,
            "total": len(services_list),
            "timestamp": datetime.now().isoformat()
        })

    async def get_service_handler(self, request):
        """Get specific service information"""
        service_name = request.match_info['service_name']

        if service_name not in self.services:
            return web.json_response(
                {"error": f"Service '{service_name}' not found"},
                status=404
            )

        return web.json_response(self.services[service_name].to_dict())

    async def register_service_handler(self, request):
        """Register a new service"""
        try:
            data = await request.json()

            # Validate required fields
            required_fields = ['name', 'host', 'port', 'hostname', 'url', 'status']
            for field in required_fields:
                if field not in data:
                    return web.json_response(
                        {"error": f"Missing required field: {field}"},
                        status=400
                    )

            service_info = ServiceInfo(
                name=data['name'],
                host=data['host'],
                port=data['port'],
                hostname=data['hostname'],
                url=data['url'],
                status=data['status'],
                timestamp=data.get('timestamp', datetime.now().isoformat()),
                metadata=data.get('metadata', {})
            )

            self.services[service_info.name] = service_info

            logger.info(f"Registered service: {service_info.name} at {service_info.url}")

            return web.json_response({
                "message": f"Service '{service_info.name}' registered successfully",
                "service": service_info.to_dict()
            }, status=201)

        except json.JSONDecodeError:
            return web.json_response(
                {"error": "Invalid JSON"},
                status=400
            )
        except Exception as e:
            logger.error(f"Error registering service: {e}")
            return web.json_response(
                {"error": "Internal server error"},
                status=500
            )

    async def update_service_handler(self, request):
        """Update service information"""
        service_name = request.match_info['service_name']

        if service_name not in self.services:
            return web.json_response(
                {"error": f"Service '{service_name}' not found"},
                status=404
            )

        try:
            data = await request.json()
            service = self.services[service_name]

            # Update fields
            for field in ['host', 'port', 'hostname', 'url', 'status', 'metadata']:
                if field in data:
                    setattr(service, field, data[field])

            service.last_heartbeat = time.time()

            logger.info(f"Updated service: {service_name}")

            return web.json_response({
                "message": f"Service '{service_name}' updated successfully",
                "service": service.to_dict()
            })

        except json.JSONDecodeError:
            return web.json_response(
                {"error": "Invalid JSON"},
                status=400
            )
        except Exception as e:
            logger.error(f"Error updating service: {e}")
            return web.json_response(
                {"error": "Internal server error"},
                status=500
            )

    async def unregister_service_handler(self, request):
        """Unregister a service"""
        service_name = request.match_info['service_name']

        if service_name not in self.services:
            return web.json_response(
                {"error": f"Service '{service_name}' not found"},
                status=404
            )

        del self.services[service_name]
        logger.info(f"Unregistered service: {service_name}")

        return web.json_response({
            "message": f"Service '{service_name}' unregistered successfully"
        })

    async def service_health_handler(self, request):
        """Check health of a specific service"""
        service_name = request.match_info['service_name']

        if service_name not in self.services:
            return web.json_response(
                {"error": f"Service '{service_name}' not found"},
                status=404
            )

        service = self.services[service_name]

        # Perform actual health check
        # For services with type "openai-api", check the babysitter URL (port + 1)
        # The service endpoint only exposes OpenAI API, babysitter provides /health endpoint
        # Rule: babysitter_port = service_port + 1
        if service.metadata.get("type") == "openai-api":
            # Calculate babysitter URL: service port + 1
            babysitter_port = service.port + 1
            check_url = f"http://{service.host}:{babysitter_port}"
        else:
            # For babysitter and other services, check their own URL
            check_url = service.url

        try:
            timeout = ClientTimeout(total=self.health_check_timeout)
            async with ClientSession(timeout=timeout) as session:
                async with session.get(f"{check_url}/health") as response:
                    if response.status == 200:
                        service.health_status = "healthy"
                        service.last_heartbeat = time.time()
                    else:
                        service.health_status = "unhealthy"
        except Exception as e:
            service.health_status = "unhealthy"
            logger.warning(f"Health check failed for {service_name} (check_url: {check_url}): {e}")

        return web.json_response({
            "service": service_name,
            "health_status": service.health_status,
            "is_healthy": service.is_healthy(),
            "last_heartbeat": service.last_heartbeat,
            "timestamp": datetime.now().isoformat()
        })

    async def heartbeat_handler(self, request):
        """Handle service heartbeat"""
        service_name = request.match_info['service_name']

        if service_name not in self.services:
            return web.json_response(
                {"error": f"Service '{service_name}' not found"},
                status=404
            )

        service = self.services[service_name]
        service.last_heartbeat = time.time()

        # Update status if provided
        try:
            data = await request.json()
            if 'status' in data:
                service.status = data['status']
        except:
            pass  # No JSON data, just update heartbeat

        return web.json_response({
            "message": "Heartbeat received",
            "timestamp": datetime.now().isoformat()
        })

    async def stats_handler(self, request):
        """Get registry statistics"""
        healthy_services = sum(1 for s in self.services.values() if s.is_healthy())
        total_services = len(self.services)

        # Group by status
        status_counts = {}
        for service in self.services.values():
            status_counts[service.status] = status_counts.get(service.status, 0) + 1

        # Group by host
        host_counts = {}
        for service in self.services.values():
            host_counts[service.host] = host_counts.get(service.host, 0) + 1

        return web.json_response({
            "total_services": total_services,
            "healthy_services": healthy_services,
            "unhealthy_services": total_services - healthy_services,
            "status_distribution": status_counts,
            "host_distribution": host_counts,
            "uptime": time.time() - getattr(self, 'start_time', time.time()),
            "timestamp": datetime.now().isoformat()
        })

    async def perform_health_checks(self):
        """Perform health checks on all registered services"""
        while self.running:
            try:
                if self.services:
                    tasks = []
                    for service in self.services.values():
                        task = self.check_service_health(service)
                        tasks.append(task)

                    await asyncio.gather(*tasks, return_exceptions=True)

                    healthy_count = sum(1 for s in self.services.values() if s.is_healthy())
                    logger.info(f"Health check completed: {healthy_count}/{len(self.services)} services healthy")

            except Exception as e:
                logger.error(f"Error during health checks: {e}")

            await asyncio.sleep(self.health_check_interval)

    async def check_service_health(self, service: ServiceInfo):
        """Check health of a single service"""
        try:
            # For services with type "openai-api", check the babysitter URL (port + 1)
            # The service endpoint only exposes OpenAI API, babysitter provides /health endpoint
            # Rule: babysitter_port = service_port + 1
            if service.metadata.get("type") == "openai-api":
                # Calculate babysitter URL: service port + 1
                babysitter_port = service.port + 1
                check_url = f"http://{service.host}:{babysitter_port}"
            elif service.metadata.get("type") == "babysitter":
                # Babysitter services check their own URL
                check_url = service.url
            else:
                # Default: use service URL
                check_url = service.url

            timeout = ClientTimeout(total=self.health_check_timeout)
            async with ClientSession(timeout=timeout) as session:
                async with session.get(f"{check_url}/health") as response:
                    if response.status == 200:
                        service.health_status = "healthy"
                    else:
                        service.health_status = "unhealthy"
        except Exception as e:
            service.health_status = "unhealthy"
            logger.warning(f"Health check failed for service {service.name} (check_url: {check_url if 'check_url' in locals() else service.url}): {e}")

    async def cleanup_stale_services(self):
        """Remove services that haven't sent heartbeats"""
        while self.running:
            try:
                current_time = time.time()
                stale_services = []

                for name, service in self.services.items():
                    # Remove services that haven't sent heartbeat for 5 minutes
                    if current_time - service.last_heartbeat > 300:
                        stale_services.append(name)

                for name in stale_services:
                    del self.services[name]
                    logger.info(f"Removed stale service: {name}")

                if stale_services:
                    logger.info(f"Cleaned up {len(stale_services)} stale services")

            except Exception as e:
                logger.error(f"Error during cleanup: {e}")

            await asyncio.sleep(self.cleanup_interval)

    async def run(self):
        """Run the registry service"""
        logger.info(f"Starting service registry on port {self.registry_port}")

        # Start background tasks
        asyncio.create_task(self.perform_health_checks())
        asyncio.create_task(self.cleanup_stale_services())

        # Start the web server
        runner = web.AppRunner(self.app)
        await runner.setup()

        site = web.TCPSite(runner, '0.0.0.0', self.registry_port)
        await site.start()

        self.running = True
        self.start_time = time.time()
        logger.info(f"Service registry started successfully on http://0.0.0.0:{self.registry_port}")

        # Keep the service running
        try:
            while self.running:
                await asyncio.sleep(1)
        except KeyboardInterrupt:
            logger.info("Received keyboard interrupt")
        finally:
            logger.info("Shutting down service registry...")
            await runner.cleanup()

def main():
    parser = argparse.ArgumentParser(description="InfiniLM Service Registry")
    parser.add_argument("--port", type=int, default=8081, help="Registry port (default: 8081)")
    parser.add_argument("--health-interval", type=int, default=30, help="Health check interval in seconds (default: 30)")
    parser.add_argument("--health-timeout", type=int, default=5, help="Health check timeout in seconds (default: 5)")
    parser.add_argument("--cleanup-interval", type=int, default=60, help="Cleanup interval in seconds (default: 60)")

    args = parser.parse_args()

    # Create logs directory
    import os
    os.makedirs('logs', exist_ok=True)

    # Create registry service
    registry = ServiceRegistry(args.port)
    registry.health_check_interval = args.health_interval
    registry.health_check_timeout = args.health_timeout
    registry.cleanup_interval = args.cleanup_interval

    # Run the registry
    try:
        asyncio.run(registry.run())
    except KeyboardInterrupt:
        logger.info("Service registry stopped by user")
    except Exception as e:
        logger.error(f"Service registry error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
