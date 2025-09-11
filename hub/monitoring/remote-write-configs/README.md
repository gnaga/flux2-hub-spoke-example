# Remote Write Configurations

This directory contains configuration templates for setting up Prometheus Remote Write from production and staging clusters to the hub cluster.

## Overview

Instead of using Prometheus federation, this setup uses Remote Write for more efficient and real-time metric collection:

- **Hub Cluster**: Receives metrics from all other clusters
- **Production/Staging Clusters**: Send metrics to the hub cluster via Remote Write

## Benefits of Remote Write over Federation

1. **Real-time streaming**: Metrics are sent as they're collected, not on-demand
2. **Better performance**: No large federation queries, reduced load on target clusters
3. **More reliable**: Built-in retry mechanisms and queue management
4. **Scalable**: Can handle high metric volumes more efficiently
5. **Cleaner separation**: Hub cluster only stores metrics, source clusters handle collection

## Configuration Files

### production-remote-write.yaml
Configuration for the production cluster to send metrics to the hub.

### staging-remote-write.yaml  
Configuration for the staging cluster to send metrics to the hub.

## Usage

### For Production Cluster

1. Apply the ConfigMap to the production cluster:
   ```bash
   kubectl apply -f production-remote-write.yaml
   ```

2. Update your production Prometheus HelmRelease to include the remote write configuration, or merge the provided patch.

### For Staging Cluster

1. Apply the ConfigMap to the staging cluster:
   ```bash
   kubectl apply -f staging-remote-write.yaml
   ```

2. Update your staging Prometheus HelmRelease to include the remote write configuration, or merge the provided patch.

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
