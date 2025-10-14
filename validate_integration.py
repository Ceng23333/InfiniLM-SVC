#!/usr/bin/env python3
"""
InfiniLM System Integration Validation Pipeline
Comprehensive step-by-step validation of the entire distributed system
"""

import time
import requests
import subprocess
import sys
import json
import logging
from typing import Dict, Any, Optional, List
from pathlib import Path
from openai import OpenAI

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

class IntegrationValidator:
    def __init__(self):
        self.registry_url = "http://localhost:8081"
        self.router_url = "http://localhost:8080"
        self.mock_service_port = 5001
        self.real_service_port = 5002
        self.mock_service_name = "mock-service"
        self.real_service_name = "real-service"
        self.processes = {}

    def print_step(self, step_num: int, title: str):
        """Print step header"""
        print(f"\n{'='*80}")
        print(f"STEP {step_num}: {title}")
        print(f"{'='*80}")

    def print_substep(self, title: str):
        """Print substep header"""
        print(f"\n--- {title} ---")

    def wait_for_service(self, url: str, timeout: int = 30, service_name: str = "service") -> bool:
        """Wait for a service to become available"""
        print(f"⏳ Waiting for {service_name} to start...")
        for i in range(timeout):
            try:
                response = requests.get(url, timeout=5)
                if response.status_code == 200:
                    print(f"✅ {service_name} is ready!")
                    return True
            except requests.exceptions.RequestException:
                pass
            time.sleep(1)
            if i % 5 == 0 and i > 0:
                print(f"   Still waiting... ({i}/{timeout}s)")

        print(f"❌ {service_name} failed to start within {timeout} seconds")
        return False

    def check_http_endpoint(self, url: str, expected_status: int = 200, description: str = "") -> bool:
        """Check HTTP endpoint"""
        try:
            response = requests.get(url, timeout=10)
            if response.status_code == expected_status:
                print(f"✅ {description or url}: {response.status_code}")
                return True
            else:
                print(f"❌ {description or url}: Expected {expected_status}, got {response.status_code}")
                return False
        except requests.exceptions.RequestException as e:
            print(f"❌ {description or url}: Connection failed - {e}")
            return False

    def get_json_response(self, url: str, description: str = "") -> Optional[Dict[str, Any]]:
        """Get JSON response from endpoint"""
        try:
            response = requests.get(url, timeout=10)
            if response.status_code == 200:
                data = response.json()
                print(f"✅ {description or url}: {json.dumps(data, indent=2)}")
                return data
            else:
                print(f"❌ {description or url}: HTTP {response.status_code}")
                return None
        except requests.exceptions.RequestException as e:
            print(f"❌ {description or url}: Connection failed - {e}")
            return None

    def step1_launch_registry(self) -> bool:
        """Step 1: Launch registry and check status"""
        self.print_step(1, "Launch Registry and Check Status")

        # Check if registry is already running
        if self.check_http_endpoint(f"{self.registry_url}/health", description="Registry health check"):
            print("✅ Registry is already running")
            return True

        self.print_substep("Starting Registry")
        try:
            # Start registry using the deployment script
            process = subprocess.Popen([
                "python3", "service_registry.py", "--port", "8081"
            ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            self.processes['registry'] = process
            print(f"🚀 Registry started with PID: {process.pid}")

            # Wait for registry to be ready
            if not self.wait_for_service(f"{self.registry_url}/health", service_name="Registry"):
                return False

            # Verify registry endpoints
            self.print_substep("Verifying Registry Endpoints")

            endpoints = [
                (f"{self.registry_url}/health", "Registry health"),
                (f"{self.registry_url}/services", "Registry services list"),
                (f"{self.registry_url}/stats", "Registry statistics")
            ]

            for url, description in endpoints:
                if not self.check_http_endpoint(url, description=description):
                    return False

            # Get initial registry status
            health_data = self.get_json_response(f"{self.registry_url}/health", "Registry health data")
            if health_data:
                print(f"📊 Registry Status: {health_data.get('registered_services', 0)} services registered")

            return True

        except Exception as e:
            print(f"❌ Failed to start registry: {e}")
            return False

    def step2_launch_router(self) -> bool:
        """Step 2: Launch router and check status"""
        self.print_step(2, "Launch Router and Check Status")

        # Check if router is already running
        if self.check_http_endpoint(f"{self.router_url}/health", description="Router health check"):
            print("✅ Router is already running")
            return True

        self.print_substep("Starting Router")
        try:
            # Start router using the deployment script
            process = subprocess.Popen([
                "python3", "distributed_router.py",
                "--router-port", "8080",
                "--registry-url", self.registry_url
            ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            self.processes['router'] = process
            print(f"🚀 Router started with PID: {process.pid}")

            # Wait for router to be ready
            if not self.wait_for_service(f"{self.router_url}/health", service_name="Router"):
                return False

            # Verify router endpoints
            self.print_substep("Verifying Router Endpoints")

            endpoints = [
                (f"{self.router_url}/health", "Router health"),
                (f"{self.router_url}/stats", "Router statistics")
            ]

            for url, description in endpoints:
                if not self.check_http_endpoint(url, description=description):
                    return False

            # Get initial router status
            stats_data = self.get_json_response(f"{self.router_url}/stats", "Router stats data")
            if stats_data:
                print(f"📊 Router Status: {stats_data.get('total_services', 0)} total services, {stats_data.get('healthy_services', 0)} healthy")

            return True

        except Exception as e:
            print(f"❌ Failed to start router: {e}")
            return False

    def step3_launch_mock_instance(self) -> bool:
        """Step 3: Launch mock instance and check status"""
        self.print_step(3, "Launch Mock Instance and Check Status")

        self.print_substep("Starting Mock Service")
        try:
            # Start mock service
            process = subprocess.Popen([
                "python3", "test_service.py"
            ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            self.processes['mock_service'] = process
            print(f"🚀 Mock service started with PID: {process.pid}")

            # Wait for mock service to be ready
            mock_url = f"http://localhost:{self.mock_service_port}"
            if not self.wait_for_service(f"{mock_url}/health", service_name="Mock Service"):
                return False

            # Verify mock service endpoints
            self.print_substep("Verifying Mock Service Endpoints")

            endpoints = [
                (f"{mock_url}/health", "Mock service health"),
                (f"{mock_url}/models", "Mock service models"),
                (f"{mock_url}/info", "Mock service info")
            ]

            for url, description in endpoints:
                if not self.check_http_endpoint(url, description=description):
                    return False

            # Test mock service functionality
            self.print_substep("Testing Mock Service Functionality")

            # Test models endpoint
            models_data = self.get_json_response(f"{mock_url}/models", "Mock service models")
            if not models_data:
                return False

            # Test chat completions
            try:
                chat_payload = {
                    "model": "test-model-1",  # Mock service uses test-model-1
                    "messages": [{"role": "user", "content": "Hello, this is a test"}]
                }
                response = requests.post(f"{mock_url}/chat/completions", json=chat_payload, timeout=10)
                if response.status_code == 200:
                    chat_data = response.json()
                    print(f"✅ Mock service chat completions: {chat_data.get('choices', [{}])[0].get('message', {}).get('content', '')}")
                else:
                    print(f"❌ Mock service chat completions failed: HTTP {response.status_code}")
                    return False
            except Exception as e:
                print(f"❌ Mock service chat completions error: {e}")
                return False

            return True

        except Exception as e:
            print(f"❌ Failed to start mock service: {e}")
            return False

    def step4_register_mock_instance(self) -> bool:
        """Step 4: Register mock instance and check status"""
        self.print_step(4, "Register Mock Instance and Check Status")

        self.print_substep("Registering Mock Service with Registry")
        try:
            # Register mock service
            service_data = {
                "name": self.mock_service_name,
                "host": "localhost",
                "hostname": "localhost",
                "port": self.mock_service_port,
                "url": f"http://localhost:{self.mock_service_port}",
                "status": "running",
                "metadata": {
                    "type": "openai-api",
                    "test": True,
                    "description": "Mock service for testing OpenAI API"
                }
            }

            response = requests.post(
                f"{self.registry_url}/services",
                json=service_data,
                timeout=10
            )

            if response.status_code == 201:
                print("✅ Mock service registered successfully")
                reg_data = response.json()
                print(f"📋 Registration response: {json.dumps(reg_data, indent=2)}")
            else:
                print(f"❌ Failed to register mock service: HTTP {response.status_code} - {response.text}")
                return False

            # Send heartbeat to make service healthy
            self.print_substep("Sending Heartbeat")
            heartbeat_response = requests.post(
                f"{self.registry_url}/services/{self.mock_service_name}/heartbeat",
                timeout=10
            )

            if heartbeat_response.status_code == 200:
                print("✅ Heartbeat sent successfully")
            else:
                print(f"⚠️ Heartbeat failed: HTTP {heartbeat_response.status_code}")

            # Wait for registry to update
            time.sleep(5)

            # Verify registration
            self.print_substep("Verifying Registration")

            # Check registry services list
            services_data = self.get_json_response(f"{self.registry_url}/services", "Registry services list")
            if not services_data:
                return False

            services = services_data.get('services', [])
            mock_service = next((s for s in services if s['name'] == self.mock_service_name), None)

            if mock_service:
                print(f"✅ Mock service found in registry: {mock_service['name']}")
                print(f"📊 Service status: {mock_service.get('status', 'unknown')}")
                print(f"📊 Health status: {mock_service.get('health_status', 'unknown')}")
                print(f"📊 Is healthy: {mock_service.get('is_healthy', False)}")
            else:
                print("❌ Mock service not found in registry")
                return False

            # Check healthy services
            healthy_data = self.get_json_response(f"{self.registry_url}/services?healthy=true", "Healthy services")
            if healthy_data:
                healthy_services = healthy_data.get('services', [])
                healthy_mock = next((s for s in healthy_services if s['name'] == self.mock_service_name), None)
                if healthy_mock:
                    print("✅ Mock service is healthy")
                else:
                    print("⚠️ Mock service is not healthy yet")

            return True

        except Exception as e:
            print(f"❌ Failed to register mock service: {e}")
            return False

    def step5_launch_real_instance(self) -> bool:
        """Step 5: Launch real instance and check status"""
        self.print_step(5, "Launch Real Instance and Check Status")

        self.print_substep("Starting Real Service (Enhanced Babysitter)")
        try:
            # Check if we're in the right directory for Rust services
            rust_repo_path = Path("/root/zenghua/repos/InfiniLM-Rust")
            if not rust_repo_path.exists():
                print("⚠️ Rust repository not found")
                return False

            # Generate test service configuration using TOML renderer
            self.print_substep("Generating Service Configuration")
            try:
                # Generate service configuration from test_services.json
                result = subprocess.run([
                    "python3", "render_service_config.py", "--config", "test_services.json", "--output", "service_generated.toml"
                ], cwd=Path(__file__).parent, capture_output=True, text=True, timeout=30)

                if result.returncode != 0:
                    print(f"❌ Failed to generate service configuration: {result.stderr}")
                    return False

                # Copy generated config to Rust repo
                generated_config = Path(__file__).parent / "service_generated.toml"
                rust_config = rust_repo_path / "service_generated.toml"

                if generated_config.exists():
                    import shutil
                    shutil.copy2(generated_config, rust_config)
                    print(f"✅ Generated service configuration: {rust_config}")
                else:
                    print("❌ Generated configuration file not found")
                    return False

            except Exception as e:
                print(f"❌ Error generating service configuration: {e}")
                return False

            # Use enhanced babysitter from Rust repo with generated configuration
            process = subprocess.Popen([
                "python3", "/root/zenghua/repos/InfiniLM-Rust/enhanced_babysitter.py",
                "service_generated.toml",
                "--port", str(self.real_service_port),
                "--name", self.real_service_name,
                "--registry", self.registry_url,
                "--router", self.router_url
            ], cwd=rust_repo_path, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            self.processes['real_service'] = process
            print(f"🚀 Real service started with PID: {process.pid}")

            # Wait for real service to be ready (increased timeout for model loading)
            real_url = f"http://localhost:{self.real_service_port}"
            if not self.wait_for_service(f"{real_url}/health", timeout=120, service_name="Real Service"):
                return False

            # Wait for xtask to be ready by checking the models endpoint
            self.print_substep("Waiting for xtask to be ready...")
            if not self.wait_for_service(f"{real_url}/models", timeout=120, service_name="Real Service (xtask)"):
                return False

            # Verify real service endpoints
            self.print_substep("Verifying Real Service Endpoints")

            endpoints = [
                (f"{real_url}/health", "Real service health"),
                (f"{real_url}/models", "Real service models"),
                (f"{real_url}/info", "Real service info")
            ]

            for url, description in endpoints:
                if not self.check_http_endpoint(url, description=description):
                    return False

            # Wait for automatic registration
            time.sleep(10)

            # Verify automatic registration
            self.print_substep("Verifying Automatic Registration")

            services_data = self.get_json_response(f"{self.registry_url}/services", "Registry services list")
            if services_data:
                services = services_data.get('services', [])
                real_service = next((s for s in services if s['name'] == self.real_service_name), None)

                if real_service:
                    print(f"✅ Real service auto-registered: {real_service['name']}")
                    print(f"📊 Service status: {real_service.get('status', 'unknown')}")
                    print(f"📊 Health status: {real_service.get('health_status', 'unknown')}")
                else:
                    print("⚠️ Real service not auto-registered yet")

            return True

        except Exception as e:
            print(f"❌ Failed to start real service: {e}")
            return False

    def step7_deregister_mock_instance(self) -> bool:
        """Step 7: Deregister mock instance and check status"""
        self.print_step(7, "Deregister Mock Instance and Check Status")

        self.print_substep("Deregistering Mock Service")
        try:
            # Deregister mock service
            response = requests.delete(
                f"{self.registry_url}/services/{self.mock_service_name}",
                timeout=10
            )

            if response.status_code == 200:
                print("✅ Mock service deregistered successfully")
            else:
                print(f"❌ Failed to deregister mock service: HTTP {response.status_code} - {response.text}")
                return False

            # Wait for registry to update
            time.sleep(5)

            # Verify deregistration
            self.print_substep("Verifying Deregistration")

            services_data = self.get_json_response(f"{self.registry_url}/services", "Registry services list")
            if services_data:
                services = services_data.get('services', [])
                mock_service = next((s for s in services if s['name'] == self.mock_service_name), None)

                if mock_service:
                    print("❌ Mock service still in registry")
                    return False
                else:
                    print("✅ Mock service successfully removed from registry")

            # Check final system status
            self.print_substep("Final System Status")

            # Registry status
            health_data = self.get_json_response(f"{self.registry_url}/health", "Final registry health")
            if health_data:
                print(f"📊 Registry: {health_data.get('registered_services', 0)} services registered")

            # Router status
            stats_data = self.get_json_response(f"{self.router_url}/stats", "Final router stats")
            if stats_data:
                print(f"📊 Router: {stats_data.get('total_services', 0)} total services, {stats_data.get('healthy_services', 0)} healthy")

            return True

        except Exception as e:
            print(f"❌ Failed to deregister mock service: {e}")
            return False

    def step6_test_router_integration(self) -> bool:
        """Step 6: Test router integration with both mock and real services"""
        self.print_step(6, "Test Router Integration")

        self.print_substep("Testing Router with Both Services")

        # Wait for router to discover both services
        time.sleep(10)

        # Test router health
        router_health = self.get_json_response(f"{self.router_url}/health", "Router health with both services")
        if not router_health:
            return False

        # Test router stats
        router_stats = self.get_json_response(f"{self.router_url}/stats", "Router stats with both services")
        if not router_stats:
            return False

        # Verify router routes to all openai-api services (both mock and xtask)
        total_services = router_stats.get('total_services', 0)
        healthy_services = router_stats.get('healthy_services', 0)
        services = router_stats.get('services', [])

        print(f"📊 Router services: {total_services} total, {healthy_services} healthy")
        print(f"📊 Router routes to all openai-api services (mock and xtask) for round-robin testing")

        # Check that all openai-api services are in the router's backend
        openai_services = [s for s in services if s.get('metadata', {}).get('type') == 'openai-api']
        if len(openai_services) != healthy_services:
            print(f"⚠️ Router should have all openai-api services, but found {len(openai_services)} out of {healthy_services}")

        for service in openai_services:
            service_type = service['metadata'].get('type', 'unknown')
            service_desc = service['metadata'].get('description', '')
            print(f"   - {service['name']} ({service_type}) at {service['url']} - {service_desc}")

        # Verify we have both mock and real services for round-robin testing
        mock_services = [s for s in openai_services if 'mock' in s['name'].lower() or s['metadata'].get('test', False)]
        real_services = [s for s in openai_services if 'xtask' in s['name'].lower()]

        if len(mock_services) > 0 and len(real_services) > 0:
            print(f"✅ Round-robin test setup: {len(mock_services)} mock service(s), {len(real_services)} real service(s)")
        else:
            print(f"⚠️ Round-robin test setup: {len(mock_services)} mock service(s), {len(real_services)} real service(s)")

        # Test models through router
        models_data = self.get_json_response(f"{self.router_url}/models", "Models through router")
        if not models_data:
            return False

        # Test specific round-robin pattern: [non-stream, non-stream, stream, stream]
        # Expected: 1st and 3rd to real service, 2nd and 4th to mock service
        self.print_substep("Testing Specific Round-Robin Pattern")
        try:
            client = OpenAI(
                api_key="dummy-key",  # Dummy key since we're using a local service
                base_url=self.router_url
            )

            print("--- Testing Pattern: [non-stream, non-stream, stream, stream] ---")
            print("Expected: 1st and 3rd to real service, 2nd and 4th to mock service")

            responses = []
            expected_services = ["Real Service", "Mock Service", "Real Service", "Mock Service"]

            # Request 1: Non-streaming (should go to real service)
            print("   Request 1: Non-streaming...")
            response = client.chat.completions.create(
                model="Qwen3-32B",
                messages=[{"role": "user", "content": "Request 1 - non-streaming"}],
                stream=False,
                timeout=30
            )
            if response.choices and len(response.choices) > 0:
                content = response.choices[0].message.content
                actual_service = "Mock Service" if "This is a test response from the mock service" in content else "Real Service"
                responses.append((1, actual_service, content))
                print(f"   Request 1: {actual_service} - {content[:50]}...")
            else:
                print(f"   Request 1: No response")

            # Request 2: Non-streaming (should go to mock service)
            print("   Request 2: Non-streaming...")
            response = client.chat.completions.create(
                model="Qwen3-32B",
                messages=[{"role": "user", "content": "Request 2 - non-streaming"}],
                stream=False,
                timeout=30
            )
            if response.choices and len(response.choices) > 0:
                content = response.choices[0].message.content
                actual_service = "Mock Service" if "This is a test response from the mock service" in content else "Real Service"
                responses.append((2, actual_service, content))
                print(f"   Request 2: {actual_service} - {content[:50]}...")
            else:
                print(f"   Request 2: No response")

            # Request 3: Streaming (should go to real service)
            print("   Request 3: Streaming...")
            stream = client.chat.completions.create(
                model="Qwen3-32B",
                messages=[{"role": "user", "content": "Request 3 - streaming"}],
                stream=True,
                timeout=30
            )
            full_content = ""
            for chunk in stream:
                if chunk.choices and len(chunk.choices) > 0:
                    delta = chunk.choices[0].delta
                    if hasattr(delta, 'content') and delta.content:
                        full_content += delta.content
            if full_content:
                actual_service = "Mock Service" if "This is a test response from the mock service" in full_content else "Real Service"
                responses.append((3, actual_service, full_content))
                print(f"   Request 3: {actual_service} - {full_content[:50]}...")
            else:
                print(f"   Request 3: No response")

            # Request 4: Streaming (should go to mock service)
            print("   Request 4: Streaming...")
            stream = client.chat.completions.create(
                model="Qwen3-32B",
                messages=[{"role": "user", "content": "Request 4 - streaming"}],
                stream=True,
                timeout=30
            )
            full_content = ""
            for chunk in stream:
                if chunk.choices and len(chunk.choices) > 0:
                    delta = chunk.choices[0].delta
                    if hasattr(delta, 'content') and delta.content:
                        full_content += delta.content
            if full_content:
                actual_service = "Mock Service" if "This is a test response from the mock service" in full_content else "Real Service"
                responses.append((4, actual_service, full_content))
                print(f"   Request 4: {actual_service} - {full_content[:50]}...")
            else:
                print(f"   Request 4: No response")

            # Analyze results
            print(f"\n--- Round-Robin Pattern Analysis ---")
            correct_count = 0
            for i, (req_num, actual_service, content) in enumerate(responses):
                expected = expected_services[i]
                status = "✅" if actual_service == expected else "❌"
                print(f"   Request {req_num}: Expected {expected}, Got {actual_service} {status}")
                if actual_service == expected:
                    correct_count += 1

            if correct_count == 4:
                print(f"✅ Perfect round-robin pattern: All {correct_count}/4 requests went to expected services")
            else:
                print(f"⚠️ Round-robin pattern: {correct_count}/4 requests went to expected services")

        except Exception as e:
            print(f"⚠️ Round-robin pattern test error: {e}")

        # Test with invalid model (should return error)
        try:
            client = OpenAI(
                api_key="dummy-key",
                base_url=self.router_url
            )

            response = client.chat.completions.create(
                model="invalid-model",
                messages=[{"role": "user", "content": "This should fail"}],
                stream=False,
                timeout=10
            )
            print(f"⚠️ Router unexpected response for invalid model: Should have failed but got response")
        except Exception as e:
            if "404" in str(e) or "400" in str(e) or "not found" in str(e).lower():
                print(f"✅ Router correctly rejects invalid model: {e}")
            else:
                print(f"⚠️ Router invalid model test error: {e}")

        # Test with malformed payload (should return error)
        try:
            client = OpenAI(
                api_key="dummy-key",
                base_url=self.router_url
            )

            # This should fail due to invalid messages format
            response = client.chat.completions.create(
                model="Qwen3-32B",
                messages="invalid_messages_format",  # Should be array
                stream=False,
                timeout=10
            )
            print(f"⚠️ Router unexpected response for malformed payload: Should have failed but got response")
        except Exception as e:
            if "400" in str(e) or "validation" in str(e).lower() or "invalid" in str(e).lower():
                print(f"✅ Router correctly rejects malformed payload: {e}")
            else:
                print(f"⚠️ Router malformed payload test error: {e}")

        return True

    def cleanup(self):
        """Cleanup all started processes"""
        print(f"\n{'='*80}")
        print("CLEANUP: Stopping All Services")
        print(f"{'='*80}")

        for name, process in self.processes.items():
            if process and process.poll() is None:
                print(f"🛑 Stopping {name} (PID: {process.pid})")
                process.terminate()
                try:
                    process.wait(timeout=5)
                    print(f"✅ {name} stopped")
                except subprocess.TimeoutExpired:
                    print(f"⚠️ {name} didn't stop gracefully, forcing kill")
                    process.kill()

        # Clean up any remaining services
        try:
            # Stop mock service if still running
            subprocess.run(["pkill", "-f", "test_service.py"], capture_output=True)
            # Stop real service if still running
            subprocess.run(["pkill", "-f", "enhanced_babysitter.py"], capture_output=True)
        except:
            pass

        print("✅ Cleanup completed")

    def run_validation_pipeline(self):
        """Run the complete validation pipeline"""
        print("🚀 Starting InfiniLM System Integration Validation Pipeline")
        print("This will validate the entire distributed system step by step")

        steps = [
            self.step1_launch_registry,
            self.step2_launch_router,
            self.step3_launch_mock_instance,
            self.step4_register_mock_instance,
            self.step5_launch_real_instance,
            self.step6_test_router_integration,
            self.step7_deregister_mock_instance
        ]

        try:
            for i, step in enumerate(steps, 1):
                if not step():
                    print(f"\n❌ VALIDATION FAILED at Step {i}")
                    return False
                time.sleep(2)  # Brief pause between steps

            print(f"\n{'='*80}")
            print("🎉 VALIDATION PIPELINE COMPLETED SUCCESSFULLY!")
            print("✅ All steps passed - System integration is working correctly")
            print(f"{'='*80}")
            return True

        except KeyboardInterrupt:
            print(f"\n⚠️ Validation interrupted by user")
            return False
        except Exception as e:
            print(f"\n❌ Validation failed with error: {e}")
            return False
        finally:
            self.cleanup()

def main():
    import argparse

    parser = argparse.ArgumentParser(description="InfiniLM System Integration Validation")
    parser.add_argument("--no-cleanup", action="store_true", help="Don't cleanup services after validation")
    parser.add_argument("--registry", default="http://localhost:8081", help="Registry URL")
    parser.add_argument("--router", default="http://localhost:8080", help="Router URL")

    args = parser.parse_args()

    validator = IntegrationValidator()
    validator.registry_url = args.registry
    validator.router_url = args.router

    success = validator.run_validation_pipeline()

    if not args.no_cleanup:
        validator.cleanup()

    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
