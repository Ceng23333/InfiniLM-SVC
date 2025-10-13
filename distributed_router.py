#!/usr/bin/env python3
"""
Distributed Router Service for InfiniLM Multi-Service Setup
Supports service discovery, remote endpoints, and dynamic service registration
"""

import asyncio
import aiohttp
import json
import time
import logging
import signal
import sys
from datetime import datetime
from typing import List, Dict, Optional, Set
from dataclasses import dataclass
from aiohttp import web, ClientSession, ClientTimeout
import argparse

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/distributed_router.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

@dataclass
class ServiceInstance:
    name: str
    host: str
    port: int
    url: str
    healthy: bool = True
    last_check: float = 0
    response_time: float = 0
    error_count: int = 0
    request_count: int = 0
    weight: int = 1
    metadata: Dict = None

    def __post_init__(self):
        if self.metadata is None:
            self.metadata = {}

class DistributedLoadBalancer:
    def __init__(self, registry_url: Optional[str] = None, static_services: List[Dict] = None):
        self.services: Dict[str, ServiceInstance] = {}
        self.current_index = 0
        self.health_check_interval = 30  # seconds
        self.health_check_timeout = 5   # seconds
        self.max_errors = 3
        self.running = True
        self.registry_url = registry_url
        self.registry_sync_interval = 60  # seconds

        # Initialize static services if provided
        if static_services:
            for service_config in static_services:
                self.add_static_service(service_config)

        logger.info(f"Initialized distributed load balancer with {len(self.services)} services")

    def add_static_service(self, service_config: Dict):
        """Add a static service configuration"""
        service = ServiceInstance(
            name=service_config.get('name', f"service_{len(self.services) + 1}"),
            host=service_config['host'],
            port=service_config['port'],
            url=f"http://{service_config['host']}:{service_config['port']}",
            weight=service_config.get('weight', 1),
            metadata=service_config.get('metadata', {})
        )
        self.services[service.name] = service
        logger.info(f"Added static service: {service.name} at {service.url}")

    async def sync_with_registry(self):
        """Sync services with the service registry"""
        if not self.registry_url:
            return

        try:
            timeout = ClientTimeout(total=10)
            async with ClientSession(timeout=timeout) as session:
                async with session.get(f"{self.registry_url}/services?healthy=true") as response:
                    if response.status == 200:
                        data = await response.json()
                        registry_services = data.get('services', [])

                        # Update services from registry
                        registry_service_names = set()
                        for service_data in registry_services:
                            service_name = service_data['name']
                            registry_service_names.add(service_name)

                            if service_name in self.services:
                                # Update existing service
                                service = self.services[service_name]
                                service.host = service_data['host']
                                service.port = service_data['port']
                                service.url = service_data['url']
                                service.healthy = service_data.get('is_healthy', True)
                                service.metadata = service_data.get('metadata', {})
                            else:
                                # Add new service from registry
                                service = ServiceInstance(
                                    name=service_name,
                                    host=service_data['host'],
                                    port=service_data['port'],
                                    url=service_data['url'],
                                    healthy=service_data.get('is_healthy', True),
                                    weight=service_data.get('weight', 1),
                                    metadata=service_data.get('metadata', {})
                                )
                                self.services[service_name] = service
                                logger.info(f"Added service from registry: {service_name} at {service.url}")

                        # Remove services that are no longer in registry (but keep static services)
                        services_to_remove = []
                        for service_name, service in self.services.items():
                            if (service_name not in registry_service_names and
                                not service.metadata.get('static', False)):
                                services_to_remove.append(service_name)

                        for service_name in services_to_remove:
                            del self.services[service_name]
                            logger.info(f"Removed service from registry: {service_name}")

        except Exception as e:
            logger.warning(f"Failed to sync with registry: {e}")

    async def health_check(self, service: ServiceInstance) -> bool:
        """Perform health check on a service instance"""
        try:
            timeout = ClientTimeout(total=self.health_check_timeout)
            async with ClientSession(timeout=timeout) as session:
                start_time = time.time()
                async with session.get(f"{service.url}/health") as response:
                    service.response_time = time.time() - start_time
                    if response.status == 200:
                        service.healthy = True
                        service.error_count = 0
                        service.last_check = time.time()
                        return True
                    else:
                        service.healthy = False
                        service.error_count += 1
                        return False
        except Exception as e:
            logger.warning(f"Health check failed for service {service.name}: {e}")
            service.healthy = False
            service.error_count += 1
            service.last_check = time.time()
            return False

    async def perform_health_checks(self):
        """Perform health checks on all services"""
        while self.running:
            try:
                if self.services:
                    tasks = [self.health_check(service) for service in self.services.values()]
                    await asyncio.gather(*tasks, return_exceptions=True)

                    # Log health status
                    healthy_count = sum(1 for s in self.services.values() if s.healthy)
                    logger.info(f"Health check completed: {healthy_count}/{len(self.services)} services healthy")

                    # Log unhealthy services
                    for service in self.services.values():
                        if not service.healthy and service.error_count >= self.max_errors:
                            logger.warning(f"Service {service.name} is unhealthy (errors: {service.error_count})")

            except Exception as e:
                logger.error(f"Error during health checks: {e}")

            await asyncio.sleep(self.health_check_interval)

    async def sync_with_registry_periodically(self):
        """Periodically sync with service registry"""
        while self.running:
            try:
                await self.sync_with_registry()
            except Exception as e:
                logger.error(f"Error syncing with registry: {e}")

            await asyncio.sleep(self.registry_sync_interval)

    def get_next_healthy_service(self) -> Optional[ServiceInstance]:
        """Get next healthy service using weighted round-robin"""
        healthy_services = [s for s in self.services.values() if s.healthy]

        if not healthy_services:
            logger.error("No healthy services available")
            return None

        # Weighted round-robin selection
        total_weight = sum(service.weight for service in healthy_services)
        if total_weight == 0:
            # Fallback to simple round-robin
            service = healthy_services[self.current_index % len(healthy_services)]
            self.current_index += 1
        else:
            # Weighted selection
            current_weight = 0
            target_weight = self.current_index % total_weight
            for service in healthy_services:
                current_weight += service.weight
                if current_weight > target_weight:
                    self.current_index += 1
                    break
            else:
                # Fallback
                service = healthy_services[0]
                self.current_index += 1

        service.request_count += 1
        return service

    def get_service_stats(self) -> Dict:
        """Get statistics about all services"""
        stats = {
            "total_services": len(self.services),
            "healthy_services": sum(1 for s in self.services.values() if s.healthy),
            "registry_url": self.registry_url,
            "services": []
        }

        for service in self.services.values():
            service_stats = {
                "name": service.name,
                "host": service.host,
                "port": service.port,
                "url": service.url,
                "healthy": service.healthy,
                "request_count": service.request_count,
                "error_count": service.error_count,
                "response_time": service.response_time,
                "last_check": service.last_check,
                "weight": service.weight,
                "metadata": service.metadata
            }
            stats["services"].append(service_stats)

        return stats

class DistributedRouterService:
    def __init__(self, router_port: int, registry_url: Optional[str] = None,
                 static_services: List[Dict] = None):
        self.router_port = router_port
        self.load_balancer = DistributedLoadBalancer(registry_url, static_services)
        self.app = web.Application()
        self.setup_routes()
        self.running = False

        # Setup signal handlers
        signal.signal(signal.SIGINT, self.signal_handler)
        signal.signal(signal.SIGTERM, self.signal_handler)

    def signal_handler(self, signum, frame):
        """Handle shutdown signals gracefully"""
        logger.info(f"Received signal {signum}, shutting down router...")
        self.running = False

    def setup_routes(self):
        """Setup HTTP routes"""
        self.app.router.add_get('/health', self.health_handler)
        self.app.router.add_get('/stats', self.stats_handler)
        self.app.router.add_get('/services', self.services_handler)
        self.app.router.add_route('*', '/{path:.*}', self.proxy_handler)

    async def health_handler(self, request):
        """Health check endpoint for the router"""
        healthy_count = sum(1 for s in self.load_balancer.services.values() if s.healthy)
        total_count = len(self.load_balancer.services)

        if healthy_count == 0:
            return web.json_response(
                {"status": "unhealthy", "message": "No healthy services available"},
                status=503
            )

        return web.json_response({
            "status": "healthy",
            "router": "running",
            "healthy_services": f"{healthy_count}/{total_count}",
            "registry_url": self.load_balancer.registry_url,
            "timestamp": datetime.now().isoformat()
        })

    async def stats_handler(self, request):
        """Statistics endpoint"""
        stats = self.load_balancer.get_service_stats()
        return web.json_response(stats)

    async def services_handler(self, request):
        """Services information endpoint"""
        services_info = []
        for service in self.load_balancer.services.values():
            services_info.append({
                "name": service.name,
                "host": service.host,
                "port": service.port,
                "url": service.url,
                "healthy": service.healthy,
                "request_count": service.request_count,
                "error_count": service.error_count,
                "response_time": service.response_time,
                "weight": service.weight,
                "metadata": service.metadata
            })

        return web.json_response({
            "services": services_info,
            "total": len(services_info),
            "registry_url": self.load_balancer.registry_url
        })

    async def proxy_handler(self, request):
        """Proxy requests to backend services"""
        # Get next healthy service
        target_service = self.load_balancer.get_next_healthy_service()

        if not target_service:
            return web.json_response(
                {"error": "No healthy services available"},
                status=503
            )

        # Prepare target URL
        target_url = f"{target_service.url}{request.path_qs}"

        try:
            # Forward the request
            timeout = ClientTimeout(total=300)  # 5 minutes timeout
            async with ClientSession(timeout=timeout) as session:
                # Prepare headers
                headers = dict(request.headers)
                headers.pop('Host', None)  # Remove host header to avoid conflicts

                # Forward the request
                async with session.request(
                    method=request.method,
                    url=target_url,
                    headers=headers,
                    data=await request.read()
                ) as response:
                    # Read response body
                    body = await response.read()

                    # Create response
                    resp = web.Response(
                        body=body,
                        status=response.status,
                        headers=response.headers
                    )

                    logger.info(f"Proxied {request.method} {request.path} -> {target_service.name} ({response.status})")
                    return resp

        except asyncio.TimeoutError:
            logger.error(f"Timeout when proxying to service {target_service.name}")
            return web.json_response(
                {"error": "Service timeout"},
                status=504
            )
        except Exception as e:
            logger.error(f"Error proxying to service {target_service.name}: {e}")
            target_service.error_count += 1
            return web.json_response(
                {"error": "Service error"},
                status=502
            )

    async def start_background_tasks(self):
        """Start background monitoring tasks"""
        asyncio.create_task(self.load_balancer.perform_health_checks())
        if self.load_balancer.registry_url:
            asyncio.create_task(self.load_balancer.sync_with_registry_periodically())

    async def run(self):
        """Run the router service"""
        logger.info(f"Starting distributed router service on port {self.router_port}")
        logger.info(f"Registry URL: {self.load_balancer.registry_url or 'Not configured'}")
        logger.info(f"Initial services: {[s.name for s in self.load_balancer.services.values()]}")

        # Start background tasks
        await self.start_background_tasks()

        # Start the web server
        runner = web.AppRunner(self.app)
        await runner.setup()

        site = web.TCPSite(runner, '0.0.0.0', self.router_port)
        await site.start()

        self.running = True
        logger.info(f"Distributed router service started successfully on http://0.0.0.0:{self.router_port}")

        # Keep the service running
        try:
            while self.running:
                await asyncio.sleep(1)
        except KeyboardInterrupt:
            logger.info("Received keyboard interrupt")
        finally:
            logger.info("Shutting down distributed router service...")
            await runner.cleanup()

def main():
    parser = argparse.ArgumentParser(description="InfiniLM Distributed Router Service")
    parser.add_argument("--router-port", type=int, default=8080, help="Router port (default: 8080)")
    parser.add_argument("--registry-url", help="Service registry URL for dynamic service discovery")
    parser.add_argument("--static-services", help="JSON file with static service configurations")
    parser.add_argument("--health-interval", type=int, default=30, help="Health check interval in seconds (default: 30)")
    parser.add_argument("--health-timeout", type=int, default=5, help="Health check timeout in seconds (default: 5)")
    parser.add_argument("--max-errors", type=int, default=3, help="Max errors before marking service unhealthy (default: 3)")
    parser.add_argument("--registry-sync-interval", type=int, default=60, help="Registry sync interval in seconds (default: 60)")

    args = parser.parse_args()

    # Parse static services if provided
    static_services = None
    if args.static_services:
        try:
            with open(args.static_services, 'r') as f:
                config = json.load(f)
                static_services = config.get('services', [])
        except FileNotFoundError:
            print(f"Error: Static services file '{args.static_services}' not found", file=sys.stderr)
            sys.exit(1)
        except json.JSONDecodeError as e:
            print(f"Error: Invalid JSON in static services file: {e}", file=sys.stderr)
            sys.exit(1)

    # Create logs directory
    import os
    os.makedirs('logs', exist_ok=True)

    # Create router service
    router = DistributedRouterService(args.router_port, args.registry_url, static_services)

    # Configure load balancer
    router.load_balancer.health_check_interval = args.health_interval
    router.load_balancer.health_check_timeout = args.health_timeout
    router.load_balancer.max_errors = args.max_errors
    router.load_balancer.registry_sync_interval = args.registry_sync_interval

    # Run the router
    try:
        asyncio.run(router.run())
    except KeyboardInterrupt:
        logger.info("Distributed router service stopped by user")
    except Exception as e:
        logger.error(f"Distributed router service error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
