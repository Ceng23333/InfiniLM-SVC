#!/usr/bin/env python3
"""
Simple test service for InfiniLM distributed testing
"""

import asyncio
import aiohttp
from aiohttp import web
import json
import time
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class TestService:
    def __init__(self, port=5001):
        self.port = port
        self.app = web.Application()
        self.start_time = time.time()
        self.setup_routes()

    def setup_routes(self):
        self.app.router.add_get('/health', self.health_check)
        self.app.router.add_get('/models', self.get_models)
        self.app.router.add_get('/info', self.get_info)
        self.app.router.add_post('/chat/completions', self.chat_completions)

    async def health_check(self, request):
        """Health check endpoint"""
        return web.json_response({
            "status": "healthy",
            "service": "test-service",
            "timestamp": time.time(),
            "port": self.port
        })

    async def get_models(self, request):
        """Get available models"""
        return web.json_response({
            "object": "list",
            "data": [
                {
                    "id": "test-model-1",
                    "object": "model",
                    "created": int(time.time()),
                    "owned_by": "test-service"
                }
            ]
        })

    async def get_info(self, request):
        """Service information endpoint"""
        return web.json_response({
            "name": "test-service",
            "host": "localhost",
            "port": self.port,
            "url": f"http://localhost:{self.port}",
            "metadata": {
                "type": "mock",
                "test": True,
                "description": "Mock service for testing"
            },
            "uptime": time.time() - getattr(self, 'start_time', time.time())
        })

    async def chat_completions(self, request):
        """Mock chat completions endpoint"""
        try:
            data = await request.json()
            return web.json_response({
                "id": "test-response-1",
                "object": "chat.completion",
                "created": int(time.time()),
                "model": data.get("model", "test-model-1"),
                "choices": [
                    {
                        "index": 0,
                        "message": {
                            "role": "assistant",
                            "content": "This is a test response from the mock service."
                        },
                        "finish_reason": "stop"
                    }
                ],
                "usage": {
                    "prompt_tokens": 10,
                    "completion_tokens": 15,
                    "total_tokens": 25
                }
            })
        except Exception as e:
            return web.json_response({"error": str(e)}, status=400)

    async def start(self):
        """Start the service"""
        runner = web.AppRunner(self.app)
        await runner.setup()
        site = web.TCPSite(runner, '0.0.0.0', self.port)
        await site.start()
        logger.info(f"Test service started on port {self.port}")

        # Keep the service running
        try:
            while True:
                await asyncio.sleep(1)
        except KeyboardInterrupt:
            logger.info("Shutting down test service...")
        finally:
            await runner.cleanup()

async def main():
    service = TestService()
    await service.start()

if __name__ == "__main__":
    asyncio.run(main())
