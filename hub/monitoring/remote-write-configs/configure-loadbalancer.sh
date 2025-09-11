#!/bin/bash

# Helper script to configure LoadBalancer endpoint in remote write configurations
# This script gets the LoadBalancer IP from the hub cluster and updates the configuration files

set -e

echo "🔍 Getting LoadBalancer IP from hub cluster..."

# Get the LoadBalancer IP
LOADBALANCER_IP=$(kubectl get svc kube-prometheus-stack-prometheus -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)

# If IP is empty, try getting the hostname (for AWS ELB)
if [ -z "$LOADBALANCER_IP" ]; then
    LOADBALANCER_IP=$(kubectl get svc kube-prometheus-stack-prometheus -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
fi

# Check if we got the LoadBalancer address
if [ -z "$LOADBALANCER_IP" ]; then
    echo "❌ Error: Could not get LoadBalancer IP/hostname for kube-prometheus-stack-prometheus service"
    echo "Please ensure:"
    echo "  1. You're connected to the hub cluster"
    echo "  2. The kube-prometheus-stack is deployed with LoadBalancer service type"
    echo "  3. Your cloud provider has assigned an external IP/hostname"
    
    echo ""
    echo "Current service status:"
    kubectl get svc kube-prometheus-stack-prometheus -n monitoring 2>/dev/null || echo "Service not found"
    exit 1
fi

echo "✅ Found LoadBalancer address: $LOADBALANCER_IP"

# Update production configuration
if [ -f "production-lightweight-values.yaml" ]; then
    echo "📝 Updating production-lightweight-values.yaml..."
    sed -i.bak "s|YOUR-HUB-PROMETHEUS-ENDPOINT|${LOADBALANCER_IP}|g" production-lightweight-values.yaml
    echo "✅ Updated production-lightweight-values.yaml"
else
    echo "⚠️  Warning: production-lightweight-values.yaml not found"
fi

# Update staging configuration
if [ -f "staging-lightweight-values.yaml" ]; then
    echo "📝 Updating staging-lightweight-values.yaml..."
    sed -i.bak "s|YOUR-HUB-PROMETHEUS-ENDPOINT|${LOADBALANCER_IP}|g" staging-lightweight-values.yaml
    echo "✅ Updated staging-lightweight-values.yaml"
else
    echo "⚠️  Warning: staging-lightweight-values.yaml not found"
fi

# Update ConfigMap-based configurations if they exist
if [ -f "production-remote-write.yaml" ]; then
    echo "📝 Updating production-remote-write.yaml..."
    sed -i.bak "s|YOUR-HUB-PROMETHEUS-ENDPOINT|${LOADBALANCER_IP}|g" production-remote-write.yaml
    echo "✅ Updated production-remote-write.yaml"
fi

if [ -f "staging-remote-write.yaml" ]; then
    echo "📝 Updating staging-remote-write.yaml..."
    sed -i.bak "s|YOUR-HUB-PROMETHEUS-ENDPOINT|${LOADBALANCER_IP}|g" staging-remote-write.yaml
    echo "✅ Updated staging-remote-write.yaml"
fi

echo ""
echo "🎉 Configuration complete!"
echo "📍 Hub Prometheus endpoint: http://$LOADBALANCER_IP:9090"
echo "📍 Remote write endpoint: http://$LOADBALANCER_IP:9090/api/v1/write"
echo ""
echo "Next steps:"
echo "1. Deploy the lightweight configurations to your production and staging clusters"
echo "2. Verify connectivity from source clusters to the LoadBalancer IP"
echo "3. Monitor remote write metrics in the hub cluster"

# Test connectivity (optional)
read -p "🔍 Test connectivity to the LoadBalancer endpoint? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Testing connectivity to http://$LOADBALANCER_IP:9090/api/v1/write..."
    if curl -s -X POST "http://$LOADBALANCER_IP:9090/api/v1/write" \
       -H "Content-Type: application/x-protobuf" \
       -H "Content-Encoding: snappy" \
       --data-binary "@/dev/null" \
       --max-time 10 >/dev/null 2>&1; then
        echo "✅ Connectivity test passed"
    else
        echo "⚠️  Connectivity test failed - this may be expected if remote write auth is required"
        echo "   You can test connectivity manually from your source clusters"
    fi
fi

echo ""
echo "💡 Backup files created with .bak extension - remove them when satisfied with the changes"
