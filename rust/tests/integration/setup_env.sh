#!/bin/bash
# Setup script for integration test conda environment

set -e

ENV_NAME="infinilm-integration-test"

echo "Setting up conda environment for integration tests..."
echo ""

if ! command -v conda &> /dev/null; then
    echo "Error: conda is not installed or not in PATH"
    echo "Please install conda or add it to your PATH"
    exit 1
fi

# Check if environment already exists
if conda env list | grep -q "^${ENV_NAME} "; then
    echo "Environment '${ENV_NAME}' already exists"
    read -p "Do you want to recreate it? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Removing existing environment..."
        conda env remove -n ${ENV_NAME} -y
    else
        echo "Updating existing environment..."
        conda run -n ${ENV_NAME} pip install -q --upgrade aiohttp requests
        echo "✅ Environment ready"
        exit 0
    fi
fi

# Create new environment
echo "Creating conda environment: ${ENV_NAME}..."
conda create -n ${ENV_NAME} python=3.10 -y

# Install dependencies
echo "Installing dependencies..."
conda run -n ${ENV_NAME} pip install aiohttp requests

# Verify installation
echo "Verifying installation..."
if conda run -n ${ENV_NAME} python -c "import aiohttp; import requests; print('✅ All dependencies installed')" 2>/dev/null; then
    echo ""
    echo "✅ Environment '${ENV_NAME}' is ready!"
    echo ""
    echo "To use it manually:"
    echo "  conda activate ${ENV_NAME}"
    echo ""
    echo "The integration test script will use it automatically."
else
    echo "❌ Error: Failed to verify dependencies"
    exit 1
fi
