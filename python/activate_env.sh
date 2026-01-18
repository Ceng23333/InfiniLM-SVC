#!/bin/bash

# InfiniLM Distributed Services Environment Activation Script
# This script activates the conda environment and sets up the working directory

echo "Activating InfiniLM Distributed Services Environment..."

# Activate conda environment
source /root/miniconda3/etc/profile.d/conda.sh
conda activate infinilm-distributed

# Change to the InfiniLM-SVC directory
cd /root/zenghua/repos/InfiniLM-SVC

# Create logs directory if it doesn't exist
mkdir -p logs

echo "Environment activated successfully!"
echo "Current directory: $(pwd)"
echo "Python version: $(python --version)"
echo "Conda environment: $CONDA_DEFAULT_ENV"
echo ""
echo "Available commands:"
echo "  ./deploy_services.sh start-registry    # Start service registry"
echo "  ./deploy_services.sh start-router      # Start distributed router"
echo "  ./deploy_services.sh start-services    # Start local services"
echo "  ./deploy_services.sh status            # Show status"
echo "  ./deploy_services.sh stop-all          # Stop all services"
echo ""
echo "For more information, run: ./deploy_services.sh --help"
