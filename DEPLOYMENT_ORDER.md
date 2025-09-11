# Deployment Order Guide

To avoid "HelmRepository not found" errors, follow this deployment order:

## Option 1: Step-by-Step Deployment (Recommended)

### Step 1: Deploy HelmRepository First
```bash
# Production cluster
kubectl apply -f clusters/production/infra-controllers/prometheus-repository.yaml

# Staging cluster  
kubectl apply -f clusters/staging/infra-controllers/prometheus-repository.yaml

# Wait for HelmRepository to be ready
kubectl wait --for=condition=Ready helmrepository/prometheus-community -n monitoring --timeout=300s
```

### Step 2: Deploy HelmRelease
```bash
# Production cluster
kubectl apply -f clusters/production/infra-controllers/prometheus-community-production.yaml

# Staging cluster
kubectl apply -f clusters/staging/infra-controllers/prometheus-community-staging.yaml
```

### Step 3: Verify Deployment
```bash
# Check HelmRepository
kubectl get helmrepository -n monitoring

# Check HelmRelease
kubectl get helmrelease -n monitoring

# Check Prometheus pods
kubectl get pods -n monitoring
```

## Option 2: Full Kustomization (With Dependencies)

The configurations now include `dependsOn` fields to ensure proper order:

```bash
# This should work now with proper dependencies
kubectl apply -k clusters/production/infra-controllers/
kubectl apply -k clusters/staging/infra-controllers/
```

## Option 3: Using Flux GitRepository

If using Flux to sync from Git:

```bash
# Flux will handle the dependencies automatically
# Just ensure your GitRepository points to the right branch/path
kubectl get gitrepository -A
kubectl get kustomization -A
```

## Troubleshooting

### If you still get "HelmRepository not found":

1. **Check HelmRepository exists**:
   ```bash
   kubectl get helmrepository -n monitoring prometheus-community
   ```

2. **Check HelmRepository status**:
   ```bash
   kubectl describe helmrepository -n monitoring prometheus-community
   ```

3. **Check Flux source controller logs**:
   ```bash
   kubectl logs -n flux-system deployment/source-controller
   ```

4. **Force reconcile**:
   ```bash
   flux reconcile source helm prometheus-community -n monitoring
   ```

5. **Manual cleanup if needed**:
   ```bash
   kubectl delete helmrelease -n monitoring kube-prometheus-stack
   kubectl delete helmrepository -n monitoring prometheus-community
   # Wait a moment, then re-apply
   kubectl apply -k clusters/production/infra-controllers/
   ```

## Expected Timeline

- **HelmRepository Ready**: ~30 seconds
- **HelmRelease Ready**: ~2-5 minutes (downloading chart)
- **Prometheus Pods Running**: ~3-8 minutes (depending on cluster resources)

Monitor progress with:
```bash
watch kubectl get helmrelease,pods -n monitoring
```
