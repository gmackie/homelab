# 🏠 Multi-Architecture Kubernetes Homelab

A complete enterprise-grade homelab setup optimized for multi-architecture deployment with your 1024x600 touchscreen display.

## 🎯 Overview

This homelab provides a full-featured Kubernetes cluster with intelligent workload placement across AMD64, ARM64, and ARM nodes, targeting ~79W total power consumption while delivering enterprise capabilities.

## 📊 System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    1024x600 Touchscreen                        │
│                  Homer Dashboard UI                             │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                 Multi-Architecture Cluster                     │
├─────────────────┬─────────────────┬─────────────────────────────┤
│   AMD64 Nodes   │   ARM64 Nodes   │      ARM Nodes              │
│   (Performance) │   (Efficiency)  │   (Ultra-Low Power)         │
│   45W each      │   7W each       │   3W each                   │
└─────────────────┴─────────────────┴─────────────────────────────┘
```

## 🚀 Features

### Core Infrastructure
- **Multi-Architecture Support**: AMD64 + ARM64 + ARM with intelligent placement
- **Storage**: Longhorn distributed storage with SSD/NVMe tiers
- **Networking**: Cilium eBPF with service mesh capabilities
- **Monitoring**: Prometheus + Grafana with comprehensive dashboards

### Essential Services
- **🏠 Homer Dashboard**: Perfect for 1024x600 touchscreen
- **📊 Grafana**: Home Assistant integration with room temperature monitoring
- **🛡️ Pi-hole**: Network-wide ad blocking
- **📦 Portainer**: Container management UI
- **🔐 Vaultwarden**: Self-hosted password manager
- **📈 Uptime Kuma**: Service monitoring

### Storage & Files
- **📂 MinIO**: S3-compatible object storage
- **☁️ Nextcloud**: File sync and sharing
- **🗂️ FileBrowser**: Simple web file manager
- **📡 NFS**: Network file system

### Media Automation
- **🎬 Jellyfin**: Media server with GPU transcoding
- **🎭 Radarr/Sonarr/Lidarr**: Media management
- **📥 SABnzbd**: Usenet downloader
- **🔍 Prowlarr/Jackett**: Indexer management

### Smart Home
- **🏡 Home Assistant**: Smart home platform
- **🔧 Node-RED**: Automation flows
- **🌡️ ESPHome**: IoT device management
- **📊 Room Monitoring**: Temperature, humidity, HVAC control

## 📋 Prerequisites

Run the prerequisites check:
```bash
./setup/check-prerequisites.sh
```

### Essential Tools
- `kubectl` - Kubernetes CLI
- `git` - Version control
- Container runtime (Docker/Podman)

### Recommended Tools
- `yq` - YAML processor
- `helm` - Kubernetes package manager
- `k9s` - Terminal UI for Kubernetes

## 🏗️ Quick Start

### 1. Validate Configuration
```bash
./setup/validate-simple.sh
```

### 2. Deploy Individual Components
```bash
# Storage layer
kubectl apply -f storage/network-storage.yaml

# Essential services
kubectl apply -f services/homelab-services.yaml

# Smart home platform
kubectl apply -f smart-home/home-assistant.yaml

# Media stack
kubectl apply -f media/media-stack.yaml
kubectl apply -f media/sabnzbd.yaml

# Monitoring
kubectl apply -f monitoring/grafana-homeassistant.yaml

# Dashboard
kubectl apply -f apps/dashboard/api/deployment.yaml
kubectl apply -f apps/dashboard/ui/deployment.yaml
```

### 3. Verify Deployment
```bash
./setup/verify-deployment.sh
```

## 🖥️ Touchscreen Setup

Your 1024x600 touchscreen is perfectly configured with the Homer dashboard:

```bash
# Point browser to:
http://homer.homelab.local
```

The dashboard includes organized service categories:
- **Infrastructure**: Grafana, ArgoCD, Portainer
- **Storage**: MinIO, Nextcloud, FileBrowser  
- **Media**: Jellyfin, Radarr, Sonarr, SABnzbd
- **Smart Home**: Home Assistant, Node-RED, ESPHome
- **Network**: Pi-hole, Vaultwarden, Uptime Kuma

## 📊 Key Service URLs

| Service | URL | Description |
|---------|-----|-------------|
| Homer Dashboard | http://homer.homelab.local | Main touchscreen interface |
| Home Assistant | http://homeassistant.homelab.local | Smart home hub |
| Grafana | http://grafana.homelab.local | Monitoring dashboards |
| Jellyfin | http://jellyfin.homelab.local | Media server |
| Pi-hole | http://pihole.homelab.local/admin | DNS ad blocker |
| Portainer | http://portainer.homelab.local | Container management |
| MinIO | http://minio.homelab.local | Object storage |
| Nextcloud | http://nextcloud.homelab.local | File sync & share |

## 🏡 Smart Home Integration

### Room Temperature Monitoring
The system includes comprehensive room monitoring:
- Living Room, Bedroom, Kitchen, Office temperatures
- Humidity tracking across all rooms
- Server room critical monitoring with alerts

### Grafana Dashboards
Three specialized dashboards for Home Assistant:
1. **Smart Home Overview**: Real-time temperatures, HVAC status
2. **Climate Control**: Temperature vs targets, energy usage
3. **Device Status**: Connectivity, battery levels, switches

### HVAC Automation
- Automated temperature scheduling (night/day modes)
- Energy optimization based on outdoor conditions
- Server room cooling with emergency controls
- Monthly maintenance reminders

## 🔧 Architecture-Aware Deployment

### Workload Placement Strategy
- **AMD64 Nodes**: High-performance workloads (Jellyfin transcoding, databases)
- **ARM64 Nodes**: Balanced efficiency (Home Assistant, web services)
- **ARM Nodes**: Ultra-low power (Pi-hole, simple services)

### Power Optimization
- **Target**: ~79W total cluster consumption
- **AMD64**: 45W per node (performance workloads)
- **ARM64**: 7W per node (balanced workloads)
- **ARM**: 3W per node (lightweight services)

## 📁 Directory Structure

```
homelab/
├── setup/                      # Deployment scripts
│   ├── validate-simple.sh      # YAML validation
│   ├── check-prerequisites.sh  # Prerequisites check
│   └── verify-deployment.sh    # Deployment verification
├── storage/                    # Storage layer
│   └── network-storage.yaml   # MinIO, Nextcloud, NFS
├── services/                   # Essential services
│   └── homelab-services.yaml  # Pi-hole, Portainer, Homer
├── smart-home/                 # Smart home platform
│   ├── home-assistant.yaml    # HA with room monitoring
│   └── esphome-devices.yaml   # IoT device configs
├── media/                      # Media automation
│   ├── media-stack.yaml       # Jellyfin, *arr apps
│   └── sabnzbd.yaml           # Usenet downloader
├── monitoring/                 # Observability
│   └── grafana-homeassistant.yaml # HA dashboards
└── apps/dashboard/             # Cluster dashboard
    ├── api/deployment.yaml
    └── ui/deployment.yaml
```

## 🛠️ Maintenance

### Regular Tasks
```bash
# Check cluster health
./setup/verify-deployment.sh

# Update configurations
kubectl apply -f <updated-manifest>

# Monitor resource usage
kubectl top nodes
kubectl top pods --all-namespaces

# Check logs
kubectl logs -n <namespace> <pod-name>
```

### Backup Strategy
- Longhorn automatic snapshots
- Configuration stored in Git
- Critical data backed up to MinIO

## 🔍 Troubleshooting

### Common Issues

**Pods Not Starting**
```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
```

**Storage Issues**
```bash
kubectl get pv,pvc --all-namespaces
kubectl describe pvc <pvc-name> -n <namespace>
```

**Network Connectivity**
```bash
kubectl get endpoints --all-namespaces
kubectl describe service <service-name> -n <namespace>
```

### Architecture-Specific Issues

**ARM Compatibility**
- Ensure images support ARM architecture
- Check node labels: `kubectl get nodes --show-labels`
- Verify affinity rules in deployments

**Resource Constraints**
- Monitor with: `kubectl top nodes`
- Adjust resource requests/limits
- Consider workload rebalancing

## 🎯 Performance Targets

| Metric | Target | Monitoring |
|--------|--------|------------|
| Total Power | ~79W | Grafana dashboard |
| CPU Efficiency | >85% useful work | Prometheus metrics |
| Storage IOPS | >1000 4K random | Longhorn metrics |
| Network Latency | <1ms internal | Service mesh metrics |
| Uptime | >99.9% | Uptime Kuma |

## 🚀 What's Next?

1. **Configure your servers** in `../nix-config`
2. **Set up your Kubernetes cluster** with k3s
3. **Deploy the homelab** using the provided manifests
4. **Connect your touchscreen** and enjoy your enterprise homelab!

## 🤝 Integration with nix-config

This repository focuses on:
- **Kubernetes manifests** and cluster configuration
- **Application deployment** and orchestration  
- **Dashboard configuration** for the touchscreen
- **Service integration** and networking

Your `../nix-config` repository handles:
- **Server configuration** and OS setup
- **Hardware management** and drivers
- **System services** and base packages
- **Infrastructure provisioning**

Perfect separation of concerns for a maintainable homelab! 🎉

---

**Ready to deploy your enterprise-grade homelab with touchscreen interface!** 🚀