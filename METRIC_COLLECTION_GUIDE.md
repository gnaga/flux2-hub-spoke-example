# Cross-Cluster Metric Collection Setup

This guide explains how the metric collection from production and staging clusters is configured using Prometheus Remote Write and how to verify it's working.

## Overview

The hub cluster's Prometheus is configured to receive metrics from both production and staging clusters using Prometheus Remote Write. This provides real-time streaming of metrics and centralized monitoring and alerting across all environments.

## Configuration Components

### 1. Hub Prometheus Remote Write Receiver
- **File**: `hub/monitoring/controllers/kube-prometheus-stack/release.yaml`
- **Purpose**: Configures the hub Prometheus to receive remote write metrics from other clusters
- **Key settings**:
  - `enableRemoteWriteReceiver: true` - Enables the /api/v1/write endpoint
  - `remoteWriteDashboards: true` - Enables remote write monitoring dashboards

### 2. Remote Write Configurations
- **Directory**: `hub/monitoring/remote-write-configs/`
- **Purpose**: Template configurations for production and staging clusters to send metrics
- **Files**:
  - `production-remote-write.yaml` - Production cluster configuration
  - `staging-remote-write.yaml` - Staging cluster configuration
  - `README.md` - Detailed setup instructions

### 3. RBAC Configuration
- **File**: `hub/monitoring/controllers/kube-prometheus-stack/remote-write-rbac.yaml`
- **Purpose**: Grants necessary permissions for remote write operations
- **Components**:
  - ServiceAccount: `prometheus-remote-write`
  - ClusterRole: Access to services, endpoints, and monitoring resources
  - ClusterRoleBinding: Binds the role to the service account

### 4. Benefits of Remote Write over Federation
- **Real-time streaming**: Metrics sent as collected, not on-demand
- **Better performance**: No large queries, reduced load on source clusters
- **More reliable**: Built-in retry and queue management
- **Scalable**: Handles high metric volumes efficiently

## Verification Steps

Once the configuration is applied, you can verify remote write is working:

### 1. Check Remote Write Endpoint
```bash
# Port-forward to Prometheus UI
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Test the remote write endpoint
curl -X POST http://localhost:9090/api/v1/write \
  -H "Content-Type: application/x-protobuf" \
  -H "Content-Encoding: snappy" \
  --data-binary "@/dev/null"
# Should return 400 (bad request) but confirms endpoint exists
```

### 2. Monitor Remote Write Status
In Prometheus UI, check these metrics:

```promql
# Check if remote write receiver is active
prometheus_remote_storage_samples_total

# Monitor incoming metrics from clusters
rate(prometheus_remote_storage_samples_total[5m])

# Check for any remote write errors
prometheus_remote_storage_samples_failed_total
```

### 3. Query Cross-Cluster Metrics
Once source clusters are configured, try these queries:

```promql
# Check metrics from both clusters (once they're sending)
up{cluster=~"production|staging"}

# Flux controller metrics from remote clusters
gotk_resource_info{cluster=~"production|staging"}

# Kubernetes API server metrics
kubernetes_build_info{cluster=~"production|staging"}
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
- **Real-time Updates**: Metrics appear in hub cluster within seconds of being collected
- **Remote Metrics**: Kubernetes and application metrics from both clusters
- **Flux Metrics**: GitOps controller metrics from production and staging deployments
- **Remote Write Metrics**: Monitor the remote write process itself

## Troubleshooting

### Common Issues

1. **Remote Write Endpoint Not Available**: Check if `enableRemoteWriteReceiver: true` is set
2. **Connection Refused**: Verify network connectivity between clusters
3. **Authentication Issues**: Check RBAC permissions for remote write service account
4. **Queue Full**: Monitor `prometheus_remote_storage_queue_length` and adjust queue settings

### Debug Commands

```bash
# Check Prometheus logs for remote write receiver
kubectl logs -n monitoring deployment/prometheus-kube-prometheus-stack-prometheus-0 -c prometheus

# Verify RBAC permissions
kubectl auth can-i create services --as=system:serviceaccount:monitoring:prometheus-remote-write

# Check remote write endpoint availability
kubectl get svc -n monitoring kube-prometheus-stack-prometheus

# Monitor remote write metrics
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Then visit http://localhost:9090/graph and query prometheus_remote_storage_*
```

## Setup Instructions

1. **Hub Cluster**: Apply the configuration in this repository
2. **Source Clusters**: Use configurations in `hub/monitoring/remote-write-configs/`
3. **Network**: Ensure clusters can reach each other's Prometheus services
4. **Monitoring**: Use provided metrics to monitor remote write health

## Notes

- **Remote Write Endpoint**: `/api/v1/write` is automatically enabled on port 9090
- **Real-time Streaming**: Metrics appear within seconds (vs federation's polling)
- **Automatic Retries**: Built-in queue management handles network issues
- **Label Preservation**: All original labels preserved, plus `cluster` and `origin_prometheus`
- **Scalability**: Can handle high metric volumes more efficiently than federation
