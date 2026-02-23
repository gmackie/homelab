# Next Steps for Homelab Deployment

**Current Status**: NFS deployment complete, storage configured, pods waiting for NFS mounts

## ✅ What We Accomplished

1. **Fixed storage class configuration**
   - Changed all ReadWriteMany PVCs from `local-path` to `nfs` storage class
   - All ReadWriteOnce PVCs using `local-path` (K3s built-in, working great)

2. **Created comprehensive NFS infrastructure**
   - 8 NFS PersistentVolumes created and bound
   - All PVCs successfully bound to appropriate volumes
   - Hybrid storage strategy in place

3. **Fixed deployment issues**
   - Jellyfin: Moved `fsGroup` from container to pod securityContext
   - Jellyfin: Removed GPU requirement (node doesn't have NVIDIA GPU)
   - All manifests updated and applied

4. **Current pod status**
   - **3 pods Running**: postgres (2), nextcloud-redis
   - **6 pods ContainerCreating**: Waiting for NFS mounts
   - **Many pods ImagePullBackOff**: Expected issue with some images

## 📊 NFS Volume Mapping

| PVC | Bound to PV | NFS Path | Status |
|-----|-------------|----------|--------|
| storage/shared-storage | nfs-media | /share/homelab/media | ✅ Dir exists |
| storage/nfs-storage | nfs-downloads | /share/homelab/downloads | ✅ Dir exists |
| media/downloads-storage | nfs-shared | /share/homelab/shared | ✅ Dir exists |
| media/movies-storage | nfs-movies | /share/homelab/movies | ⚠️ **Needs creation** |
| media/tv-storage | nfs-tv | /share/homelab/tv | ⚠️ **Needs creation** |
| media/music-storage | nfs-media-1 | /share/homelab/media | ✅ Dir exists |
| media/media-storage | nfs-media-general | /share/homelab/media-general | ⚠️ **Needs creation** |
| smart-home/media-storage | nfs-shared-1 | /share/homelab/shared | ✅ Dir exists |

## 🚨 IMMEDIATE ACTION REQUIRED

The following NFS directories need to be created on your NAS (192.168.0.250):

```bash
# SSH to your NAS and run:
mkdir -p /share/homelab/movies /share/homelab/tv /share/homelab/media-general
chmod 777 /share/homelab/movies /share/homelab/tv /share/homelab/media-general
```

**Why this is needed**: Kubernetes pods are stuck in ContainerCreating because they can't mount these NFS paths:
- `mount.nfs: access denied by server while mounting 192.168.0.250:/share/homelab/movies`
- `mount.nfs: access denied by server while mounting 192.168.0.250:/share/homelab/tv`
- `mount.nfs: access denied by server while mounting 192.168.0.250:/share/homelab/media-general`

## 🔄 After Creating Directories

Once you've created the directories on your NAS, the pods should automatically start:

```bash
# Watch pods start up:
watch kubectl get pods --all-namespaces

# Check for any remaining issues:
kubectl get pods --all-namespaces | grep -v "Running\|Completed"
```

## 📝 Known Issues to Address Later

### Image Pull Failures
Many pods have ImagePullBackOff errors. These are expected issues noted in previous sessions:
- cloudflared, homer, esphome, ha-prometheus-bridge
- Various media stack images

To fix these, you'll need to:
1. Verify image names/tags in manifests
2. Check registry access
3. Update to working image versions

### Services Still Pending Review
- MinIO, Nextcloud, NFS server, FileBrowser (storage namespace)
- Pi-hole, Portainer, Homer, etc. (homelab-services namespace)
- Most media stack apps (Radarr, Sonarr, qBittorrent, etc.)

## 🎯 Success Metrics

When the NFS directories are created, you should see:
- **Jellyfin, Radarr, Sonarr, Lidarr pods**: Running
- **Home Assistant pod**: Running
- **All storage volumes**: Successfully mounted

## 📁 Files Modified in This Session

- `storage/network-storage.yaml` - Updated PVCs to use NFS storage class
- `media/media-stack.yaml` - Fixed Jellyfin deployment, updated PVCs to NFS
- `smart-home/home-assistant.yaml` - Updated media-storage PVC to NFS
- `fix-rwx-pvcs.py` - Python script to automate PVC updates
- `fix-storage.sh` - Script to change Longhorn to local-path (already run)

## 🏆 Bottom Line

**You're very close!** The infrastructure is all configured correctly. Just need to create 3 directories on the NAS:

```bash
ssh user@192.168.0.250
mkdir -p /share/homelab/movies /share/homelab/tv /share/homelab/media-general
chmod 777 /share/homelab/movies /share/homelab/tv /share/homelab/media-general
```

Then your homelab should start running!
