# Homelab Multi-Architecture System Troubleshooting Guide

This guide helps you diagnose and fix common issues in your multi-architecture homelab setup.

## Quick Start Deployment

```bash
# 1. Deploy the entire system
cd /Volumes/dev/homelab
./setup/deploy-homelab.sh deploy

# 2. Test the system
./setup/test-system.sh all

# 3. If issues, run troubleshooting
./setup/deploy-homelab.sh troubleshoot
```

## Common Issues and Solutions

### 1. Pods Stuck in Pending State

**Symptoms:**
- Pods show "Pending" status for extended periods
- No pods scheduled on certain architectures

**Diagnosis:**
```bash
kubectl get pods --all-namespaces | grep Pending
kubectl describe pod <pending-pod-name> -n <namespace>
```

**Common Causes & Solutions:**

#### A. Architecture Mismatch
**Issue:** Pod trying to run on wrong architecture

**Solution:**
```bash
# Check node labels
kubectl get nodes --show-labels | grep kubernetes.io/arch

# Fix node affinity in deployment
kubectl patch deployment <deployment-name> -n <namespace> -p '{
  "spec": {
    "template": {
      "spec": {
        "affinity": {
          "nodeAffinity": {
            "requiredDuringSchedulingIgnoredDuringExecution": {
              "nodeSelectorTerms": [{
                "matchExpressions": [{
                  "key": "kubernetes.io/arch",
                  "operator": "In",
                  "values": ["amd64", "arm64", "arm"]
                }]
              }]
            }
          }
        }
      }
    }
  }
}'
```

#### B. Resource Constraints
**Issue:** Not enough CPU/memory on target nodes

**Solution:**
```bash
# Check node resources
kubectl describe nodes

# Reduce resource requests
kubectl patch deployment <deployment-name> -n <namespace> -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "<container-name>",
          "resources": {
            "requests": {
              "cpu": "50m",
              "memory": "128Mi"
            }
          }
        }]
      }
    }
  }
}'
```

#### C. Storage Issues
**Issue:** PersistentVolumeClaims not bound

**Solution:**
```bash
# Check PV/PVC status
kubectl get pv,pvc --all-namespaces

# If using Longhorn, check if it's installed
kubectl get storageclass

# Create a simple local storage class if needed
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
EOF
```

### 2. Image Pull Errors

**Symptoms:**
- Pods show "ImagePullBackOff" or "ErrImagePull"
- Multi-architecture images not found

**Diagnosis:**
```bash
kubectl describe pod <pod-name> -n <namespace>
```

**Solutions:**

#### A. Architecture-Specific Images
```bash
# Check available architectures for image
docker manifest inspect <image-name>

# Use multi-arch images or specify arch-specific tags
# In deployment YAML:
spec:
  containers:
  - name: app
    image: python:3.11-slim  # Multi-arch
    # OR
    image: python:3.11-slim-arm64  # Arch-specific
```

#### B. Private Registry Access
```bash
# Create image pull secret
kubectl create secret docker-registry regcred \
  --docker-server=<your-registry-server> \
  --docker-username=<your-name> \
  --docker-password=<your-password> \
  --docker-email=<your-email>

# Add to deployment
spec:
  imagePullSecrets:
  - name: regcred
```

### 3. Service Communication Issues

**Symptoms:**
- Services not accessible
- DNS resolution failures
- Cross-architecture communication problems

**Diagnosis:**
```bash
# Check service endpoints
kubectl get endpoints --all-namespaces

# Test DNS resolution from within cluster
kubectl run debug --image=busybox -it --rm -- nslookup <service-name>.<namespace>

# Test service connectivity
kubectl run debug --image=curlimages/curl -it --rm -- curl http://<service-name>.<namespace>:8080/health
```

**Solutions:**

#### A. Service Configuration
```bash
# Check service selector matches pod labels
kubectl get service <service-name> -n <namespace> -o yaml
kubectl get pods -n <namespace> --show-labels

# Fix service selector if needed
kubectl patch service <service-name> -n <namespace> -p '{
  "spec": {
    "selector": {
      "app": "<correct-app-label>"
    }
  }
}'
```

#### B. Network Policies
```bash
# Check for restrictive network policies
kubectl get networkpolicies --all-namespaces

# Create permissive policy for debugging
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all
  namespace: <namespace>
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - {}
  egress:
  - {}
EOF
```

### 4. NATS Cluster Issues

**Symptoms:**
- Event consumers not receiving messages
- NATS pods not clustering properly

**Diagnosis:**
```bash
kubectl logs -n event-driven sts/nats -c nats
kubectl get pods -n event-driven -l app=nats
```

**Solutions:**

#### A. Clustering Problems
```bash
# Check NATS cluster status
kubectl port-forward -n event-driven svc/nats 8222:8222 &
curl http://localhost:8222/routez

# Restart NATS cluster
kubectl rollout restart statefulset/nats -n event-driven
```

#### B. Authentication Issues
```bash
# Reset NATS auth if needed
kubectl delete secret nats-auth -n event-driven --ignore-not-found

# The deployment will recreate with default credentials
kubectl rollout restart statefulset/nats -n event-driven
```

### 5. ML Serving Issues

**Symptoms:**
- Models not loading
- Inference requests failing
- Architecture routing not working

**Diagnosis:**
```bash
# Check model registry
kubectl port-forward -n ml-serving svc/model-registry 8000:8000 &
curl http://localhost:8000/models

# Check serving pods
kubectl logs -n ml-serving deployment/sklearn-serving-arm64
kubectl logs -n ml-serving deployment/tensorflow-serving-amd64
```

**Solutions:**

#### A. Model Storage Issues
```bash
# Check MinIO access
kubectl port-forward -n ml-serving svc/minio 9001:9001 &
# Open http://localhost:9001 (admin/minio123)

# Re-run model deployment
kubectl delete job ml-model-deployer -n ml-serving
kubectl apply -f /Volumes/dev/homelab/ml-serving/kserve-multiarch.yaml
```

#### B. Architecture Routing
```bash
# Verify node selectors
kubectl get deployment sklearn-serving-arm64 -n ml-serving -o yaml | grep -A5 nodeAffinity

# Check if nodes have correct labels
kubectl get nodes -l kubernetes.io/arch=arm64
```

### 6. Dashboard Issues

**Symptoms:**
- Dashboard not loading
- API not responding
- Metrics not updating

**Diagnosis:**
```bash
kubectl logs -n default deployment/dashboard-api
kubectl logs -n default deployment/dashboard-ui
```

**Solutions:**

#### A. API Connection Issues
```bash
# Check API health
kubectl port-forward -n default svc/dashboard-api 8080:8080 &
curl http://localhost:8080/health

# Restart if unhealthy
kubectl rollout restart deployment/dashboard-api -n default
kubectl rollout restart deployment/dashboard-ui -n default
```

#### B. Metrics Collection Problems
```bash
# Check if metrics server is running
kubectl get deployment metrics-server -n kube-system

# Install metrics server if missing
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

## Performance Optimization

### Resource Allocation by Architecture

```bash
# AMD64 nodes (high performance)
kubectl patch deployment <heavy-workload> -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "app",
          "resources": {
            "requests": {"cpu": "1000m", "memory": "2Gi"},
            "limits": {"cpu": "4000m", "memory": "8Gi"}
          }
        }]
      }
    }
  }
}'

# ARM64 nodes (balanced efficiency)
kubectl patch deployment <medium-workload> -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "app",
          "resources": {
            "requests": {"cpu": "200m", "memory": "512Mi"},
            "limits": {"cpu": "1000m", "memory": "2Gi"}
          }
        }]
      }
    }
  }
}'

# ARM nodes (ultra-efficient)
kubectl patch deployment <light-workload> -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "app",
          "resources": {
            "requests": {"cpu": "100m", "memory": "128Mi"},
            "limits": {"cpu": "250m", "memory": "256Mi"}
          }
        }]
      }
    }
  }
}'
```

## Monitoring Commands

### System Health Check
```bash
# Quick health check
./setup/test-system.sh test

# Detailed status
./setup/test-system.sh status

# Performance test
./setup/test-system.sh perf

# Full diagnostic
./setup/test-system.sh all
```

### Manual Checks
```bash
# Check all pod status
kubectl get pods --all-namespaces | grep -v Running

# Check resource usage
kubectl top nodes
kubectl top pods --all-namespaces | head -20

# Check events for errors
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20

# Check service endpoints
kubectl get endpoints --all-namespaces | grep -v '<none>'
```

## Emergency Recovery

### Complete System Reset
```bash
# Clean everything
./setup/deploy-homelab.sh clean

# Wait for cleanup
sleep 30

# Redeploy
./setup/deploy-homelab.sh deploy
```

### Selective Component Restart
```bash
# Restart specific components
kubectl rollout restart deployment/dashboard-api -n default
kubectl rollout restart statefulset/nats -n event-driven
kubectl rollout restart deployment/minio -n ml-serving
```

## Getting Help

### Log Collection
```bash
# Collect logs from all components
mkdir -p /tmp/homelab-logs
kubectl logs -n default deployment/dashboard-api > /tmp/homelab-logs/dashboard-api.log
kubectl logs -n event-driven statefulset/nats > /tmp/homelab-logs/nats.log
kubectl logs -n ml-serving deployment/model-registry > /tmp/homelab-logs/model-registry.log

# Get cluster info
kubectl cluster-info dump > /tmp/homelab-logs/cluster-info.txt
```

### System Configuration Export
```bash
# Export current configuration
kubectl get all --all-namespaces -o yaml > /tmp/homelab-logs/all-resources.yaml
kubectl get nodes -o yaml > /tmp/homelab-logs/nodes.yaml
```

This troubleshooting guide should help you identify and resolve most common issues in your multi-architecture homelab setup.