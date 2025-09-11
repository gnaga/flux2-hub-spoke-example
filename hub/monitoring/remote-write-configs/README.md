# Remote Write Configurations

This directory contains configuration templates for setting up Prometheus Remote Write from production and staging clusters to the hub cluster.

## Overview

**IMPORTANT**: This approach requires Prometheus instances running in production and staging clusters to collect and forward metrics.

This setup uses the Prometheus Remote Write model for more efficient and real-time metric collection:

- **Hub Cluster**: Receives metrics from all other clusters (full kube-prometheus-stack)
- **Production/Staging Clusters**: Run lightweight Prometheus instances that send metrics to the hub cluster via Remote Write

## Benefits of Prometheus Remote Write Model

1. **Real-time streaming**: Metrics are sent as they're collected, not on-demand
2. **Better performance**: No large polling queries, reduced load on target clusters
3. **More reliable**: Built-in retry mechanisms and queue management
4. **Scalable**: Can handle high metric volumes more efficiently
5. **Cleaner separation**: Hub cluster only stores metrics, source clusters handle collection

## Configuration Files

### production-remote-write.yaml
ConfigMap for the production cluster to send metrics to the hub.

### staging-remote-write.yaml  
ConfigMap for the staging cluster to send metrics to the hub.

### production-lightweight-values.yaml
Lightweight kube-prometheus-stack Helm values for production cluster deployment.

### staging-lightweight-values.yaml
Lightweight kube-prometheus-stack Helm values for staging cluster deployment.

## Lightweight kube-prometheus-stack for Source Clusters

Since monitoring is centralized in the hub cluster, production and staging clusters should use a lightweight kube-prometheus-stack configuration. This reduces resource usage while still providing metric collection capabilities.

### Recommended Lightweight Configuration

For production and staging clusters, disable components that are centralized in the hub:

```yaml
# values.yaml for staging/production kube-prometheus-stack
grafana:
  enabled: false  # Grafana runs in hub cluster

alertmanager:
  enabled: false  # Alerting handled by hub cluster

prometheus:
  prometheusSpec:
    # Reduce retention since metrics are sent to hub
    retention: "2h"
    retentionSize: "1GB"
    
    # Reduce resource requests
    resources:
      requests:
        memory: "400Mi"
        cpu: "100m"
      limits:
        memory: "800Mi"
        cpu: "200m"
    
    # Configure remote write to hub cluster
    remoteWrite:
      - url: "http://YOUR-HUB-PROMETHEUS-ENDPOINT:9090/api/v1/write"
        writeRelabelConfigs:
          # Add cluster label to identify source
          - targetLabel: cluster
            replacement: "production"  # or "staging"
        queueConfig:
          capacity: 10000
          maxShards: 50
          maxSamplesPerSend: 2000
          batchSendDeadline: 5s

# Optional: Disable node-exporter if metrics are collected differently
# nodeExporter:
#   enabled: false

# Optional: Keep kube-state-metrics for cluster-specific metrics
kube-state-metrics:
  enabled: true

# Optional: Disable Prometheus Operator CRDs if they exist in hub
prometheusOperator:
  admissionWebhooks:
    enabled: false  # Reduce complexity
  tls:
    enabled: false  # Simplify configuration
```

### Benefits of Lightweight Configuration

1. **Reduced Resource Usage**: Lower memory and CPU requirements
2. **Simplified Management**: Fewer components to maintain per cluster
3. **Centralized Monitoring**: All dashboards and alerts in one place
4. **Cost Efficiency**: Lower infrastructure costs for monitoring
5. **Consistent Experience**: Unified monitoring interface

### Customizing the Hub Endpoint

Before deploying, update the remote write URL in the lightweight values files:

```bash
# Edit the production configuration
sed -i 's|YOUR-HUB-PROMETHEUS-ENDPOINT|your-actual-hub-endpoint|g' production-lightweight-values.yaml

# Edit the staging configuration  
sed -i 's|YOUR-HUB-PROMETHEUS-ENDPOINT|your-actual-hub-endpoint|g' staging-lightweight-values.yaml
```

Example endpoints:
- **Internal Service**: `kube-prometheus-stack-prometheus.monitoring.svc.cluster.local`
- **External Ingress**: `prometheus.hub.example.com`
- **LoadBalancer**: `10.0.0.100`

## Usage

### For Production Cluster

1. Apply the lightweight kube-prometheus-stack configuration:
   ```bash
   # Apply with lightweight values
   helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
     --namespace monitoring --create-namespace \
     --values production-lightweight-values.yaml
   ```

2. Apply the ConfigMap for remote write configuration:
   ```bash
   kubectl apply -f production-remote-write.yaml
   ```

3. Update your production Prometheus HelmRelease to include the remote write configuration, or merge the provided patch.

### For Staging Cluster

1. Apply the lightweight kube-prometheus-stack configuration:
   ```bash
   # Apply with lightweight values
   helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
     --namespace monitoring --create-namespace \
     --values staging-lightweight-values.yaml
   ```

2. Apply the ConfigMap for remote write configuration:
   ```bash
   kubectl apply -f staging-remote-write.yaml
   ```

3. Update your staging Prometheus HelmRelease to include the remote write configuration, or merge the provided patch.

## Network Requirements

- Production and staging Prometheus instances must be able to reach the hub cluster's Prometheus service
- Default endpoint: `http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090/api/v1/write`
- For cross-cluster setup, you may need to use external service endpoints or ingress

## Monitoring Remote Write

You can monitor the remote write status using these metrics on the source clusters:

- `prometheus_remote_storage_samples_total`
- `prometheus_remote_storage_samples_failed_total`
- `prometheus_remote_storage_samples_retried_total`
- `prometheus_remote_storage_samples_pending`
- `prometheus_remote_storage_queue_length`

## Customization

### Changing the Hub Endpoint

Update the `url` field in both configuration files to point to your hub cluster's Prometheus remote write endpoint.

### Filtering Metrics

Add `writeRelabelConfigs` to filter which metrics are sent:

```yaml
writeRelabelConfigs:
  # Only send metrics matching certain patterns
  - sourceLabels: [__name__]
    regex: "up|.*_total|.*_duration_.*|gotk_.*"
    action: keep
  # Drop internal Prometheus metrics
  - sourceLabels: [__name__]
    regex: "prometheus_.*"
    action: drop
```

### Queue Configuration

Adjust queue settings based on your metric volume and network reliability:

- `capacity`: Total queue capacity (default: 10000)
- `maxShards`: Maximum number of parallel senders (default: 50)  
- `maxSamplesPerSend`: Samples per batch (default: 2000)
- `batchSendDeadline`: How long to wait before sending incomplete batch (default: 5s)

## Troubleshooting

1. **Connection Issues**: Check network connectivity between clusters
2. **Authentication**: Ensure proper RBAC if using service accounts
3. **Queue Full**: Increase capacity or reduce sample rate if queue fills up
4. **Performance**: Monitor queue metrics and adjust shard/batch settings
