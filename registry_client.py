#!/usr/bin/env python3
"""
Registry Client for InfiniLM Services
Provides interface for interacting with the service registry
"""

import requests
import time
import logging
import json
from typing import Dict, Any, Optional, List
from dataclasses import dataclass

logger = logging.getLogger(__name__)

@dataclass
class ServiceInfo:
    name: str
    host: str
    port: int
    url: str
    status: str
    metadata: Dict[str, Any] = None

class RegistryClient:
    def __init__(self, registry_url: str = "http://localhost:8081"):
        self.registry_url = registry_url.rstrip('/')
        self.session = requests.Session()
        self.session.timeout = 10

    def register_service(self, service_info: ServiceInfo) -> bool:
        """Register a service with the registry"""
        service_data = {
            "name": service_info.name,
            "host": service_info.host,
            "hostname": service_info.host,
            "port": service_info.port,
            "url": service_info.url,
            "status": service_info.status,
            "metadata": service_info.metadata or {}
        }

        try:
            response = self.session.post(
                f"{self.registry_url}/services",
                json=service_data
            )

            if response.status_code == 201:
                logger.info(f"✅ Service '{service_info.name}' registered successfully")
                return True
            else:
                logger.error(f"❌ Failed to register service: {response.text}")
                return False

        except requests.exceptions.RequestException as e:
            logger.error(f"❌ Error connecting to registry: {e}")
            return False

    def unregister_service(self, service_name: str) -> bool:
        """Unregister a service from the registry"""
        try:
            response = self.session.delete(
                f"{self.registry_url}/services/{service_name}"
            )

            if response.status_code == 200:
                logger.info(f"✅ Service '{service_name}' unregistered successfully")
                return True
            else:
                logger.warning(f"⚠️ Failed to unregister service: {response.text}")
                return False

        except requests.exceptions.RequestException as e:
            logger.warning(f"⚠️ Error connecting to registry during unregister: {e}")
            return False

    def send_heartbeat(self, service_name: str) -> bool:
        """Send heartbeat to registry"""
        try:
            response = self.session.post(
                f"{self.registry_url}/services/{service_name}/heartbeat"
            )

            if response.status_code == 200:
                logger.debug(f"Heartbeat sent for {service_name}")
                return True
            else:
                logger.warning(f"Heartbeat failed: {response.text}")
                return False

        except requests.exceptions.RequestException as e:
            logger.warning(f"Heartbeat error: {e}")
            return False

    def get_service_health(self, service_name: str) -> Optional[Dict[str, Any]]:
        """Get service health status"""
        try:
            response = self.session.get(
                f"{self.registry_url}/services/{service_name}/health"
            )

            if response.status_code == 200:
                return response.json()
            else:
                logger.warning(f"Failed to get health status: {response.text}")
                return None

        except requests.exceptions.RequestException as e:
            logger.warning(f"Error getting health status: {e}")
            return None

    def list_services(self) -> List[Dict[str, Any]]:
        """List all registered services"""
        try:
            response = self.session.get(f"{self.registry_url}/services")

            if response.status_code == 200:
                data = response.json()
                return data.get('services', [])
            else:
                logger.warning(f"Failed to list services: {response.text}")
                return []

        except requests.exceptions.RequestException as e:
            logger.warning(f"Error listing services: {e}")
            return []

    def get_healthy_services(self) -> List[Dict[str, Any]]:
        """Get only healthy services"""
        try:
            response = self.session.get(f"{self.registry_url}/services?healthy=true")

            if response.status_code == 200:
                data = response.json()
                return data.get('services', [])
            else:
                logger.warning(f"Failed to get healthy services: {response.text}")
                return []

        except requests.exceptions.RequestException as e:
            logger.warning(f"Error getting healthy services: {e}")
            return []

    def check_registry_health(self) -> bool:
        """Check if registry is healthy"""
        try:
            response = self.session.get(f"{self.registry_url}/health")

            if response.status_code == 200:
                data = response.json()
                logger.info(f"Registry is healthy: {data.get('registered_services', 0)} services registered")
                return True
            else:
                logger.error(f"Registry health check failed: {response.text}")
                return False

        except requests.exceptions.RequestException as e:
            logger.error(f"Cannot connect to registry at {self.registry_url}")
            return False
