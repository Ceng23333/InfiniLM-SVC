#!/usr/bin/env python3
"""
Router Client for InfiniLM Services
Provides interface for interacting with the distributed router
"""

import requests
import logging
import json
from typing import Dict, Any, Optional, List

logger = logging.getLogger(__name__)

class RouterClient:
    def __init__(self, router_url: str = "http://localhost:8080"):
        self.router_url = router_url.rstrip('/')
        self.session = requests.Session()
        self.session.timeout = 30

    def check_router_health(self) -> bool:
        """Check if router is healthy"""
        try:
            response = self.session.get(f"{self.router_url}/health")

            if response.status_code == 200:
                data = response.json()
                logger.info(f"Router is healthy: {data.get('healthy_services', 'unknown')} services available")
                return True
            else:
                logger.error(f"Router health check failed: {response.text}")
                return False

        except requests.exceptions.RequestException as e:
            logger.error(f"Cannot connect to router at {self.router_url}")
            return False

    def get_router_stats(self) -> Optional[Dict[str, Any]]:
        """Get router statistics"""
        try:
            response = self.session.get(f"{self.router_url}/stats")

            if response.status_code == 200:
                return response.json()
            else:
                logger.warning(f"Failed to get router stats: {response.text}")
                return None

        except requests.exceptions.RequestException as e:
            logger.warning(f"Error getting router stats: {e}")
            return None

    def get_models(self) -> Optional[Dict[str, Any]]:
        """Get available models through router"""
        try:
            response = self.session.get(f"{self.router_url}/models")

            if response.status_code == 200:
                return response.json()
            else:
                logger.warning(f"Failed to get models: {response.text}")
                return None

        except requests.exceptions.RequestException as e:
            logger.warning(f"Error getting models: {e}")
            return None

    def chat_completions(self, messages: List[Dict[str, str]], model: str = None, **kwargs) -> Optional[Dict[str, Any]]:
        """Send chat completion request through router"""
        payload = {
            "messages": messages,
            **kwargs
        }

        if model:
            payload["model"] = model

        try:
            response = self.session.post(
                f"{self.router_url}/chat/completions",
                json=payload
            )

            if response.status_code == 200:
                return response.json()
            else:
                logger.warning(f"Chat completion failed: {response.text}")
                return None

        except requests.exceptions.RequestException as e:
            logger.warning(f"Error in chat completion: {e}")
            return None

    def test_router_connection(self) -> bool:
        """Test router connection with a simple request"""
        try:
            # Try to get models as a simple test
            models = self.get_models()
            if models is not None:
                logger.info("✅ Router connection test successful")
                return True
            else:
                logger.warning("⚠️ Router connection test failed - no models returned")
                return False

        except Exception as e:
            logger.error(f"❌ Router connection test failed: {e}")
            return False
