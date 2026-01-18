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
            return
            
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
                    if response.status == 201:
                        print(f"✅ {self.name} registered with registry")
                        return True
                    else:
                        text = await response.text()
                        print(f"⚠️  Failed to register {self.name}: {response.status} - {text}")
                        return False
        except Exception as e:
            print(f"⚠️  Error registering {self.name}: {e}")
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
        # Register with registry
        if self.registry_url:
            await self.register_with_registry()
            # Start heartbeat loop
            asyncio.create_task(self.heartbeat_loop())
        
        # Start babysitter server
        babysitter_runner = web.AppRunner(web.Application())
        babysitter_app = web.Application()
        babysitter_app.router.add_get('/health', self.health_handler)
        babysitter_runner = web.AppRunner(babysitter_app)
        await babysitter_runner.setup()
        babysitter_site = web.TCPSite(babysitter_runner, '127.0.0.1', self.babysitter_port)
        await babysitter_site.start()
        
        # Start main service
        runner = web.AppRunner(self.app)
        await runner.setup()
        site = web.TCPSite(runner, '127.0.0.1', self.port)
        await site.start()
        
        self.running = True
        print(f"✅ {self.name} started on port {self.port} (babysitter: {self.babysitter_port})")
        print(f"   Models: {', '.join(self.models)}")
        
        # Keep running
        try:
            while self.running:
                await asyncio.sleep(1)
        except KeyboardInterrupt:
            pass
        finally:
            await runner.cleanup()
            await babysitter_runner.cleanup()

def main():
    parser = argparse.ArgumentParser(description='Mock service for integration testing')
    parser.add_argument('--name', required=True, help='Service name')
    parser.add_argument('--port', type=int, required=True, help='Service port')
    parser.add_argument('--models', required=True, help='Comma-separated list of models')
    parser.add_argument('--registry-url', help='Registry URL for registration')
    
    args = parser.parse_args()
    
    models = [m.strip() for m in args.models.split(',')]
    
    service = MockService(
        name=args.name,
        port=args.port,
        models=models,
        registry_url=args.registry_url
    )
    
    # Handle shutdown
    def signal_handler(sig, frame):
        print(f"\n🛑 Shutting down {service.name}...")
        service.running = False
        sys.exit(0)
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    try:
        asyncio.run(service.start())
    except KeyboardInterrupt:
        service.running = False

if __name__ == '__main__':
    main()
