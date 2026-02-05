#!/bin/bash

# Deploy Homelab with NFS Storage
# Uses NFS server at 192.168.0.250:/share

set -euo pipefail

NFS_SERVER="192.168.0.250"
NFS_PATH="/share"
HOMELAB_DIR="/home/mackieg/dev/homelab"

echo "🚀 Deploying Homelab with NFS Storage"
echo "NFS Server: $NFS_SERVER:$NFS_PATH"
echo ""

# Wait for namespace cleanup
echo "⏳ Waiting for namespace cleanup..."
kubectl wait --for=delete namespace/storage namespace/homelab-services namespace/smart-home namespace/media namespace/monitoring --timeout=60s 2>/dev/null || true
sleep 5

# Create NFS PersistentVolumes
echo "📦 Creating NFS PersistentVolumes..."
cat <<EOF | kubectl apply -f -
# Large shared storage
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-shared
spec:
  capacity:
    storage: 2Ti
  accessModes:
    - ReadWriteMany
  nfs:
    server: $NFS_SERVER
    path: $NFS_PATH/homelab/shared
  persistentVolumeReclaimPolicy: Retain
---
# Media storage
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-media
spec:
  capacity:
    storage: 2Ti
  accessModes:
    - ReadWriteMany
  nfs:
    server: $NFS_SERVER
    path: $NFS_PATH/homelab/media
  persistentVolumeReclaimPolicy: Retain
---
# Nextcloud data
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-nextcloud
spec:
  capacity:
    storage: 500Gi
  accessModes:
    - ReadWriteOnce
  nfs:
    server: $NFS_SERVER
    path: $NFS_PATH/homelab/nextcloud
  persistentVolumeReclaimPolicy: Retain
---
# MinIO data
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-minio
spec:
  capacity:
    storage: 500Gi
  accessModes:
    - ReadWriteOnce
  nfs:
    server: $NFS_SERVER
    path: $NFS_PATH/homelab/minio
  persistentVolumeReclaimPolicy: Retain
---
# Downloads storage
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-downloads
spec:
  capacity:
    storage: 1Ti
  accessModes:
    - ReadWriteMany
  nfs:
    server: $NFS_SERVER
    path: $NFS_PATH/homelab/downloads
  persistentVolumeReclaimPolicy: Retain
EOF

echo "✅ NFS PersistentVolumes created"
echo ""
echo "📝 Next steps:"
echo "1. Update your manifests to use NFS PVs or local-path storage"
echo "2. For large data (media, downloads, shared): use NFS PVs above"
echo "3. For small config data: use local-path (K3s default)"
echo ""
echo "To deploy, run:"
echo "  kubectl apply -f $HOMELAB_DIR/storage/network-storage.yaml"
echo "  kubectl apply -f $HOMELAB_DIR/services/homelab-services.yaml"
echo "  kubectl apply -f $HOMELAB_DIR/smart-home/home-assistant.yaml"
echo "  kubectl apply -f $HOMELAB_DIR/media/media-stack.yaml"
echo ""
echo "✨ NFS storage is ready!"
