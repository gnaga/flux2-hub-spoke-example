#!/bin/bash

# Deployment script for Prometheus monitoring setup
# Handles HelmRepository dependency issues by deploying in correct order

set -e

CLUSTER_TYPE="$1"

if [ -z "$CLUSTER_TYPE" ] || [[ "$CLUSTER_TYPE" != "production" && "$CLUSTER_TYPE" != "staging" ]]; then
    echo "Usage: $0 [production|staging]"
    echo "Example: $0 production"
    exit 1
fi

echo "🚀 Deploying Prometheus monitoring to $CLUSTER_TYPE cluster"
echo "=============================================="

# Step 1: Deploy namespace and HelmRepository first
echo "📦 Step 1: Creating monitoring namespace and HelmRepository..."
kubectl apply -f clusters/$CLUSTER_TYPE/infra-controllers/prometheus-repository.yaml

# Step 2: Wait for HelmRepository to be ready
echo "⏳ Step 2: Waiting for HelmRepository to be ready..."
if kubectl wait --for=condition=Ready helmrepository/prometheus-community -n monitoring --timeout=60s; then
    echo "✅ HelmRepository is ready"
else
    echo "⚠️  HelmRepository not ready yet, but continuing..."
fi

# Step 3: Deploy the HelmRelease
echo "🔧 Step 3: Deploying HelmRelease..."
kubectl apply -f clusters/$CLUSTER_TYPE/infra-controllers/prometheus-community-$CLUSTER_TYPE.yaml

# Step 4: Monitor the deployment
echo "👀 Step 4: Monitoring deployment progress..."
echo "You can monitor the progress with:"
echo "  kubectl get helmrelease -n monitoring"
echo "  kubectl get pods -n monitoring"
echo "  kubectl logs -n flux-system deployment/helm-controller"
echo ""

# Check HelmRelease status
echo "Current HelmRelease status:"
kubectl get helmrelease -n monitoring 2>/dev/null || echo "No HelmReleases found yet"

echo ""
echo "🎉 Deployment initiated successfully!"
echo "💡 The deployment may take 5-10 minutes to complete."
echo "💡 Use 'kubectl get pods -n monitoring -w' to watch progress"
