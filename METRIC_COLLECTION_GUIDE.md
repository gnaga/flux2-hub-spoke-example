# Cross-Cluster Metric Collection Setup

This guide explains how the metric collection from production and staging clusters is configured and how to verify it's working.

## Overview

The hub cluster's Prometheus is configured to collect metrics from both production and staging clusters using Prometheus federation. This allows centralized monitoring and alerting across all environments.

## Configuration Components

### 1. Federation Scrape Configuration
- **File**: `hub/monitoring/controllers/kube-prometheus-stack/federation-scrape-config.yaml`
- **Purpose**: Configures additional scrape jobs for production and staging cluster federation
- **Key metrics collected**:
  - Core Kubernetes metrics (apiserver, kube-state-metrics, kubelet, node-exporter)
  - Flux controller metrics (gotk_*, controller_runtime_*)
  - Application metrics (up, *_total, *_duration_*, *_info)

### 2. Static Target Configuration
- **File**: Embedded in `federation-scrape-config.yaml`
- **Purpose**: Direct connection to known Prometheus services in production/staging clusters
- **Configuration**: Uses static targets to connect to Prometheus federation endpoints

### 3. RBAC Configuration
- **File**: `hub/monitoring/controllers/kube-prometheus-stack/monitoring-rbac.yaml`
- **Purpose**: Grants necessary permissions for cross-cluster metric collection
- **Components**:
  - ServiceAccount: `prometheus-federation`
  - ClusterRole: Access to services, endpoints, pods, and monitoring resources
  - RoleBindings: Specific access to production and staging namespaces

### 4. Prometheus Configuration
- **File**: `hub/monitoring/controllers/kube-prometheus-stack/release.yaml`
- **Updates**: 
  - Added `additionalScrapeConfigsSecret` configuration
  - Configured `serviceAccountName` for proper RBAC

## Verification Steps

Once the configuration is applied, you can verify metric collection is working:

### 1. Check Prometheus Targets
```bash
# Port-forward to Prometheus UI
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Open browser to http://localhost:9090
# Navigate to Status > Targets
# Look for federation jobs: "federate-production" and "federate-staging"
```

### 2. Query Cross-Cluster Metrics
In Prometheus UI, try these queries:

```promql
# Check if metrics from both clusters are available
up{cluster=~"production|staging"}

# Flux controller metrics from remote clusters
gotk_resource_info{cluster=~"production|staging"}

# Kubernetes API server metrics
kubernetes_build_info{cluster=~"production|staging"}

# Node metrics from remote clusters
node_info{cluster=~"production|staging"}
```

### 3. Verify Static Target Configuration
```bash
# Check the federation scrape configuration
kubectl get configmap flux-prometheus-federation -n monitoring -o yaml

# Look for the static_configs section with production and staging targets
# Expected targets:
# - kube-prometheus-stack-prometheus.production.svc.cluster.local:9090
# - kube-prometheus-stack-prometheus.staging.svc.cluster.local:9090
```

### 4. Verify Federation Endpoints
```bash
# Check if federation ConfigMap is properly mounted
kubectl get configmap flux-prometheus-federation -n monitoring -o yaml

# Check if Prometheus can access the scrape configs
kubectl logs -n monitoring deployment/kube-prometheus-stack-prometheus -c prometheus
```

### 5. Test Federation Connectivity
```bash
# Check if production/staging services are accessible from monitoring namespace
kubectl get services -n production | grep prometheus
kubectl get services -n staging | grep prometheus

# Test network connectivity (if services exist)
kubectl run test-pod --rm -i --tty --image=curlimages/curl -- /bin/sh
# From inside pod, test: curl http://prometheus-service.production:9090/federate
```

## Expected Metrics

Once working, you should see these metric patterns:

- **Cluster Labels**: All metrics will have a `cluster` label with values "production" or "staging"
- **Federation Jobs**: Targets showing "federate-production" and "federate-staging" jobs
- **Remote Metrics**: Kubernetes and application metrics from both clusters
- **Flux Metrics**: GitOps controller metrics from production and staging deployments

## Troubleshooting

### Common Issues

1. **No Federation Targets**: Check if production/staging Prometheus services exist and are labeled correctly
2. **RBAC Errors**: Verify the prometheus-federation ServiceAccount has proper permissions
3. **Network Issues**: Ensure the hub cluster can reach production/staging cluster services
4. **Configuration Errors**: Check Prometheus logs for scrape configuration parsing errors

### Debug Commands

```bash
# Check Prometheus configuration reload
kubectl logs -n monitoring deployment/kube-prometheus-stack-prometheus -c config-reloader

# Verify RBAC permissions
kubectl auth can-i get services --as=system:serviceaccount:monitoring:prometheus-federation -n production
kubectl auth can-i get services --as=system:serviceaccount:monitoring:prometheus-federation -n staging

# Check service discovery
kubectl get endpoints -n production
kubectl get endpoints -n staging
```

## Notes

- The configuration assumes that production and staging Prometheus instances are running in their respective namespaces
- Metrics are collected every 30 seconds from federation endpoints  
- The setup uses static target configuration to connect to known Prometheus services
- Expected service names: `kube-prometheus-stack-prometheus` or `prometheus-operated`
- All collected metrics are preserved with their original labels, plus an additional `cluster` label
