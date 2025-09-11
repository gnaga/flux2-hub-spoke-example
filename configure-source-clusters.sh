#!/bin/bash

# Configuration script for production and staging cluster prometheus configurations
# This script updates the LoadBalancer endpoint in both cluster configurations

set -e

echo "🔧 Configuring Prometheus for Production and Staging Clusters"
echo "=========================================================="

# Check if we're in the right directory
if [ ! -f "clusters/production/infra-controllers/prometheus-community-production.yaml" ]; then
    echo "❌ Error: Not in the correct directory. Please run this from the flux2-hub-spoke-example root."
    exit 1
fi

# Get the hub cluster LoadBalancer IP
echo "🔍 Please provide the hub cluster's Prometheus LoadBalancer IP/hostname:"
echo "   You can get this from the hub cluster with:"
echo "   kubectl get svc kube-prometheus-stack-prometheus -n monitoring"
echo ""

read -p "Enter LoadBalancer IP/hostname: " LOADBALANCER_IP

if [ -z "$LOADBALANCER_IP" ]; then
    echo "❌ Error: LoadBalancer IP cannot be empty"
    exit 1
fi

echo ""
echo "📝 Updating configurations with LoadBalancer: $LOADBALANCER_IP"

# Update production configuration
echo "Updating production cluster configuration..."
sed -i.bak "s|YOUR-HUB-PROMETHEUS-LOADBALANCER|${LOADBALANCER_IP}|g" \
    clusters/production/infra-controllers/prometheus-community-production.yaml

# Update staging configuration
echo "Updating staging cluster configuration..."
sed -i.bak "s|YOUR-HUB-PROMETHEUS-LOADBALANCER|${LOADBALANCER_IP}|g" \
    clusters/staging/infra-controllers/prometheus-community-staging.yaml

echo ""
echo "✅ Configuration complete!"
echo ""
echo "📋 Summary of changes:"
echo "   Production cluster: Will send metrics to http://$LOADBALANCER_IP:9090/api/v1/write"
echo "   Staging cluster:    Will send metrics to http://$LOADBALANCER_IP:9090/api/v1/write"
echo ""
echo "🚀 Next steps:"
echo "1. Commit and push these changes to your Git repository"
echo "2. Ensure Flux is configured in your production and staging clusters"
echo "3. The lightweight kube-prometheus-stack will be deployed automatically"
echo "4. Monitor the deployments with: kubectl get helmrelease -n monitoring"
echo "5. Check remote write status in the hub cluster Prometheus"
echo ""
echo "💡 Backup files created with .bak extension - remove them when satisfied with changes"
