# Cross-Cluster Metric Collection Setup

This guide explains different approaches for collecting metrics from production and staging clusters and centralizing them in the hub cluster.

## Architecture Overview

There are several approaches to collect metrics from production and staging clusters:

### Option 1: Remote Write with Source Prometheus (Recommended)
Deploy lightweight Prometheus instances in production/staging clusters that collect metrics and forward them to the hub cluster via Remote Write.

### Option 2: Direct Scraping from Hub
Configure the hub cluster's Prometheus to directly scrape metrics from production/staging clusters over the network.

### Option 3: Pull-based with Service Discovery
Use Prometheus service discovery to dynamically discover and scrape targets across clusters.

**This guide focuses on Option 1 (Remote Write) as it provides the best performance, reliability, and scalability.**

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

### 4. Benefits of Prometheus Remote Write Model
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

### 4. Verify Remote Write Endpoints
```bash
# Check if remote write ConfigMap is properly mounted
kubectl get configmap flux-prometheus-remote-write -n monitoring -o yaml

# Check if Prometheus can access the scrape configs
kubectl logs -n monitoring deployment/kube-prometheus-stack-prometheus -c prometheus
```

### 5. Test Remote Write Connectivity
```bash
# Check if production/staging services are accessible from monitoring namespace
kubectl get services -n production | grep prometheus
kubectl get services -n staging | grep prometheus

# Test network connectivity (if services exist)
kubectl run test-pod --rm -i --tty --image=curlimages/curl -- /bin/sh
# From inside pod, test: curl http://prometheus-service.production:9090/api/v1/write
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

### Prerequisites
**IMPORTANT**: For the Prometheus Remote Write model to work, you MUST have Prometheus instances running in both production and staging clusters to collect and forward metrics.

### Deployment Steps

1. **Hub Cluster**: 
   - Deploy full kube-prometheus-stack with Grafana, AlertManager, and long-term storage
   - Apply the configuration in this repository
   - Enable remote write receiver (`enableRemoteWriteReceiver: true`)

2. **Production Cluster**:
   - **REQUIRED**: Deploy lightweight kube-prometheus-stack using `production-lightweight-values.yaml`
   - This installs Prometheus for metric collection (without Grafana/AlertManager)
   - Configure remote write to forward metrics to hub cluster
   - Apply remote write ConfigMaps

3. **Staging Cluster**:
   - **REQUIRED**: Deploy lightweight kube-prometheus-stack using `staging-lightweight-values.yaml`
   - This installs Prometheus for metric collection (without Grafana/AlertManager)
   - Configure remote write to forward metrics to hub cluster
   - Apply remote write ConfigMaps

4. **Network Configuration**: Ensure clusters can reach each other's Prometheus services

5. **Monitoring**: Use provided metrics to monitor remote write health

## Alternative Approaches (If No Prometheus in Source Clusters)

If you prefer NOT to deploy Prometheus in production/staging clusters, consider these alternatives:

### Option A: Direct Scraping from Hub
Configure the hub Prometheus to scrape metrics directly from source clusters:

```yaml
# Add to hub Prometheus configuration
additionalScrapeConfigs:
  - job_name: 'production-cluster'
    kubernetes_sd_configs:
      - api_server: 'https://production-k8s-api-server:6443'
        role: 'pod'
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - target_label: cluster
        replacement: production

  - job_name: 'staging-cluster'
    kubernetes_sd_configs:
      - api_server: 'https://staging-k8s-api-server:6443'
        role: 'pod'
    relabel_configs:
      - target_label: cluster
        replacement: staging
```

**Requirements:**
- Network connectivity from hub to source clusters
- Proper RBAC permissions for cross-cluster access
- Exposed metrics endpoints (node-exporter, kube-state-metrics, etc.)

### Option B: Metrics Collection Agents
Deploy lightweight metric collection agents (like Grafana Agent or Prometheus Agent):

```yaml
# Example: Grafana Agent configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-agent-config
data:
  config.yaml: |
    server:
      http_listen_port: 80
    prometheus:
      configs:
      - name: production
        scrape_configs:
        - job_name: kubernetes-pods
          kubernetes_sd_configs:
          - role: pod
        remote_write:
        - url: http://hub-prometheus:9090/api/v1/write
          external_labels:
            cluster: production
```

### Option C: Flux-specific Metrics Only
If you only need Flux GitOps metrics, configure Flux controllers to expose metrics and scrape them directly:

```yaml
# Flux controller configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: flux-monitoring
data:
  scrape_config: |
    - job_name: flux-system
      kubernetes_sd_configs:
      - role: pod
        namespaces:
          names: [flux-system]
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: "true"
```

**Recommendation**: Option 1 (Remote Write with lightweight Prometheus) is still preferred for production environments due to better reliability, performance, and feature completeness.

## Notes

- **Remote Write Endpoint**: `/api/v1/write` is automatically enabled on port 9090
- **Real-time Streaming**: Metrics appear within seconds using the Prometheus Remote Write model
- **Automatic Retries**: Built-in queue management handles network issues
- **Label Preservation**: All original labels preserved, plus `cluster` and `origin_prometheus`
- **Scalability**: Can handle high metric volumes more efficiently using the Prometheus Remote Write model
