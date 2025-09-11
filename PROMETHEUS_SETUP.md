# Prometheus Multi-Cluster Setup Guide

This document explains the complete Prometheus monitoring setup for the hub-spoke architecture with cross-cluster metric collection.

## Architecture Overview

- **Hub Cluster**: Full kube-prometheus-stack with Grafana, AlertManager, and LoadBalancer service
- **Production Cluster**: Lightweight kube-prometheus-stack that forwards metrics to hub
- **Staging Cluster**: Lightweight kube-prometheus-stack that forwards metrics to hub

## Configuration Files

### Hub Cluster
- `hub/monitoring/controllers/kube-prometheus-stack/release.yaml` - Full monitoring stack with LoadBalancer service

### Base Configuration  
- `deploy/infra-controllers/prometheus-community.yaml` - HelmRepository and namespace
- `deploy/infra-controllers/kustomization.yaml` - Includes prometheus-community resource

### Production Cluster
- `clusters/production/infra-controllers/prometheus-community-production.yaml` - Lightweight config
- `clusters/production/infra-controllers/kustomization.yaml` - References production config

### Staging Cluster
- `clusters/staging/infra-controllers/prometheus-community-staging.yaml` - Lightweight config  
- `clusters/staging/infra-controllers/kustomization.yaml` - References staging config

## Setup Steps

### 1. Deploy Hub Cluster
```bash
# From hub cluster context
kubectl apply -k hub/
```

### 2. Get LoadBalancer IP
```bash
# Wait for LoadBalancer to be assigned
kubectl get svc kube-prometheus-stack-prometheus -n monitoring

# Get the external IP/hostname
LOADBALANCER_IP=$(kubectl get svc kube-prometheus-stack-prometheus -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Hub Prometheus LoadBalancer: $LOADBALANCER_IP"
```

### 3. Configure Source Clusters
```bash
# Run the configuration script
./configure-source-clusters.sh

# Enter the LoadBalancer IP when prompted
```

### 4. Deploy to Production Cluster
```bash
# Switch to production cluster context
kubectl config use-context production-cluster

# Apply the configuration
kubectl apply -k clusters/production/
```

### 5. Deploy to Staging Cluster
```bash
# Switch to staging cluster context
kubectl config use-context staging-cluster

# Apply the configuration
kubectl apply -k clusters/staging/
```

## Verification

### Check Deployments
```bash
# On each cluster, verify the HelmRelease
kubectl get helmrelease -n monitoring
kubectl get prometheus -n monitoring
kubectl get pods -n monitoring
```

### Verify Remote Write
```bash
# On hub cluster, check incoming metrics
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Visit http://localhost:9090 and query:
# up{cluster=~"production|staging"}
# gotk_resource_info{cluster=~"production|staging"}
```

### Monitor Remote Write Status
```bash
# Check remote write metrics on hub cluster
# prometheus_remote_storage_samples_total
# prometheus_remote_storage_samples_failed_total
```

## Resource Requirements

### Hub Cluster
- **Prometheus**: Default resources (higher memory/CPU)
- **Grafana**: Enabled with dashboards
- **AlertManager**: Enabled for alerting
- **Storage**: Long-term retention

### Production Cluster  
- **Prometheus**: 400Mi memory, 100m CPU
- **Storage**: 2Gi (2h retention)
- **Grafana**: Disabled
- **AlertManager**: Disabled

### Staging Cluster
- **Prometheus**: 300Mi memory, 75m CPU  
- **Storage**: 1Gi (2h retention)
- **Grafana**: Disabled
- **AlertManager**: Disabled

## Key Features

### Remote Write Configuration
- Automatic cluster labeling (`cluster=production/staging`)
- Queue management for reliability
- Retry mechanisms for network issues
- External labels for identification

### Lightweight Deployment
- 60-80% resource reduction vs full stack
- Disabled components (Grafana, AlertManager)
- Minimal retention (2h vs default 24h)
- Optimized queue settings

### Security Considerations
- LoadBalancer exposes Prometheus publicly
- Consider using `loadBalancerSourceRanges` for IP restrictions
- Enable authentication if needed
- Configure TLS for encrypted communication

## Troubleshooting

### Common Issues

1. **LoadBalancer Pending**
   ```bash
   kubectl describe svc kube-prometheus-stack-prometheus -n monitoring
   ```

2. **HelmRelease Stuck**
   ```bash
   kubectl describe helmrelease kube-prometheus-stack -n monitoring
   kubectl logs -n flux-system deployment/helm-controller
   ```

3. **Remote Write Not Working**
   ```bash
   # Check connectivity from source cluster
   curl -X POST http://<LOADBALANCER-IP>:9090/api/v1/write \
     -H "Content-Type: application/x-protobuf" \
     --data-binary "@/dev/null"
   
   # Check Prometheus logs
   kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0
   ```

4. **Missing Metrics**
   ```bash
   # Verify external labels on source clusters
   kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
   # Query: prometheus_build_info{cluster="production"}
   ```

## Customization

### Adding More Clusters
1. Create new cluster directory: `clusters/new-cluster/`
2. Copy and modify prometheus configuration
3. Update cluster labels and resource allocations
4. Run configuration script to set LoadBalancer IP

### Changing Metrics
- Modify `writeRelabelConfigs` to filter metrics
- Adjust `queueConfig` based on metric volume
- Update retention periods if needed

### Security Enhancements
```yaml
prometheus:
  service:
    type: LoadBalancer
    loadBalancerSourceRanges:
      - 10.0.0.0/8    # Your cluster CIDRs
      - 172.16.0.0/12
```

## Support

For issues with this setup:
1. Check the troubleshooting section
2. Verify network connectivity between clusters
3. Review Flux and Helm controller logs
4. Ensure LoadBalancer is properly assigned
