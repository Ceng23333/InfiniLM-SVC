#!/usr/bin/env python3
"""
Service Configuration Renderer
Generates service.toml files from deployment configurations and templates
"""

import json
import os
import argparse
from pathlib import Path
from typing import Dict, List, Any
import tempfile

class ServiceConfigRenderer:
    def __init__(self, templates_dir: str = "templates", configs_dir: str = "deployment_configs"):
        self.templates_dir = Path(templates_dir)
        self.configs_dir = Path(configs_dir)

    def load_template(self, template_name: str) -> str:
        """Load a template file"""
        template_path = self.templates_dir / template_name
        if not template_path.exists():
            raise FileNotFoundError(f"Template not found: {template_path}")

        with open(template_path, 'r') as f:
            return f.read()

    def load_deployment_config(self, config_name: str) -> Dict[str, Any]:
        """Load a deployment configuration file"""
        config_path = self.configs_dir / config_name
        if not config_path.exists():
            raise FileNotFoundError(f"Deployment config not found: {config_path}")

        with open(config_path, 'r') as f:
            return json.load(f)

    def create_test_models_config(self) -> Dict[str, Any]:
        """Create a test models configuration for validation"""
        return {
            "models": [
                {
                    "name": "test-model",
                    "path": "/tmp/test-model.gguf",  # Dummy path for testing
                    "gpus": [0],
                    "max_tokens": 1024,
                    "temperature": 0.7,
                    "top_p": 0.9,
                    "repetition_penalty": 1.02,
                    "max_sessions": 1
                }
            ]
        }

    def render_template(self, template_content: str, context: Dict[str, Any]) -> str:
        """Render template with context using simple string replacement"""
        rendered = template_content

        # Handle model sections
        if 'models' in context:
            model_sections = []
            for model in context['models']:
                model_section = f"[{model['name']}]\n"
                model_section += f"path = \"{model['path']}\"\n"
                model_section += f"gpus = {model['gpus']}\n"
                model_section += f"max-tokens = {model['max_tokens']}\n"
                model_section += f"temperature = {model['temperature']}\n"
                model_section += f"top-p = {model['top_p']}\n"
                model_section += f"repetition-penalty = {model['repetition_penalty']}\n"

                if 'top_k' in model:
                    model_section += f"top-k = {model['top_k']}\n"
                if 'think' in model:
                    model_section += f"think = {str(model['think']).lower()}\n"
                if 'max_sessions' in model:
                    model_section += f"max-sessions = {model['max_sessions']}\n"
                if 'gpu_memory_utilization' in model:
                    model_section += f"gpu-memory-utilization = {model['gpu_memory_utilization']}\n"

                model_sections.append(model_section)

            # Replace the model loop in template
            rendered = rendered.replace("{% for model in models %}", "")
            rendered = rendered.replace("{% endfor %}", "")
            rendered = rendered.replace("{% if model.top_k is defined %}top-k = {{ model.top_k }}{% endif %}", "")
            rendered = rendered.replace("{% if model.think is defined %}think = {{ model.think | lower }}{% endif %}", "")
            rendered = rendered.replace("{% if model.max_sessions is defined %}max-sessions = {{ model.max_sessions }}{% endif %}", "")
            rendered = rendered.replace("{% if model.gpu_memory_utilization is defined %}gpu-memory-utilization = {{ model.gpu_memory_utilization }}{% endif %}", "")
            rendered = rendered.replace("[{{ model.name }}]", "")
            rendered = rendered.replace("path = \"{{ model.path }}\"", "")
            rendered = rendered.replace("gpus = {{ model.gpus | tojson }}", "")
            rendered = rendered.replace("max-tokens = {{ model.max_tokens }}", "")
            rendered = rendered.replace("temperature = {{ model.temperature }}", "")
            rendered = rendered.replace("top-p = {{ model.top_p }}", "")
            rendered = rendered.replace("repetition-penalty = {{ model.repetition_penalty }}", "")

            # Add the rendered model sections
            rendered = "\n".join(model_sections) + "\n"

        return rendered

    def generate_service_config(self, template_name: str, context: Dict[str, Any], output_path: str = None) -> str:
        """Generate a service configuration file"""
        template_content = self.load_template(template_name)
        rendered_content = self.render_template(template_content, context)

        if output_path is None:
            # Create a temporary file
            temp_file = tempfile.NamedTemporaryFile(mode='w', suffix='.toml', delete=False)
            output_path = temp_file.name
            temp_file.write(rendered_content)
            temp_file.close()
        else:
            with open(output_path, 'w') as f:
                f.write(rendered_content)

        return output_path

    def generate_test_config(self, output_path: str = None) -> str:
        """Generate a test service configuration for validation"""
        test_context = self.create_test_models_config()
        return self.generate_service_config("service.toml.template", test_context, output_path)

def main():
    parser = argparse.ArgumentParser(description="Render service configurations from templates")
    parser.add_argument("--template", default="service.toml.template", help="Template file name")
    parser.add_argument("--config", help="Deployment configuration file")
    parser.add_argument("--output", help="Output file path")
    parser.add_argument("--test", action="store_true", help="Generate test configuration")
    parser.add_argument("--templates-dir", default="templates", help="Templates directory")
    parser.add_argument("--configs-dir", default="deployment_configs", help="Configs directory")

    args = parser.parse_args()

    renderer = ServiceConfigRenderer(args.templates_dir, args.configs_dir)

    try:
        if args.test:
            # Generate test configuration
            output_path = renderer.generate_test_config(args.output)
            print(f"Generated test service configuration: {output_path}")
        else:
            # Load deployment config and generate
            if not args.config:
                print("Error: --config is required when not using --test")
                return 1

            context = renderer.load_deployment_config(args.config)
            output_path = renderer.generate_service_config(args.template, context, args.output)
            print(f"Generated service configuration: {output_path}")

        return 0

    except Exception as e:
        print(f"Error: {e}")
        return 1

if __name__ == "__main__":
    exit(main())
