# Prometheus Deployment Troubleshooting

## Common Issues and Solutions

### 1. "HelmRepository prometheus-community not found"

**Error**: `failed to get source: HelmRepository.source.toolkit.fluxcd.io "prometheus-community" not found`

**Cause**: The HelmRelease is trying to reference a HelmRepository that doesn't exist yet.

**Solution**:
```bash
# Deploy HelmRepository first
kubectl apply -f clusters/production/infra-controllers/prometheus-repository.yaml

# Wait for it to be ready
kubectl wait --for=condition=Ready helmrepository/prometheus-community -n monitoring --timeout=60s

# Then deploy the HelmRelease
kubectl apply -f clusters/production/infra-controllers/prometheus-community-production.yaml
```

### 2. "unable to get dependency: helmreleases.helm.toolkit.fluxcd.io not found"

**Error**: `unable to get 'monitoring/prometheus-community' dependency: helmreleases.helm.toolkit.fluxcd.io "prometheus-community" not found`

**Cause**: The `dependsOn` field is incorrectly referencing a non-existent HelmRelease.

**Solution**: Remove the incorrect `dependsOn` field (this has been fixed in the configurations).

### 3. HelmRepository shows "Not Ready"

**Check status**:
```bash
kubectl describe helmrepository prometheus-community -n monitoring
```

**Common causes**:
- Network issues accessing https://prometheus-community.github.io/helm-charts
- DNS resolution problems
- Corporate firewall blocking access

**Solutions**:
```bash
# Check if the URL is accessible
curl -I https://prometheus-community.github.io/helm-charts

# Force reconcile
flux reconcile source helm prometheus-community -n monitoring

# Check source controller logs
kubectl logs -n flux-system deployment/source-controller
```

### 4. HelmRelease stuck in "Not Ready" state

**Check status**:
```bash
kubectl describe helmrelease kube-prometheus-stack -n monitoring
```

**Common causes**:
- Chart version not found (check if `61.x` exists)
- Values configuration errors
- Resource constraints

**Solutions**:
```bash
# Check available chart versions
helm search repo prometheus-community/kube-prometheus-stack --versions

# Check helm controller logs
kubectl logs -n flux-system deployment/helm-controller

# Force reconcile
flux reconcile helmrelease kube-prometheus-stack -n monitoring
```

### 5. Pods stuck in Pending state

**Check pod status**:
```bash
kubectl get pods -n monitoring
kubectl describe pod <pod-name> -n monitoring
```

**Common causes**:
- Insufficient cluster resources
- Storage class issues
- Node selectors/affinity

**Solutions**:
```bash
# Check cluster resources
kubectl top nodes
kubectl describe nodes

# Check storage class
kubectl get storageclass

# Reduce resource requests if needed (edit HelmRelease values)
```

### 6. Remote Write not working

**Check connectivity**:
```bash
# From source cluster, test hub connectivity
curl -X POST http://<HUB-LOADBALANCER-IP>:9090/api/v1/write \
  -H "Content-Type: application/x-protobuf" \
  --data-binary "@/dev/null" \
  --max-time 10
```

**Check Prometheus logs**:
```bash
# On source cluster
kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0

# Look for remote write errors
kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0 | grep -i "remote"
```

**Verify configuration**:
```bash
# Check if remote write URL is correct
kubectl get helmrelease kube-prometheus-stack -n monitoring -o yaml | grep -A 5 remoteWrite
```

## Diagnostic Commands

### Quick Health Check
```bash
#!/bin/bash
echo "=== Namespace ==="
kubectl get namespace monitoring

echo "=== HelmRepository ==="
kubectl get helmrepository -n monitoring

echo "=== HelmRelease ==="
kubectl get helmrelease -n monitoring

echo "=== Pods ==="
kubectl get pods -n monitoring

echo "=== Services ==="
kubectl get svc -n monitoring

echo "=== PVCs ==="
kubectl get pvc -n monitoring
```

### Detailed Diagnostics
```bash
#!/bin/bash
echo "=== HelmRepository Status ==="
kubectl describe helmrepository prometheus-community -n monitoring

echo "=== HelmRelease Status ==="
kubectl describe helmrelease kube-prometheus-stack -n monitoring

echo "=== Flux Controller Logs ==="
kubectl logs -n flux-system deployment/helm-controller --tail=50

echo "=== Prometheus Logs ==="
kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0 --tail=30 2>/dev/null || echo "Prometheus pod not ready"
```

## Clean Restart Procedure

If everything is stuck, try a clean restart:

```bash
# 1. Delete HelmRelease
kubectl delete helmrelease kube-prometheus-stack -n monitoring

# 2. Delete HelmRepository
kubectl delete helmrepository prometheus-community -n monitoring

# 3. Wait a moment
sleep 10

# 4. Redeploy using the script
./deploy-prometheus.sh production  # or staging
```

## Prevention

To avoid these issues in the future:

1. **Always use the deployment script**: `./deploy-prometheus.sh [production|staging]`
2. **Deploy step-by-step**: HelmRepository first, then HelmRelease
3. **Wait for readiness**: Use `kubectl wait` commands
4. **Monitor deployment**: Watch logs and status during deployment
5. **Test connectivity**: Verify LoadBalancer IPs before configuring remote write
