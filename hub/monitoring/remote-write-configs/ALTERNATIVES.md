# Alternative Metric Collection Approaches

If you prefer NOT to deploy Prometheus instances in your production and staging clusters, this document outlines alternative approaches for collecting metrics.

## Why Alternatives Might Be Needed

- **Resource Constraints**: Limited CPU/Memory in source clusters
- **Security Policies**: Restrictions on deploying monitoring tools
- **Simplified Operations**: Preference for centralized-only monitoring
- **Cost Optimization**: Reducing per-cluster overhead

## Option 1: Direct Cross-Cluster Scraping

Configure the hub Prometheus to directly scrape metrics from production and staging clusters.

### Hub Configuration

Add to your hub cluster's kube-prometheus-stack values:

```yaml
prometheus:
  prometheusSpec:
    additionalScrapeConfigs:
      - job_name: 'production-nodes'
        kubernetes_sd_configs:
          - api_server: 'https://production-cluster-api:6443'
            role: node
            tls_config:
              ca_file: /etc/prometheus/secrets/production-ca/ca.crt
            bearer_token_file: /etc/prometheus/secrets/production-token/token
        relabel_configs:
          - target_label: cluster
            replacement: 'production'
          - target_label: environment
            replacement: 'production'

      - job_name: 'production-pods'
        kubernetes_sd_configs:
          - api_server: 'https://production-cluster-api:6443'
            role: pod
            tls_config:
              ca_file: /etc/prometheus/secrets/production-ca/ca.crt
            bearer_token_file: /etc/prometheus/secrets/production-token/token
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
            action: keep
            regex: 'true'
          - target_label: cluster
            replacement: 'production'

      - job_name: 'staging-nodes'
        kubernetes_sd_configs:
          - api_server: 'https://staging-cluster-api:6443'
            role: node
            tls_config:
              ca_file: /etc/prometheus/secrets/staging-ca/ca.crt
            bearer_token_file: /etc/prometheus/secrets/staging-token/token
        relabel_configs:
          - target_label: cluster
            replacement: 'staging'
          - target_label: environment
            replacement: 'staging'

    # Mount secrets for cluster access
    secrets:
      - production-ca
      - production-token
      - staging-ca  
      - staging-token
```

### Required Secrets

Create Kubernetes secrets in the hub cluster for cross-cluster access:

```bash
# Production cluster access
kubectl create secret generic production-ca \
  --from-file=ca.crt=production-cluster-ca.crt \
  -n monitoring

kubectl create secret generic production-token \
  --from-file=token=production-cluster-token.txt \
  -n monitoring

# Staging cluster access
kubectl create secret generic staging-ca \
  --from-file=ca.crt=staging-cluster-ca.crt \
  -n monitoring

kubectl create secret generic staging-token \
  --from-file=token=staging-cluster-token.txt \
  -n monitoring
```

### Requirements

1. **Network Connectivity**: Hub cluster must reach source cluster APIs
2. **RBAC Permissions**: Service accounts with monitoring permissions in source clusters
3. **Certificates**: Valid CA certificates and tokens for authentication
4. **Exposed Metrics**: Applications must expose Prometheus metrics

### Limitations

- **Higher Latency**: Network hops for each scrape
- **Single Point of Failure**: Hub cluster unavailable = no metrics collection
- **Network Dependencies**: Requires stable cross-cluster networking
- **Authentication Complexity**: Managing multiple cluster credentials

## Option 2: Grafana Agent (Recommended Alternative)

Deploy lightweight Grafana Agent instead of full Prometheus.

### Grafana Agent Configuration

```yaml
# grafana-agent-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-agent-config
  namespace: monitoring
data:
  config.yaml: |
    server:
      http_listen_port: 80
      log_level: info

    prometheus:
      configs:
        - name: production
          scrape_configs:
            # Kubernetes API Server
            - job_name: 'kubernetes-apiservers'
              kubernetes_sd_configs:
                - role: endpoints
              scheme: https
              tls_config:
                ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
              bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
              relabel_configs:
                - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
                  action: keep
                  regex: default;kubernetes;https

            # Kubelet metrics
            - job_name: 'kubernetes-nodes'
              kubernetes_sd_configs:
                - role: node
              scheme: https
              tls_config:
                ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
                insecure_skip_verify: true
              bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token

            # Pod metrics (applications with prometheus.io/scrape: "true")
            - job_name: 'kubernetes-pods'
              kubernetes_sd_configs:
                - role: pod
              relabel_configs:
                - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
                  action: keep
                  regex: true
                - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
                  action: replace
                  target_label: __metrics_path__
                  regex: (.+)

            # Flux controllers
            - job_name: 'flux-system'
              kubernetes_sd_configs:
                - role: pod
                  namespaces:
                    names: ['flux-system']
              relabel_configs:
                - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
                  action: keep
                  regex: true

          remote_write:
            - url: http://<LOADBALANCER-IP>:9090/api/v1/write
              external_labels:
                cluster: 'production'
                environment: 'production'
              queue_config:
                capacity: 10000
                max_shards: 50
                batch_send_deadline: 5s

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana-agent
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana-agent
  template:
    metadata:
      labels:
        app: grafana-agent
    spec:
      serviceAccountName: grafana-agent
      containers:
      - name: agent
        image: grafana/agent:latest
        args:
        - -config.file=/etc/agent/config.yaml
        - -prometheus.wal-directory=/tmp/wal
        ports:
        - containerPort: 80
        volumeMounts:
        - name: config
          mountPath: /etc/agent
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
      volumes:
      - name: config
        configMap:
          name: grafana-agent-config

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: grafana-agent
  namespace: monitoring

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: grafana-agent
rules:
- apiGroups: [""]
  resources: ["nodes", "nodes/metrics", "services", "endpoints", "pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["extensions"]
  resources: ["ingresses"]
  verbs: ["get", "list", "watch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: grafana-agent
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: grafana-agent
subjects:
- kind: ServiceAccount
  name: grafana-agent
  namespace: monitoring
```

### Benefits of Grafana Agent

1. **Lightweight**: ~50MB memory vs ~400MB for Prometheus
2. **Purpose-built**: Designed specifically for metric forwarding
3. **Prometheus Compatible**: Uses same scrape configs and relabeling
4. **Efficient**: Better performance for remote write scenarios
5. **Simpler**: No local storage, alerting, or querying complexity

## Option 3: Flux-Only Metrics Collection

If you only need GitOps metrics from Flux controllers:

### Minimal Scrape Configuration

```yaml
# Add to hub Prometheus
additionalScrapeConfigs:
  - job_name: 'production-flux'
    kubernetes_sd_configs:
      - api_server: 'https://production-cluster-api:6443'
        role: pod
        namespaces:
          names: ['flux-system']
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: 'true'
      - target_label: cluster
        replacement: 'production'

  - job_name: 'staging-flux' 
    kubernetes_sd_configs:
      - api_server: 'https://staging-cluster-api:6443'
        role: pod
        namespaces:
          names: ['flux-system']
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: 'true'
      - target_label: cluster
        replacement: 'staging'
```

### Flux Controller Configuration

Ensure Flux controllers expose metrics:

```yaml
# kustomization.yaml in flux-system
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- gotk-components.yaml
- gotk-sync.yaml
patches:
- patch: |
    - op: add
      path: /spec/template/metadata/annotations
      value:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
  target:
    kind: Deployment
    name: "(helm-controller|source-controller|kustomize-controller|notification-controller)"
```

## Option 4: OpenTelemetry Collector

Use OpenTelemetry Collector as a metrics gateway:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: otelcol-config
data:
  config.yaml: |
    receivers:
      prometheus:
        config:
          scrape_configs:
          - job_name: 'kubernetes-pods'
            kubernetes_sd_configs:
            - role: pod
    
    processors:
      resource:
        attributes:
        - key: cluster
          value: production
          action: insert
    
    exporters:
      prometheusremotewrite:
        endpoint: http://hub-prometheus:9090/api/v1/write
    
    service:
      pipelines:
        metrics:
          receivers: [prometheus]
          processors: [resource]
          exporters: [prometheusremotewrite]
```

## Recommendation

For most use cases without Prometheus in source clusters:

1. **Best Overall**: **Grafana Agent** - Purpose-built, lightweight, reliable
2. **Flux-only**: **Direct scraping** of flux-system namespace
3. **Full Monitoring**: **Cross-cluster scraping** if network allows
4. **Future-proof**: **OpenTelemetry** for vendor-neutral approach

The Grafana Agent approach provides the best balance of resource efficiency and functionality while maintaining the benefits of the remote write model.
