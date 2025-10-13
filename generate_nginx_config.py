#!/usr/bin/env python3
"""
Distributed Nginx Configuration Generator for InfiniLM Multi-Service Setup
Generates nginx configuration for routing to services across multiple servers
"""

import argparse
import json
import sys
from typing import List, Dict, Optional
from dataclasses import dataclass

@dataclass
class ServiceEndpoint:
    name: str
    host: str
    port: int
    weight: int = 1
    max_fails: int = 3
    fail_timeout: str = "30s"
    backup: bool = False

class NginxConfigGenerator:
    def __init__(self, router_port: int = 8080, upstream_name: str = "infinilm_backend"):
        self.router_port = router_port
        self.upstream_name = upstream_name
        self.services: List[ServiceEndpoint] = []
        self.health_check_enabled = True
        self.load_balancing_method = "round_robin"  # round_robin, least_conn, ip_hash
        self.proxy_timeout = 300
        self.proxy_connect_timeout = 60

    def add_service(self, name: str, host: str, port: int, weight: int = 1,
                   max_fails: int = 3, fail_timeout: str = "30s", backup: bool = False):
        """Add a service endpoint to the configuration"""
        service = ServiceEndpoint(
            name=name,
            host=host,
            port=port,
            weight=weight,
            max_fails=max_fails,
            fail_timeout=fail_timeout,
            backup=backup
        )
        self.services.append(service)

    def add_services_from_file(self, config_file: str):
        """Add services from a JSON configuration file"""
        try:
            with open(config_file, 'r') as f:
                config = json.load(f)

            for service_config in config.get('services', []):
                self.add_service(
                    name=service_config.get('name', f"service_{len(self.services) + 1}"),
                    host=service_config['host'],
                    port=service_config['port'],
                    weight=service_config.get('weight', 1),
                    max_fails=service_config.get('max_fails', 3),
                    fail_timeout=service_config.get('fail_timeout', '30s'),
                    backup=service_config.get('backup', False)
                )
        except FileNotFoundError:
            print(f"Error: Configuration file '{config_file}' not found", file=sys.stderr)
            sys.exit(1)
        except json.JSONDecodeError as e:
            print(f"Error: Invalid JSON in configuration file: {e}", file=sys.stderr)
            sys.exit(1)
        except KeyError as e:
            print(f"Error: Missing required field '{e}' in configuration file", file=sys.stderr)
            sys.exit(1)

    def generate_nginx_config(self) -> str:
        """Generate nginx configuration"""
        if not self.services:
            raise ValueError("No services configured")

        config = f"""events {{
    worker_connections 1024;
}}

http {{
    # Load balancing method
    upstream {self.upstream_name} {{
        # Load balancing method: {self.load_balancing_method}
"""

        # Add load balancing method
        if self.load_balancing_method == "least_conn":
            config += "        least_conn;\n"
        elif self.load_balancing_method == "ip_hash":
            config += "        ip_hash;\n"
        # round_robin is default, no directive needed

        # Add service endpoints
        for service in self.services:
            config += f"        server {service.host}:{service.port}"

            if service.weight != 1:
                config += f" weight={service.weight}"
            if service.max_fails != 3:
                config += f" max_fails={service.max_fails}"
            if service.fail_timeout != "30s":
                config += f" fail_timeout={service.fail_timeout}"
            if service.backup:
                config += " backup"

            config += f";  # {service.name}\n"

        config += f"""    }}

    # Health check configuration
    upstream {self.upstream_name}_health {{
"""

        # Add health check endpoints
        for service in self.services:
            config += f"        server {service.host}:{service.port};\n"

        config += f"""    }}

    server {{
        listen {self.router_port};
        server_name _;

        # Health check endpoint for the router itself
        location /health {{
            access_log off;
            return 200 "healthy\\n";
            add_header Content-Type text/plain;
        }}

        # Service discovery endpoint
        location /services {{
            access_log off;
            add_header Content-Type application/json;
            return 200 '{json.dumps(self._get_services_info(), indent=2)}';
        }}

        # Backend health check endpoint
        location /backend-health {{
            access_log off;
            proxy_pass http://{self.upstream_name}_health;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_connect_timeout 5s;
            proxy_send_timeout 5s;
            proxy_read_timeout 5s;
        }}

        # Proxy all other requests to backend services
        location / {{
            proxy_pass http://{self.upstream_name};
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;

            # Timeout settings
            proxy_connect_timeout {self.proxy_connect_timeout}s;
            proxy_send_timeout {self.proxy_timeout}s;
            proxy_read_timeout {self.proxy_timeout}s;

            # Buffer settings
            proxy_buffering on;
            proxy_buffer_size 4k;
            proxy_buffers 8 4k;

            # Error handling
            proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
            proxy_next_upstream_tries 3;
            proxy_next_upstream_timeout 10s;
        }}
    }}
}}"""

        return config

    def _get_services_info(self) -> Dict:
        """Get services information for the /services endpoint"""
        return {
            "upstream": self.upstream_name,
            "load_balancing_method": self.load_balancing_method,
            "services": [
                {
                    "name": service.name,
                    "host": service.host,
                    "port": service.port,
                    "weight": service.weight,
                    "max_fails": service.max_fails,
                    "fail_timeout": service.fail_timeout,
                    "backup": service.backup
                }
                for service in self.services
            ],
            "total_services": len(self.services)
        }

    def save_config(self, output_file: str):
        """Save nginx configuration to file"""
        config = self.generate_nginx_config()
        with open(output_file, 'w') as f:
            f.write(config)
        print(f"Nginx configuration saved to: {output_file}")

    def print_config(self):
        """Print nginx configuration to stdout"""
        print(self.generate_nginx_config())

def main():
    parser = argparse.ArgumentParser(description="Generate nginx configuration for distributed InfiniLM services")
    parser.add_argument("--router-port", type=int, default=8080, help="Router port (default: 8080)")
    parser.add_argument("--upstream-name", default="infinilm_backend", help="Upstream name (default: infinilm_backend)")
    parser.add_argument("--config-file", help="JSON configuration file with services")
    parser.add_argument("--output", "-o", help="Output file (default: stdout)")
    parser.add_argument("--load-balancing", choices=["round_robin", "least_conn", "ip_hash"],
                       default="round_robin", help="Load balancing method (default: round_robin)")
    parser.add_argument("--proxy-timeout", type=int, default=300, help="Proxy timeout in seconds (default: 300)")
    parser.add_argument("--proxy-connect-timeout", type=int, default=60, help="Proxy connect timeout in seconds (default: 60)")

    # Service specification options
    parser.add_argument("--services", help="Comma-separated list of services in format 'name:host:port:weight'")

    args = parser.parse_args()

    # Create generator
    generator = NginxConfigGenerator(args.router_port, args.upstream_name)
    generator.load_balancing_method = args.load_balancing
    generator.proxy_timeout = args.proxy_timeout
    generator.proxy_connect_timeout = args.proxy_connect_timeout

    # Add services from configuration file
    if args.config_file:
        generator.add_services_from_file(args.config_file)

    # Add services from command line
    if args.services:
        for service_spec in args.services.split(','):
            parts = service_spec.strip().split(':')
            if len(parts) < 3:
                print(f"Error: Invalid service specification '{service_spec}'. Expected format: 'name:host:port:weight'", file=sys.stderr)
                sys.exit(1)

            name = parts[0]
            host = parts[1]
            port = int(parts[2])
            weight = int(parts[3]) if len(parts) > 3 else 1

            generator.add_service(name, host, port, weight)

    # Check if any services were added
    if not generator.services:
        print("Error: No services configured. Use --config-file or --services to specify services.", file=sys.stderr)
        sys.exit(1)

    # Generate and output configuration
    if args.output:
        generator.save_config(args.output)
    else:
        generator.print_config()

if __name__ == "__main__":
    main()
