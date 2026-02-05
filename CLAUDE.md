# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Multi-architecture Kubernetes homelab using K3s with AMD64 (NUC), ARM64 (Raspberry Pi 4), and ARM (Raspberry Pi Zero) nodes. Target power consumption: ~79W. Uses pure Kubernetes YAML manifests (no Helm/Kustomize).

## Common Commands

### Deployment
```bash
# Full deployment
./setup/deploy-complete-homelab.sh

# Single component deployment
./setup/deploy-component.sh <component>
# Components: storage, services, smart-home, esphome, media, usenet, monitoring, dashboard-api, dashboard-ui, touchscreen

# GitOps deployment with ArgoCD
./setup/deploy-gitops.sh
```

### Validation & Health
```bash
./setup/check-prerequisites.sh     # Verify kubectl, git, cluster connection
./setup/validate-simple.sh         # YAML syntax validation
./setup/health-check.sh            # Comprehensive health checks
```

### kubectl Operations
```bash
kubectl get pods --all-namespaces
kubectl apply -f <manifest.yaml>
kubectl apply --dry-run=client --validate=true -f <manifest.yaml>  # Validate before apply
```

## Architecture

### Deployment Order
Storage → Services → Smart-Home → Media → Monitoring → Dashboard → GitOps

### Directory-to-Namespace Mapping
| Directory | Namespace | Purpose |
|-----------|-----------|---------|
| storage/ | storage | MinIO, Nextcloud, NFS |
| services/ | homelab-services | Pi-hole, Portainer, Homer |
| smart-home/ | smart-home | Home Assistant, ESPHome, MQTT |
| media/ | media | Jellyfin, Radarr, Sonarr, SABnzbd |
| monitoring/ | monitoring | Grafana, Prometheus |
| apps/dashboard/ | default | Cluster dashboard API/UI |
| apps/touchscreen-monitor/ | touchscreen | 1024x600 touchscreen interface |
| gitops/ | argocd | ArgoCD for GitOps |

### Multi-Architecture Scheduling Pattern
All deployments use `nodeAffinity` for architecture-aware scheduling:
```yaml
affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      preference:
        matchExpressions:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]  # Heavy workloads
          # or ["arm64"] for balanced, ["arm"] for ultra-low-power
```

### Workload Distribution
- **AMD64 (NUC, 45W)**: Jellyfin transcoding, GitLab, PostgreSQL, heavy compute
- **ARM64 (RPi4, 7W)**: Home Assistant, Grafana, ArgoCD, balanced workloads
- **ARM (RPi0, 3W)**: Pi-hole, MQTT broker, backup scheduler

## Key Patterns

### Manifest Structure
Standard pattern across all services:
1. Namespace definition
2. ConfigMaps/Secrets (placeholders only - no real secrets in repo)
3. PersistentVolumeClaims
4. Deployments with resource limits and nodeAffinity
5. Services (ClusterIP/NodePort/LoadBalancer)
6. Ingress rules (domain: `*.homelab.local` or `*.mackie.house`)

### Security Placeholders
Before deployment, replace all placeholder credentials:
```bash
grep -r "changeme\|your-.*-key\|edgepassword" .
```

## CI/CD

GitHub Actions validates on push/PR:
- YAML syntax validation (pyyaml)
- Kubernetes manifest validation (`kubectl --dry-run=client`)
- Security scanning
- Shell script linting
