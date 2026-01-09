#!/usr/bin/env python3
"""
Enhanced Babysitter script for InfiniLM service with Registry and Router integration
Automatically restarts the service when it crashes and manages registry registration
"""

import subprocess
import time
import signal
import sys
import os
import logging
import threading
import asyncio
import aiohttp
from aiohttp import web
import json
from datetime import datetime
from pathlib import Path
from typing import Optional, List, Dict

# Import our registry and router clients
from registry_client import RegistryClient, ServiceInfo
from router_client import RouterClient

log_file = f"enhanced_babysitter_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(log_file),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

class EnhancedServiceBabysitter:
    def __init__(self, config_file, host, port, service_name=None,
                 registry_url=None, router_url=None,
                 max_restarts=10, restart_delay=5, heartbeat_interval=30,
                 service_type="InfiniLM", infinilm_server_args=None):
        self.config_file = config_file
        self.host = host
        self.port = port
        self.service_type = service_type  # "InfiniLM" or "InfiniLM-Rust"
        self.infinilm_server_args = infinilm_server_args or {}  # Arguments for InfiniLM Python server
        self.service_name = service_name or f"infinilm-{service_type.lower().replace(' ', '-')}-{port}"
        self.registry_url = registry_url
        self.router_url = router_url
        self.max_restarts = max_restarts
        self.restart_delay = restart_delay
        self.heartbeat_interval = heartbeat_interval
        self.restart_count = 0
        self.process = None
        self.running = True
        self.heartbeat_thread = None
        self.service_port = None  # Will be set when InfiniLM server starts
        self.web_app = None
        self.web_runner = None
        # Unified rule: InfiniLM server always uses the specified port, babysitter uses port+1
        self.service_target_port = port  # Port that InfiniLM server should use (the user-specified port)
        self.babysitter_port = port + 1  # Port for babysitter's HTTP server (always port+1 to avoid conflict)

        # Initialize clients only if URLs are provided
        if registry_url:
            self.registry_client = RegistryClient(registry_url)
        else:
            self.registry_client = None
        if router_url:
            self.router_client = RouterClient(router_url)
        else:
            self.router_client = None

        # Service info
        self.service_info = ServiceInfo(
            name=self.service_name,
            host=self.host,
            port=self.babysitter_port,
            url=f"http://{self.host}:{self.babysitter_port}",
            status="running",
            metadata={
                "type": service_type,
                "config_file": config_file,
                "babysitter": "enhanced",
                "started_at": datetime.now().isoformat()
            }
        )

        # Setup signal handlers for graceful shutdown
        signal.signal(signal.SIGINT, self.signal_handler)
        signal.signal(signal.SIGTERM, self.signal_handler)

        # Setup HTTP server
        self.setup_web_server()

    def signal_handler(self, signum, frame):
        """Handle shutdown signals gracefully"""
        logger.info(f"Received signal {signum}, shutting down gracefully...")
        self.running = False

        # Stop heartbeat thread
        if self.heartbeat_thread and self.heartbeat_thread.is_alive():
            logger.info("Stopping heartbeat thread...")
            # The thread will stop when self.running becomes False

        # Unregister from registry
        self.unregister_from_registry()

        # Terminate service process
        if self.process:
            logger.info("Terminating service process...")
            self.process.terminate()
            try:
                self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                logger.warning("Service didn't terminate gracefully, forcing kill...")
                self.process.kill()

    def setup_web_server(self):
        """Setup HTTP server with service management endpoints only"""
        self.web_app = web.Application()
        self.web_app.router.add_get('/health', self.health_handler)
        self.web_app.router.add_get('/models', self.models_handler)
        self.web_app.router.add_get('/info', self.info_handler)
        # Remove the catch-all proxy handler - babysitter doesn't proxy OpenAI requests

    async def health_handler(self, request):
        """Health check endpoint"""
        return web.json_response({
            "status": "healthy",
            "service": self.service_name,
            "babysitter": "enhanced",
            "infinilm_server_running": self.process is not None and self.process.poll() is None,
            "infinilm_server_port": self.service_port,
            "timestamp": time.time()
        })

    async def models_handler(self, request):
        """Models endpoint - proxy to InfiniLM server"""
        if not self.service_port:
            return web.json_response({"error": "InfiniLM server not ready"}, status=503)

        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(f"http://localhost:{self.service_port}/models") as response:
                    data = await response.json()
                    return web.json_response(data)
        except Exception as e:
            logger.error(f"Error proxying models request: {e}")
            return web.json_response({"error": "Service unavailable"}, status=503)

    async def info_handler(self, request):
        """Service info endpoint"""
        return web.json_response({
            "name": self.service_name,
            "host": self.host,
            "port": self.babysitter_port,
            "url": f"http://{self.host}:{self.babysitter_port}",
            "metadata": self.service_info.metadata,
            "infinilm_server_port": self.service_port,
            "uptime": time.time() - getattr(self, 'start_time', time.time())
        })


    async def start_web_server(self):
        """Start the HTTP server"""
        self.web_runner = web.AppRunner(self.web_app)
        await self.web_runner.setup()
        site = web.TCPSite(self.web_runner, '0.0.0.0', self.babysitter_port)
        await site.start()
        logger.info(f"HTTP server started on port {self.babysitter_port}")

    async def stop_web_server(self):
        """Stop the HTTP server"""
        if self.web_runner:
            await self.web_runner.cleanup()
            logger.info("HTTP server stopped")

    def detect_service_port(self) -> Optional[int]:
        """Detect the port that InfiniLM server is running on by parsing logs"""
        if not self.process:
            return None

        # Wait for InfiniLM server to start and parse logs
        for _ in range(30):  # Wait up to 30 seconds
            if self.process.poll() is not None:
                return None  # Process died

            # Check if we can find the port in the logs
            try:
                # Try to read from stdout (non-blocking)
                import select
                if select.select([self.process.stdout], [], [], 0.1)[0]:
                    line = self.process.stdout.readline()
                    if line:
                        logger.info(f"Service log: {line.strip()}")
                        # Look for port patterns in the logs
                        import re
                        # Look for patterns like "start service at 0.0.0.0:5003"
                        port_match = re.search(r'start service at [^:]+:(\d+)', line)
                        if port_match:
                            port = int(port_match.group(1))
                            logger.info(f"Found InfiniLM server port: {port}")
                            return port
            except Exception as e:
                logger.debug(f"Error reading process output: {e}")
                pass

            time.sleep(1)

        # If we can't detect the port from logs, assume it's using the target port
        logger.warning(f"Could not detect InfiniLM server port from logs, assuming it's using target port {self.service_target_port}")
        return self.service_target_port

    def detect_infinilm_service_port(self) -> Optional[int]:
        """Detect when InfiniLM (Python) server is actually ready by checking if port is listening and HTTP server responds"""
        if not self.process:
            return None

        import socket
        import requests

        target_port = self.port
        target_host = self.host if self.host != 'localhost' else '127.0.0.1'
        check_url = f"http://{self.host}:{target_port}/models"

        logger.info(f"Waiting for InfiniLM server to be ready on port {target_port}...")

        # Wait up to 120 seconds for the server to be ready (model loading can take time)
        for attempt in range(120):
            # Check if process died
            if self.process.poll() is not None:
                logger.error("InfiniLM server process died during startup")
                return None

            # First check if port is listening
            port_listening = False
            try:
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(1)
                result = sock.connect_ex((target_host, target_port))
                sock.close()
                port_listening = (result == 0)
            except Exception as e:
                logger.debug(f"Port check error: {e}")
                port_listening = False

            if port_listening:
                # Port is listening, now check if HTTP server responds
                try:
                    response = requests.get(check_url, timeout=(2, 5))
                    if response.status_code == 200:
                        logger.info(f"InfiniLM server is ready! Port {target_port} is listening and responding to HTTP requests")
                        return target_port
                    elif response.status_code == 503:
                        # Server is starting but not ready yet (model loading)
                        logger.debug(f"Server is starting (HTTP 503), waiting... (attempt {attempt + 1}/120)")
                    elif response.status_code in (502, 504):
                        # Bad gateway or timeout - server might still be starting
                        logger.debug(f"Server not fully ready yet (HTTP {response.status_code}), waiting... (attempt {attempt + 1}/120)")
                    else:
                        logger.debug(f"Unexpected HTTP status {response.status_code}, waiting... (attempt {attempt + 1}/120)")
                except requests.exceptions.ConnectionError:
                    # Connection refused - port might not be fully ready yet
                    logger.debug(f"Connection refused, waiting for server... (attempt {attempt + 1}/120)")
                except requests.exceptions.Timeout:
                    # Timeout - server might be slow to respond
                    logger.debug(f"Request timeout, server might be busy... (attempt {attempt + 1}/120)")
                except Exception as e:
                    logger.debug(f"Error checking HTTP endpoint: {e}")

            # Log progress every 10 seconds
            if attempt > 0 and attempt % 10 == 0:
                elapsed = attempt
                logger.info(f"Still waiting for InfiniLM server to be ready... ({elapsed}s elapsed)")

            time.sleep(1)

        logger.warning(f"InfiniLM server did not become ready within 120 seconds on port {target_port}")
        return None

    def register_with_registry(self) -> bool:
        """Register this babysitter service with the registry"""
        if not self.registry_client:
            return False
        logger.info(f"Registering babysitter '{self.service_name}' with registry...")
        return self.registry_client.register_service(self.service_info)

    def fetch_models_from_server(self, max_retries=1000, retry_delay=2) -> List[Dict]:
        """Fetch model list from InfiniLM server with retry logic"""
        if not self.service_port:
            logger.warning("Cannot fetch models: service port not detected")
            return []

        import requests
        import socket

        # Use self.host instead of hardcoded localhost for consistency
        url = f"http://{self.host}:{self.service_port}/models"

        # First, wait a bit longer and verify the port is actually listening
        # This helps avoid premature connection attempts when server is still starting
        logger.debug(f"Waiting for server on {self.host}:{self.service_port} to be ready...")
        initial_wait = 10  # Wait 10 seconds before first attempt (model loading takes time)

        # Check if port is listening before making HTTP requests
        for check_attempt in range(initial_wait):
            try:
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(1)
                result = sock.connect_ex((self.host if self.host != 'localhost' else '127.0.0.1', self.service_port))
                sock.close()
                if result == 0:
                    logger.debug(f"Port {self.service_port} is listening, server may be ready")
                    break
            except Exception as e:
                logger.debug(f"Port check error: {e}")
            time.sleep(1)

        # Additional wait after port is listening to ensure HTTP server is fully ready
        time.sleep(3)

        # Log progress every N attempts to avoid spam
        log_interval = 30  # Log every 30 attempts (60 seconds with 2s delay)
        last_log_attempt = -log_interval  # Initialize to negative so first attempt (0) will log

        for attempt in range(max_retries):
            try:
                # Use a shorter timeout for connection to detect unresponsive servers quickly
                # Create a completely new connection each retry - don't reuse connections
                # This ensures we're not hitting stale/broken connections from previous attempts
                from requests.adapters import HTTPAdapter

                # Create a NEW session for EACH attempt to ensure fresh connection
                # This prevents reuse of potentially broken/stale connections
                session = requests.Session()

                # Configure adapter to minimize connection reuse
                # Use very small pool so connections aren't reused across retries
                adapter = HTTPAdapter(
                    pool_connections=1,  # Only 1 connection pool
                    pool_maxsize=1,      # Max 1 connection in pool
                    max_retries=0,       # No automatic retries
                    pool_block=False     # Don't block waiting for pool
                )
                session.mount('http://', adapter)
                session.mount('https://', adapter)

                # Force connection close after request
                session.headers.update({'Connection': 'close'})

                response = session.get(
                    url,
                    timeout=(5, 10),  # (connect timeout, read timeout)
                    allow_redirects=False  # Don't follow redirects
                )

                # CRITICAL: Close session immediately after each request
                # This forces the connection to be closed and not reused in next retry
                session.close()
                if response.status_code == 200:
                    data = response.json()
                    # Extract model list from OpenAI API format: {"data": [{"id": "...", ...}, ...]}
                    if isinstance(data, dict) and "data" in data:
                        models = data["data"]
                        model_ids = [model.get("id") for model in models if isinstance(model, dict) and "id" in model]
                        if models:
                            logger.info(f"Fetched {len(model_ids)} models from InfiniLM server: {model_ids}")
                            return models
                        else:
                            logger.debug(f"Models endpoint returned empty list (attempt {attempt + 1}/{max_retries})")
                    elif isinstance(data, list):
                        model_ids = [model.get("id") for model in data if isinstance(model, dict) and "id" in model]
                        if model_ids:
                            logger.info(f"Fetched {len(model_ids)} models from InfiniLM server: {model_ids}")
                            return data
                        else:
                            logger.debug(f"Models endpoint returned empty list (attempt {attempt + 1}/{max_retries})")
                    else:
                        logger.warning(f"Unexpected models response format: {data}")
                        return []
                elif response.status_code in (502, 503):
                    # Service not ready yet (502 = Bad Gateway, 503 = Service Unavailable), retry silently
                    # Only log periodically to avoid spam, but log details on first attempt or periodically
                    should_log = (attempt - last_log_attempt >= log_interval) or (attempt == 0)
                    if should_log:
                        elapsed = attempt * retry_delay
                        # Try to get more info from response - be very careful with error handling
                        error_detail = ""
                        response_text = ""
                        try:
                            if hasattr(response, 'text'):
                                response_text = str(response.text)[:200]  # First 200 chars
                                try:
                                    error_data = response.json()
                                    if isinstance(error_data, dict):
                                        if "error" in error_data:
                                            error_detail = f" - error: {error_data['error']}"
                                        elif "detail" in error_data:
                                            error_detail = f" - detail: {error_data['detail']}"
                                    else:
                                        error_detail = f" - response: {str(error_data)[:100]}"
                                except (ValueError, AttributeError):
                                    # Not JSON, use raw text
                                    if response_text:
                                        error_detail = f" - body: {response_text[:100]}"
                            else:
                                error_detail = " - (no response body available)"
                        except Exception as e:
                            error_detail = f" - (error reading response: {type(e).__name__})"

                        # Always include response info in log
                        headers_info = ""
                        try:
                            if hasattr(response, 'headers'):
                                headers_info = f", headers: {dict(response.headers)}"
                        except:
                            pass

                        # Log with more detail
                        logger.info(f"Waiting for InfiniLM server to be ready... (attempt {attempt + 1}/{max_retries}, {elapsed}s elapsed, HTTP {response.status_code}{error_detail}{headers_info})")
                        if attempt == 0 and response.status_code == 502:
                            # On first 502, also log at warning level to ensure visibility
                            logger.warning(f"502 Bad Gateway on first attempt - URL: {url}, Response: {response_text[:500] if response_text else 'N/A'}")
                        last_log_attempt = attempt
                    if attempt < max_retries - 1:
                        time.sleep(retry_delay)
                        continue
                else:
                    # Unexpected status code - log warning but continue retrying
                    if attempt - last_log_attempt >= log_interval:
                        logger.warning(f"Unexpected HTTP status {response.status_code} when fetching models (attempt {attempt + 1}/{max_retries})")
                        last_log_attempt = attempt
                    if attempt < max_retries - 1:
                        time.sleep(retry_delay)
                        continue
            except requests.exceptions.Timeout:
                # Timeout - server might be busy or slow, retry silently
                if attempt - last_log_attempt >= log_interval:
                    elapsed = attempt * retry_delay
                    logger.info(f"Request timeout waiting for InfiniLM server... (attempt {attempt + 1}/{max_retries}, {elapsed}s elapsed)")
                    last_log_attempt = attempt
                if attempt < max_retries - 1:
                    time.sleep(retry_delay)
                    continue
            except requests.exceptions.ConnectionError:
                # Connection error - service not ready yet, retry silently
                # Only log periodically to avoid spam
                if attempt - last_log_attempt >= log_interval:
                    elapsed = attempt * retry_delay
                    logger.info(f"Waiting for InfiniLM server connection... (attempt {attempt + 1}/{max_retries}, {elapsed}s elapsed)")
                    last_log_attempt = attempt
                if attempt < max_retries - 1:
                    time.sleep(retry_delay)
                    continue
            except Exception as e:
                # Unexpected error - log warning but continue retrying
                if attempt - last_log_attempt >= log_interval:
                    logger.warning(f"Error fetching models (attempt {attempt + 1}/{max_retries}): {e}")
                    last_log_attempt = attempt
                if attempt < max_retries - 1:
                    time.sleep(retry_delay)
                    continue

        # Final failure after all retries
        total_time = max_retries * retry_delay
        logger.warning(f"Failed to fetch models from server after {max_retries} attempts (~{total_time}s). Service will be registered without model information.")
        return []

    def register_service_with_registry(self) -> bool:
        """Register InfiniLM server with the registry"""
        if not self.registry_client:
            return False
        if not self.service_port:
            logger.warning("Cannot register InfiniLM server: port not detected")
            return False

        # Fetch models from the server
        models = self.fetch_models_from_server()

        # Extract model IDs for easier tracking
        model_ids = []
        if models:
            for model in models:
                if isinstance(model, dict) and "id" in model:
                    model_ids.append(model["id"])

        metadata = {
            "type": "openai-api",
            "parent_service": self.service_name,
            "babysitter": "enhanced",
            "started_at": datetime.now().isoformat()
        }

        # Add models to metadata if available
        if model_ids:
            metadata["models"] = model_ids
            metadata["models_list"] = models  # Full model info for router aggregation
            logger.info(f"Registering service with {len(model_ids)} models: {model_ids}")

        infinilm_server_info = ServiceInfo(
            name=f"{self.service_name}-server",
            host=self.host,
            port=self.service_port,
            url=f"http://{self.host}:{self.service_port}",
            status="running",
            metadata=metadata
        )

        logger.info(f"Registering InfiniLM server '{infinilm_server_info.name}' with registry...")
        return self.registry_client.register_service(infinilm_server_info)

    def unregister_from_registry(self) -> bool:
        """Unregister both babysitter and InfiniLM server from the registry"""
        if not self.registry_client:
            return True  # No registry, nothing to unregister

        success = True

        # Unregister babysitter
        logger.info(f"Unregistering babysitter '{self.service_name}' from registry...")
        if not self.registry_client.unregister_service(self.service_name):
            success = False

        # Unregister InfiniLM server if port was detected
        if self.service_port:
            server_name = f"{self.service_name}-server"
            logger.info(f"Unregistering InfiniLM server '{server_name}' from registry...")
            if not self.registry_client.unregister_service(server_name):
                success = False

        return success

    def heartbeat_loop(self):
        """Periodic heartbeat loop"""
        if not self.registry_client:
            logger.info("No registry configured, skipping heartbeat loop")
            return

        logger.info("Starting heartbeat loop...")
        server_registered = False  # Track if server has been successfully registered

        while self.running:
            try:
                if self.process and self.process.poll() is None:
                    # Service is running, send heartbeat for babysitter (always registered)
                    try:
                        self.registry_client.send_heartbeat(self.service_name)
                    except Exception as e:
                        logger.warning(f"Heartbeat failed for babysitter '{self.service_name}': {e}")

                    # Only send heartbeat for InfiniLM server if it's been registered
                    # Check if server is registered by trying to send heartbeat
                    # If it fails with "not found", mark as not registered yet
                    if self.service_port:
                        server_name = f"{self.service_name}-server"
                        try:
                            self.registry_client.send_heartbeat(server_name)
                            if not server_registered:
                                server_registered = True
                                logger.info(f"Server '{server_name}' is now registered, heartbeats will continue")
                        except Exception as e:
                            error_msg = str(e)
                            # Only log warning if we previously thought it was registered
                            # or if it's been a while (to avoid spam during initial startup)
                            if server_registered or "not found" not in error_msg.lower():
                                logger.warning(f"Heartbeat failed: {e}")
                            # If it's "not found", it's expected during initial startup
                            server_registered = False
                else:
                    # Service is not running, don't send heartbeat
                    logger.debug("Service not running, skipping heartbeat")
                    server_registered = False  # Reset registration status

                # Wait for next heartbeat
                for _ in range(self.heartbeat_interval):
                    if not self.running:
                        break
                    time.sleep(1)

            except Exception as e:
                logger.error(f"Error in heartbeat loop: {e}")
                time.sleep(5)  # Wait a bit before retrying

        logger.info("Heartbeat loop stopped")

    def start_service(self):
        """Start the InfiniLM service (InfiniLM or InfiniLM-Rust)"""
        try:
            if self.service_type == "InfiniLM-Rust":
                return self._start_rust_service()
            elif self.service_type == "InfiniLM":
                return self._start_infinilm_service()
            else:
                logger.error(f"Unknown service type: {self.service_type}")
                return False
        except Exception as e:
            logger.error(f"Failed to start service: {e}")
            return False

    def _start_rust_service(self):
        """Start the InfiniLM-Rust service"""
        # Find the InfiniLM-Rust repository directory
        possible_paths = [
            Path(__file__).parent.parent / "InfiniLM-Rust",
            Path("/home/zenghua/repos/InfiniLM-Rust"),
            Path("InfiniLM-Rust"),
        ]

        repo_dir = None
        for path in possible_paths:
            if path.exists():
                repo_dir = path
                break

        if repo_dir is None:
            logger.error("Could not find InfiniLM-Rust repository directory")
            return False

        # Build the cargo command
        cmd = [
            "cargo",
            "service", self.config_file,
            "-p", str(self.service_target_port)
        ]

        logger.info(f"Starting InfiniLM-Rust service with command: {' '.join(cmd)}")
        logger.info(f"Working directory: {repo_dir}")

        # Start the process with proper environment
        env = os.environ.copy()
        # Source cargo environment
        cargo_env_path = os.path.expanduser("~/.cargo/env")
        if os.path.exists(cargo_env_path):
            # Add cargo bin to PATH
            cargo_bin = os.path.expanduser("~/.cargo/bin")
            if cargo_bin not in env.get("PATH", ""):
                env["PATH"] = f"{cargo_bin}:{env.get('PATH', '')}"

        self.process = subprocess.Popen(
            cmd,
            cwd=repo_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
            bufsize=1,
            env=env
        )

        logger.info(f"InfiniLM-Rust service started with PID: {self.process.pid}")

        # Wait for InfiniLM server to start and detect port
        self.service_port = self.detect_service_port()
        if self.service_port:
            logger.info(f"✅ Detected InfiniLM server running on port {self.service_port}")
        else:
            logger.warning("⚠️ Could not detect InfiniLM server port")

        # Register babysitter with registry
        if self.register_with_registry():
            logger.info("✅ Babysitter registered with registry")
        else:
            logger.warning("⚠️ Failed to register babysitter with registry, but continuing...")

        # Register InfiniLM server with registry
        if self.register_service_with_registry():
            logger.info("✅ InfiniLM server registered with registry")
        else:
            logger.warning("⚠️ Failed to register InfiniLM server with registry, but continuing...")

        return True

    def _start_infinilm_service(self):
        """Start the InfiniLM Python service"""
        # Check if launch_script_path is specified in infinilm_server_args
        launch_script = None
        if self.infinilm_server_args and "launch_script_path" in self.infinilm_server_args:
            specified_path = Path(self.infinilm_server_args["launch_script_path"])
            if specified_path.exists():
                launch_script = specified_path
                logger.info(f"Using specified launch script: {launch_script}")
            else:
                logger.error(f"Specified launch script path does not exist: {specified_path}")
                return False
        else:
            # Find the launch_server.py script - try common locations
            possible_paths = [
                Path("/workspace/InfiniLM/scripts/launch_server.py"),
                Path(__file__).parent.parent / "InfiniLM" / "scripts" / "launch_server.py",
                Path("/home/zenghua/repos/InfiniLM/scripts/launch_server.py"),
                Path("InfiniLM/scripts/launch_server.py"),
            ]

            for path in possible_paths:
                if path.exists():
                    launch_script = path
                    logger.info(f"Found launch script at: {launch_script}")
                    break

            if launch_script is None:
                logger.error("Could not find launch_server.py. Please specify --launch-script or set launch_script_path in infinilm_server_args.")
                return False

        # Build the Python command
        cmd = [
            "python3",
            str(launch_script),
            "--port", str(self.port),
            "--host", self.host,
        ]

        # Add InfiniLM server arguments from infinilm_server_args
        for key, value in self.infinilm_server_args.items():
            if key.startswith("--"):
                arg = key
            else:
                arg = f"--{key.replace('_', '-')}"

            if value is True:
                cmd.append(arg)
            elif value is False:
                continue  # Skip False flags
            elif value is not None:
                # Special handling for model_name -> model-name
                if key == "model_name":
                    cmd.extend(["--model-name", str(value)])
                else:
                    cmd.extend([arg, str(value)])

        logger.info(f"Starting InfiniLM service with command: {' '.join(cmd)}")
        logger.info(f"Working directory: {launch_script.parent.parent}")

        # Start the process
        env = os.environ.copy()
        self.process = subprocess.Popen(
            cmd,
            cwd=launch_script.parent.parent,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
            bufsize=1,
            env=env
        )

        logger.info(f"InfiniLM service started with PID: {self.process.pid}")

        # For InfiniLM service, the port is directly specified
        # But we need to detect when it's actually ready (listening and responding)
        self.service_port = self.detect_infinilm_service_port()

        if self.service_port:
            logger.info(f"✅ InfiniLM server detected and ready on port {self.service_port}")
        else:
            logger.warning(f"⚠️ Could not detect InfiniLM server on port {self.port}, but continuing...")
            self.service_port = self.port  # Fallback to target port

        # Register babysitter with registry
        if self.register_with_registry():
            logger.info("✅ Babysitter registered with registry")
        else:
            logger.warning("⚠️ Failed to register babysitter with registry, but continuing...")

        # Register InfiniLM server with registry (this will fetch models with retry logic)
        # The register_service_with_registry will handle waiting for the server to be ready
        if self.register_service_with_registry():
            logger.info("✅ InfiniLM server registered with registry")
        else:
            logger.warning("⚠️ Failed to register InfiniLM server with registry, but continuing...")

        return True

    def check_service_health(self) -> bool:
        """Check if the service is responding to health checks"""
        try:
            # Use aiohttp for async health check (but this is a sync method, so we'll use a simple approach)
            import urllib.request
            with urllib.request.urlopen(f"http://{self.host}:{self.port}/health", timeout=5) as response:
                return response.status == 200
        except:
            return False

    def monitor_service(self):
        """Monitor the service process and restart if needed"""
        while self.running:
            if self.process is None:
                if not self.start_service():
                    logger.error("Failed to start service, waiting before retry...")
                    time.sleep(self.restart_delay)
                    continue

            # Check if process is still running
            if self.process.poll() is not None:
                exit_code = self.process.returncode
                logger.warning(f"Service process exited with code: {exit_code}")

                # Read any remaining output
                if self.process.stdout:
                    output = self.process.stdout.read()
                    if output:
                        logger.info(f"Service output: {output}")

                self.restart_count += 1

                if self.restart_count > self.max_restarts:
                    logger.error(f"Maximum restart attempts ({self.max_restarts}) reached. Giving up.")
                    break

                logger.info(f"Restarting service (attempt {self.restart_count}/{self.max_restarts})...")
                time.sleep(self.restart_delay)
                self.process = None
                continue

            # Read output in real-time
            if self.process.stdout:
                line = self.process.stdout.readline()
                if line:
                    line = line.strip()
                    if line:
                        logger.info(f"Service: {line}")

            time.sleep(0.1)  # Small delay to prevent busy waiting

    async def run(self):
        """Main run loop"""
        logger.info("Starting Enhanced InfiniLM service babysitter...")
        logger.info(f"Service name: {self.service_name}")
        logger.info(f"Config file: {self.config_file}")
        logger.info(f"Service type: {self.service_type}")
        logger.info(f"Host: {self.host}")
        logger.info(f"Port: {self.port}")
        logger.info(f"Registry URL: {self.registry_url}")
        logger.info(f"Router URL: {self.router_url}")
        logger.info(f"Max restarts: {self.max_restarts}")
        logger.info(f"Restart delay: {self.restart_delay}s")
        logger.info(f"Heartbeat interval: {self.heartbeat_interval}s")

        # Set start time
        self.start_time = time.time()

        # Check registry and router connectivity (only if configured)
        if self.registry_client:
            if not self.registry_client.check_registry_health():
                logger.warning("⚠️ Registry is not healthy, but continuing...")
        else:
            logger.info("ℹ️  Registry not configured, skipping registration")

        if self.router_client:
            if not self.router_client.check_router_health():
                logger.warning("⚠️ Router is not healthy, but continuing...")
        else:
            logger.info("ℹ️  Router not configured, skipping router checks")

        # Start HTTP server
        await self.start_web_server()

        # Start heartbeat thread
        self.heartbeat_thread = threading.Thread(target=self.heartbeat_loop, daemon=True)
        self.heartbeat_thread.start()

        try:
            # Start service monitoring in a separate thread
            monitor_thread = threading.Thread(target=self.monitor_service, daemon=True)
            monitor_thread.start()

            # Keep the main thread alive
            while self.running:
                await asyncio.sleep(1)

        except KeyboardInterrupt:
            logger.info("Received keyboard interrupt, shutting down...")
        except Exception as e:
            logger.error(f"Unexpected error: {e}")
        finally:
            await self.stop_web_server()
            if self.process:
                logger.info("Cleaning up...")
                self.signal_handler(signal.SIGTERM, None)

        logger.info("Enhanced babysitter stopped.")

def main():
    import argparse

    parser = argparse.ArgumentParser(description="Enhanced Babysitter for InfiniLM service with Registry integration")
    parser.add_argument("--host", default="localhost", help="Host to run the service on (default: localhost)")
    parser.add_argument("-p", "--port", type=int, default=5000, help="Port to run the service on (default: 5000)")
    parser.add_argument("-n", "--name", help="Service name (default: infinilm-{service-type}-{port})")
    parser.add_argument("--registry", default=None, help="Registry URL (default: None, skips registration)")
    parser.add_argument("--router", default=None, help="Router URL (default: None, skips router checks)")
    parser.add_argument("--max-restarts", type=int, default=10, help="Maximum number of restart attempts (default: 10)")
    parser.add_argument("--restart-delay", type=int, default=5, help="Delay between restarts in seconds (default: 5)")
    parser.add_argument("--heartbeat-interval", type=int, default=30, help="Heartbeat interval in seconds (default: 30)")
    parser.add_argument("--service-type", choices=["InfiniLM", "InfiniLM-Rust"], default="InfiniLM",
                       help="Service type: InfiniLM (Python launch_server.py) or InfiniLM-Rust (cargo service) (default: InfiniLM)")
    parser.add_argument("--path", required=True,
                       help="Path: model path for InfiniLM (if service-type=InfiniLM) or config file path for InfiniLM-Rust (if service-type=InfiniLM-Rust)")
    parser.add_argument("--dev", default="nvidia", help="Device type for InfiniLM server (default: nvidia)")
    parser.add_argument("--ndev", type=int, default=1, help="Number of devices for InfiniLM server (default: 1)")
    parser.add_argument("--max-batch", type=int, default=3, help="Max batch size for InfiniLM server (default: 3)")
    parser.add_argument("--max-tokens", type=int, help="Max tokens for InfiniLM server")
    parser.add_argument("--awq", action="store_true", help="Use AWQ quantized model for InfiniLM server")
    parser.add_argument("--request-timeout", type=int, default=300,
                       help="Request timeout in seconds for InfiniLM server (default: 300)")
    parser.add_argument("--launch-script", default=None,
                       help="Path to launch_server.py script (default: auto-detect from common locations)")

    args = parser.parse_args()

    # Build infinilm_server_args if service type is InfiniLM
    infinilm_server_args = {}
    if args.service_type == "InfiniLM":
        # For InfiniLM, --path is the model path
        infinilm_server_args = {
            "model_path": args.path,
            "dev": args.dev,
            "ndev": args.ndev,
            "max_batch": args.max_batch,
            "request_timeout": args.request_timeout,
        }
        if args.launch_script:
            infinilm_server_args["launch_script_path"] = args.launch_script
        if args.max_tokens:
            infinilm_server_args["max_tokens"] = args.max_tokens
        if args.awq:
            infinilm_server_args["awq"] = True
    else:
        # For InfiniLM-Rust, --path is the config file path
        if not os.path.exists(args.path):
            logger.error(f"Config file not found: {args.path}")
            sys.exit(1)

    # Create and run enhanced babysitter
    babysitter = EnhancedServiceBabysitter(
        config_file=args.path if args.service_type == "InfiniLM-Rust" else "N/A",
        host=args.host,
        port=args.port,
        service_name=args.name,
        registry_url=args.registry,
        router_url=args.router,
        max_restarts=args.max_restarts,
        restart_delay=args.restart_delay,
        heartbeat_interval=args.heartbeat_interval,
        service_type=args.service_type,
        infinilm_server_args=infinilm_server_args if args.service_type == "InfiniLM" else None
    )

    asyncio.run(babysitter.run())

if __name__ == "__main__":
    main()
