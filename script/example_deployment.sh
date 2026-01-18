#!/bin/bash

# Example Distributed InfiniLM Deployment
# This script demonstrates how to set up a distributed InfiniLM deployment

set -e

echo "=== Distributed InfiniLM Deployment Example ==="
echo ""

# Configuration
REGISTRY_PORT=8081
ROUTER_PORT=8080
SERVER1_IP="192.168.1.10"
SERVER2_IP="192.168.1.11"
ROUTER_IP="192.168.1.100"

echo "Configuration:"
echo "  Registry Port: $REGISTRY_PORT"
echo "  Router Port: $ROUTER_PORT"
echo "  Server 1 IP: $SERVER1_IP"
echo "  Server 2 IP: $SERVER2_IP"
echo "  Router IP: $ROUTER_IP"
echo ""

# Step 1: Start Service Registry
echo "Step 1: Starting Service Registry..."
echo "Run this on the router server ($ROUTER_IP):"
echo "  ./deploy_services.sh start-registry"
echo ""

# Step 2: Start Distributed Router
echo "Step 2: Starting Distributed Router..."
echo "Run this on the router server ($ROUTER_IP):"
echo "  ./deploy_services.sh start-router"
echo ""

# Step 3: Start Services on Server 1
echo "Step 3: Starting Services on Server 1 ($SERVER1_IP)..."
echo "SSH to $SERVER1_IP and run:"
echo "  ./deploy_services.sh start-services"
echo ""

# Step 4: Start Services on Server 2
echo "Step 4: Starting Services on Server 2 ($SERVER2_IP)..."
echo "SSH to $SERVER2_IP and run:"
echo "  ./deploy_services.sh start-services"
echo ""

# Step 5: Verify Deployment
echo "Step 5: Verify Deployment..."
echo "Check registry status:"
echo "  curl http://$ROUTER_IP:$REGISTRY_PORT/health"
echo ""
echo "Check router status:"
echo "  curl http://$ROUTER_IP:$ROUTER_PORT/health"
echo ""
echo "List all services:"
echo "  curl http://$ROUTER_IP:$REGISTRY_PORT/services"
echo ""

# Step 6: Test Load Balancing
echo "Step 6: Test Load Balancing..."
echo "Make requests to the router:"
echo "  curl http://$ROUTER_IP:$ROUTER_PORT/health"
echo "  curl http://$ROUTER_IP:$ROUTER_PORT/models"
echo ""

# Step 7: Generate Nginx Config
echo "Step 7: Generate Nginx Configuration..."
echo "Run this on the router server:"
echo "  ./deploy_services.sh generate-config"
echo ""

echo "=== Deployment Complete ==="
echo ""
echo "Your distributed InfiniLM setup is now ready!"
echo "Router endpoint: http://$ROUTER_IP:$ROUTER_PORT"
echo "Registry endpoint: http://$ROUTER_IP:$REGISTRY_PORT"
echo ""
echo "For management commands, see DISTRIBUTED_DEPLOYMENT_README.md"
