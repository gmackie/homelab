# Homelab K3s Deployment Status

**Date**: 2025-11-16
**Status**: NFS Storage Configuration Complete, Ready for Deployment

## ✅ Completed

1. **K3s Cluster** - Running (v1.33.5+k3s1) on labnuc
2. **kubectl Access** - Configured and working
3. **Longhorn Storage** - Installed but not recommended for this setup
4. **NFS Client** - Installed (nfs-utils)
5. **NFS Connectivity** - Verified (192.168.0.250:/share)
6. **Deployment Scripts** - Fixed and ready
   - Updated storage sizes to fit available disk
   - Fixed YAML validation (multi-document support)
   - Created NFS deployment script

## 🔧 Key Issues Resolved

### 1. Storage Configuration
- **Problem**: Manifests requested 8.5TB but only 455GB available
- **Solution**: Reduced sizes to ~270Gi total for local storage
- **Better Solution**: Use NFS server at 192.168.0.250

### 2. Longhorn Issues
- **Problem**: Volumes entering "faulted" state
- **Root Cause**: Disk space constraints + NFS mounting issues
- **Solution**: Switch to NFS storage from your NAS

### 3. NFS Mounting
- **Problem**: "mount program didn't pass remote address" error
- **Root Cause**: `nfs-utils` package not installed
- **Solution**: Installed nfs-utils, rpcbind, nfs-client.target

### 4. Deployment Script
- **Problem**: YAML validation failing on multi-document files
- **Root Cause**: Using `yaml.safe_load()` instead of `yaml.safe_load_all()`
- **Solution**: Fixed `/home/mackieg/dev/homelab/setup/deploy-complete-homelab.sh`

## 📊 Infrastructure Deployed

### Namespaces & Resources
- **150+ Kubernetes resources** created across all phases
- Namespaces: storage, homelab-services, smart-home, media, monitoring

### Services Configured
- **Storage**: MinIO, Nextcloud, NFS, FileBrowser
- **Services**: Pi-hole, Portainer, Homer, Vaultwarden, Uptime Kuma, Nginx Proxy Manager
- **Smart Home**: Home Assistant, Node-RED, ESPHome, Zigbee2MQTT
- **Media**: Jellyfin, Radarr, Sonarr, Lidarr, Prowlarr, qBittorrent, Jackett, Overseerr
- **Monitoring**: Grafana, Prometheus integration

## 🚀 Next Steps

### Option 1: Deploy with NFS (Recommended)

Use your NFS server for all large storage:

```bash
chmod +x /home/mackieg/dev/homelab/setup/deploy-with-nfs.sh
./setup/deploy-with-nfs.sh
```

Then manually deploy each phase:
```bash
kubectl apply -f storage/network-storage.yaml
kubectl apply -f services/homelab-services.yaml
kubectl apply -f smart-home/home-assistant.yaml
kubectl apply -f media/media-stack.yaml
kubectl apply -f monitoring/grafana-homeassistant.yaml
```

### Option 2: Deploy with Local Storage

Use the corrected manifests with reduced sizes:

```bash
HOMELAB_DIR=/home/mackieg/dev/homelab ./setup/deploy-complete-homelab.sh auto
```

**Note**: This uses Longhorn which had issues. May need troubleshooting.

## 📁 Storage Strategy

### Recommended: Hybrid Approach
- **Large data** → NFS (media, downloads, shared): Use NFS PVs
- **Small config** → local-path (configs, databases): Use K3s default

### NFS Server Details
- **Server**: 192.168.0.250
- **Path**: /share
- **Subdirectories needed on NFS**:
  - /share/homelab/shared
  - /share/homelab/media
  - /share/homelab/nextcloud
  - /share/homelab/minio
  - /share/homelab/downloads

## ⚠️ Known Issues

1. **Image Pull Failures** - Some images need fixing:
   - cloudflared
   - homer
   - esphome-compile-devices
   - ha-prometheus-bridge

2. **Jellyfin Deployment** - Has invalid fsGroup in securityContext

3. **Storage Classes** - longhorn-ssd/longhorn-nvme have disk selector issues (fixed by removing selectors)

## 🔍 Troubleshooting

### Check Pod Status
```bash
kubectl get pods --all-namespaces
```

### Check Storage
```bash
kubectl get pv,pvc --all-namespaces
```

### Check Longhorn Volumes
```bash
kubectl get volumes.longhorn.io -n longhorn-system
```

### View Logs
```bash
kubectl logs -n <namespace> <pod-name>
```

## 📝 Files Modified

- `/home/mackieg/dev/homelab/setup/deploy-complete-homelab.sh` - Fixed YAML validation
- `/home/mackieg/dev/homelab/storage/network-storage.yaml` - Reduced storage sizes
- `/home/mackieg/dev/homelab/setup/deploy-with-nfs.sh` - New NFS deployment script

## 🎯 Recommendation

**Use NFS storage from your NAS (192.168.0.250)** for a more reliable homelab setup. This avoids:
- Longhorn complexity
- Local disk space constraints
- Volume provisioning issues

The NFS server is working and verified. You just need to:
1. Create the subdirectories on your NAS (listed above)
2. Run the NFS deployment script
3. Deploy your services

---

*For questions or issues, check the troubleshooting section or review pod events with `kubectl describe pod <pod-name>`*
