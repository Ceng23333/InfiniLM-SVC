#!/usr/bin/env python3
"""
Mock Service for Integration Testing
Simulates a backend InfiniLM service with OpenAI API compatibility
"""

import asyncio
import aiohttp
from aiohttp import web
import json
import argparse
import signal
import sys
from typing import List, Dict, Any
import time
import logging

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

class MockService:
    def __init__(self, name: str, port: int, models: List[str], registry_url: str = None):
        self.name = name
        self.port = port
        self.babysitter_port = port + 1
        self.models = models
        self.registry_url = registry_url
        self.app = web.Application()
        self.running = False
        self.request_count = 0
        
        # Setup routes
        self.app.router.add_post('/v1/chat/completions', self.chat_completions_handler)
        self.app.router.add_get('/v1/models', self.models_handler)
        self.app.router.add_get('/health', self.health_handler)
        
    async def register_with_registry(self):
        """Register this service with the registry"""
        if not self.registry_url:
            logger.info("No registry URL provided, skipping registration")
            print(f"[{self.name}] No registry URL, skipping registration", flush=True)
            return
        
        logger.info(f"Registering {self.name} with registry at {self.registry_url}")
        print(f"[{self.name}] Registering with registry at {self.registry_url}", flush=True)
            
        service_data = {
            "name": self.name,
            "host": "127.0.0.1",
            "hostname": "localhost",
            "port": self.port,
            "url": f"http://127.0.0.1:{self.port}",
            "status": "running",
            "metadata": {
                "type": "openai-api",
                "models": self.models,
                "models_list": [
                    {"id": model, "object": "model", "created": int(time.time())}
                    for model in self.models
                ]
            }
        }
        
        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    f"{self.registry_url}/services",
                    json=service_data,
                    timeout=aiohttp.ClientTimeout(total=5)
                ) as response:
                    text = await response.text()
                    if response.status == 201:
                        logger.info(f"✅ {self.name} registered with registry")
                        print(f"[{self.name}] ✅ Registered with registry (status: {response.status})", flush=True)
                        return True
                    else:
                        logger.warning(f"Failed to register {self.name}: {response.status} - {text}")
                        print(f"[{self.name}] ⚠️  Registration failed: {response.status} - {text}", flush=True)
                        return False
        except Exception as e:
            logger.error(f"Error registering {self.name}: {e}", exc_info=True)
            print(f"[{self.name}] ❌ Error registering: {e}", flush=True)
            return False
    
    async def send_heartbeat(self):
        """Send heartbeat to registry"""
        if not self.registry_url:
            return
            
        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    f"{self.registry_url}/services/{self.name}/heartbeat",
                    timeout=aiohttp.ClientTimeout(total=2)
                ) as response:
                    if response.status != 200:
                        print(f"⚠️  Heartbeat failed for {self.name}: {response.status}")
        except Exception as e:
            # Silently ignore heartbeat errors in tests
            pass
    
    async def heartbeat_loop(self):
        """Periodic heartbeat to registry"""
        while self.running:
            await self.send_heartbeat()
            await asyncio.sleep(10)  # Heartbeat every 10 seconds
    
    async def chat_completions_handler(self, request):
        """Handle chat completions requests"""
        self.request_count += 1
        
        try:
            data = await request.json()
            model = data.get('model', 'unknown')
            stream = data.get('stream', False)
            messages = data.get('messages', [])
            
            # Check if this service supports the requested model
            if model not in self.models:
                return web.json_response(
                    {"error": {"message": f"Model {model} not available on this service"}},
                    status=400
                )
            
            if stream:
                # Streaming response
                response = web.StreamResponse()
                response.headers['Content-Type'] = 'text/event-stream'
                response.headers['Transfer-Encoding'] = 'chunked'
                await response.prepare(request)
                
                # Send streaming chunks
                content = f"Hello from {self.name} (model: {model})"
                for i, char in enumerate(content):
                    chunk_data = {
                        "id": f"chatcmpl-{self.request_count}",
                        "object": "chat.completion.chunk",
                        "created": int(time.time()),
                        "model": model,
                        "choices": [{
                            "index": 0,
                            "delta": {"content": char},
                            "finish_reason": None
                        }]
                    }
                    await response.write(f"data: {json.dumps(chunk_data)}\n\n".encode())
                    await asyncio.sleep(0.01)  # Small delay to simulate streaming
                
                # Send done chunk
                await response.write(b"data: [DONE]\n\n")
                await response.write_eof()
                return response
            else:
                # Non-streaming response
                return web.json_response({
                    "id": f"chatcmpl-{self.request_count}",
                    "object": "chat.completion",
                    "created": int(time.time()),
                    "model": model,
                    "choices": [{
                        "index": 0,
                        "message": {
                            "role": "assistant",
                            "content": f"Hello from {self.name} (model: {model})"
                        },
                        "finish_reason": "stop"
                    }],
                    "usage": {
                        "prompt_tokens": 10,
                        "completion_tokens": 5,
                        "total_tokens": 15
                    }
                })
        except Exception as e:
            return web.json_response(
                {"error": {"message": str(e)}},
                status=500
            )
    
    async def models_handler(self, request):
        """Handle models list request"""
        return web.json_response({
            "object": "list",
            "data": [
                {"id": model, "object": "model", "created": int(time.time())}
                for model in self.models
            ]
        })
    
    async def health_handler(self, request):
        """Health check endpoint (babysitter)"""
        return web.json_response({
            "status": "healthy",
            "service": self.name,
            "port": self.port,
            "requests": self.request_count
        })
    
    async def start(self):
        """Start the mock service"""
        logger.info(f"Starting {self.name}...")
        print(f"[{self.name}] Starting service...", flush=True)
        sys.stdout.flush()
        
        # Register with registry
        if self.registry_url:
            logger.info(f"Registering with registry: {self.registry_url}")
            print(f"[{self.name}] Registering with registry: {self.registry_url}", flush=True)
            await self.register_with_registry()
            # Start heartbeat loop
            asyncio.create_task(self.heartbeat_loop())
        
        # Start babysitter server
        logger.info(f"Starting babysitter endpoint on port {self.babysitter_port}")
        print(f"[{self.name}] Starting babysitter endpoint on port {self.babysitter_port}", flush=True)
        babysitter_app = web.Application()
        babysitter_app.router.add_get('/health', self.health_handler)
        babysitter_runner = web.AppRunner(babysitter_app)
        await babysitter_runner.setup()
        babysitter_site = web.TCPSite(babysitter_runner, '127.0.0.1', self.babysitter_port)
        await babysitter_site.start()
        logger.info(f"Babysitter endpoint started on port {self.babysitter_port}")
        print(f"[{self.name}] ✅ Babysitter endpoint started on port {self.babysitter_port}", flush=True)
        
        # Start main service
        logger.info(f"Starting main service on port {self.port}")
        print(f"[{self.name}] Starting main service on port {self.port}", flush=True)
        runner = web.AppRunner(self.app)
        await runner.setup()
        site = web.TCPSite(runner, '127.0.0.1', self.port)
        await site.start()
        logger.info(f"Main service started on port {self.port}")
        print(f"[{self.name}] ✅ Main service started on port {self.port}", flush=True)
        
        self.running = True
        logger.info(f"✅ {self.name} fully started on port {self.port} (babysitter: {self.babysitter_port})")
        logger.info(f"   Models: {', '.join(self.models)}")
        print(f"✅ {self.name} started on port {self.port} (babysitter: {self.babysitter_port})", flush=True)
        print(f"   Models: {', '.join(self.models)}", flush=True)
        sys.stdout.flush()
        
        # Keep running
        try:
            while self.running:
                await asyncio.sleep(1)
        except KeyboardInterrupt:
            logger.info("Received keyboard interrupt")
            print(f"[{self.name}] Received keyboard interrupt", flush=True)
        finally:
            logger.info("Cleaning up...")
            print(f"[{self.name}] Cleaning up...", flush=True)
            await runner.cleanup()
            await babysitter_runner.cleanup()

def main():
    parser = argparse.ArgumentParser(description='Mock service for integration testing')
    parser.add_argument('--name', required=True, help='Service name')
    parser.add_argument('--port', type=int, required=True, help='Service port')
    parser.add_argument('--models', required=True, help='Comma-separated list of models')
    parser.add_argument('--registry-url', help='Registry URL for registration')
    
    args = parser.parse_args()
    
    logger.info(f"Mock service starting with args: name={args.name}, port={args.port}, models={args.models}, registry_url={args.registry_url}")
    print(f"[MOCK_SERVICE] Starting with args: name={args.name}, port={args.port}, models={args.models}", flush=True)
    sys.stdout.flush()
    
    models = [m.strip() for m in args.models.split(',')]
    
    service = MockService(
        name=args.name,
        port=args.port,
        models=models,
        registry_url=args.registry_url
    )
    
    # Handle shutdown
    def signal_handler(sig, frame):
        logger.info(f"Received signal {sig}, shutting down...")
        print(f"\n🛑 Shutting down {service.name}...", flush=True)
        service.running = False
        sys.exit(0)
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    try:
        logger.info("Entering asyncio.run()")
        print(f"[{service.name}] Entering event loop...", flush=True)
        asyncio.run(service.start())
    except KeyboardInterrupt:
        logger.info("KeyboardInterrupt caught")
        service.running = False
    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        print(f"[{service.name}] ❌ Fatal error: {e}", flush=True)
        raise

if __name__ == '__main__':
    main()
