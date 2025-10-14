#!/usr/bin/env python3
"""
Simplified Service Registration Script for InfiniLM Distributed Services
This script makes it easy to register services with the registry
"""

import argparse
import requests
import json
import time
import sys
from typing import Dict, Any

class ServiceRegistrar:
    def __init__(self, registry_url: str = "http://localhost:8081"):
        self.registry_url = registry_url.rstrip('/')
        
    def register_service(self, name: str, host: str, port: int, 
                        hostname: str = None, metadata: Dict[str, Any] = None) -> bool:
        """Register a service with the registry"""
        if hostname is None:
            hostname = host
            
        if metadata is None:
            metadata = {}
            
        service_data = {
            "name": name,
            "host": host,
            "hostname": hostname,
            "port": port,
            "url": f"http://{host}:{port}",
            "status": "running",
            "metadata": metadata
        }
        
        try:
            response = requests.post(
                f"{self.registry_url}/services",
                json=service_data,
                timeout=10
            )
            
            if response.status_code == 201:
                print(f"✅ Service '{name}' registered successfully!")
                print(f"   URL: http://{host}:{port}")
                print(f"   Registry: {self.registry_url}")
                return True
            else:
                print(f"❌ Failed to register service: {response.text}")
                return False
                
        except requests.exceptions.RequestException as e:
            print(f"❌ Error connecting to registry: {e}")
            return False
    
    def unregister_service(self, name: str) -> bool:
        """Unregister a service from the registry"""
        try:
            response = requests.delete(
                f"{self.registry_url}/services/{name}",
                timeout=10
            )
            
            if response.status_code == 200:
                print(f"✅ Service '{name}' unregistered successfully!")
                return True
            else:
                print(f"❌ Failed to unregister service: {response.text}")
                return False
                
        except requests.exceptions.RequestException as e:
            print(f"❌ Error connecting to registry: {e}")
            return False
    
    def list_services(self) -> None:
        """List all registered services"""
        try:
            response = requests.get(f"{self.registry_url}/services", timeout=10)
            
            if response.status_code == 200:
                data = response.json()
                services = data.get('services', [])
                
                if not services:
                    print("📋 No services registered")
                    return
                    
                print(f"📋 Registered Services ({len(services)} total):")
                print("-" * 80)
                
                for service in services:
                    status_icon = "🟢" if service.get('is_healthy', False) else "🔴"
                    print(f"{status_icon} {service['name']}")
                    print(f"   URL: {service['url']}")
                    print(f"   Status: {service.get('status', 'unknown')}")
                    print(f"   Health: {service.get('health_status', 'unknown')}")
                    if service.get('metadata'):
                        print(f"   Metadata: {service['metadata']}")
                    print()
            else:
                print(f"❌ Failed to list services: {response.text}")
                
        except requests.exceptions.RequestException as e:
            print(f"❌ Error connecting to registry: {e}")
    
    def check_registry_health(self) -> bool:
        """Check if registry is healthy"""
        try:
            response = requests.get(f"{self.registry_url}/health", timeout=5)
            if response.status_code == 200:
                data = response.json()
                print(f"✅ Registry is healthy: {data.get('registered_services', 0)} services registered")
                return True
            else:
                print(f"❌ Registry health check failed: {response.text}")
                return False
        except requests.exceptions.RequestException as e:
            print(f"❌ Cannot connect to registry at {self.registry_url}")
            return False

def main():
    parser = argparse.ArgumentParser(description="InfiniLM Service Registration Tool")
    parser.add_argument("--registry", default="http://localhost:8081", 
                       help="Registry URL (default: http://localhost:8081)")
    
    subparsers = parser.add_subparsers(dest="command", help="Available commands")
    
    # Register command
    register_parser = subparsers.add_parser("register", help="Register a service")
    register_parser.add_argument("name", help="Service name")
    register_parser.add_argument("host", help="Service host")
    register_parser.add_argument("port", type=int, help="Service port")
    register_parser.add_argument("--hostname", help="Service hostname (defaults to host)")
    register_parser.add_argument("--metadata", help="JSON metadata string")
    
    # Unregister command
    unregister_parser = subparsers.add_parser("unregister", help="Unregister a service")
    unregister_parser.add_argument("name", help="Service name")
    
    # List command
    subparsers.add_parser("list", help="List all registered services")
    
    # Health command
    subparsers.add_parser("health", help="Check registry health")
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return
    
    registrar = ServiceRegistrar(args.registry)
    
    if args.command == "register":
        metadata = {}
        if args.metadata:
            try:
                metadata = json.loads(args.metadata)
            except json.JSONDecodeError:
                print("❌ Invalid JSON in metadata")
                return
        
        success = registrar.register_service(
            args.name, args.host, args.port, args.hostname, metadata
        )
        sys.exit(0 if success else 1)
        
    elif args.command == "unregister":
        success = registrar.unregister_service(args.name)
        sys.exit(0 if success else 1)
        
    elif args.command == "list":
        registrar.list_services()
        
    elif args.command == "health":
        success = registrar.check_registry_health()
        sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
