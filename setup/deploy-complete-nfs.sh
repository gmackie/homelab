#!/bin/bash

# Complete NFS-Based Homelab Deployment
# Uses NFS server at 192.168.0.250:/share for ALL storage

set -euo pipefail

NFS_SERVER="192.168.0.250"
NFS_BASE="/share/homelab"

echo "🚀 Complete NFS-Based Homelab Deployment"
echo "NFS Server: $NFS_SERVER:$NFS_BASE"
echo ""

# Wait for namespace cleanup
echo "⏳ Waiting for namespace cleanup..."
for ns in storage homelab-services smart-home media monitoring; do
    kubectl wait --for=delete namespace/$ns --timeout=60s 2>/dev/null || true
done
sleep 5

echo "📦 Creating comprehensive NFS PersistentVolumes..."

# Delete existing NFS PVs to start fresh
kubectl delete pv --selector=nfs-homelab=true 2>/dev/null || true

# Create all NFS PersistentVolumes
cat <<EOF | kubectl apply -f -
# Large shared storage
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-shared
  labels:
    nfs-homelab: "true"
spec:
  capacity:
    storage: 2Ti
  accessModes:
    - ReadWriteMany
  nfs:
    server: $NFS_SERVER
    path: $NFS_BASE/shared
  persistentVolumeReclaimPolicy: Retain
  storageClassName: nfs
---
# Media storage
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-media
  labels:
    nfs-homelab: "true"
spec:
  capacity:
    storage: 2Ti
  accessModes:
    - ReadWriteMany
  nfs:
    server: $NFS_SERVER
    path: $NFS_BASE/media
  persistentVolumeReclaimPolicy: Retain
  storageClassName: nfs
---
# Downloads
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-downloads
  labels:
    nfs-homelab: "true"
spec:
  capacity:
    storage: 1Ti
  accessModes:
    - ReadWriteMany
  nfs:
    server: $NFS_SERVER
    path: $NFS_BASE/downloads
  persistentVolumeReclaimPolicy: Retain
  storageClassName: nfs
---
# NFS Storage Class (manual binding)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
EOF

echo "✅ NFS PersistentVolumes created"
echo ""

# Set local-path as default for configs
echo "⚙️  Configuring storage classes..."
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' 2>/dev/null || true
kubectl patch storageclass longhorn -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' 2>/dev/null || true
kubectl patch storageclass longhorn-ssd -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' 2>/dev/null || true

echo "✅ local-path set as default for configs, NFS available for large data"
echo ""

echo "📋 Deployment Strategy:"
echo "  - Small configs → local-path (K3s default, fast)"
echo "  - Large data → NFS (your NAS)"
echo ""
echo "📝 Ready to deploy! Run:"
echo "  kubectl apply -f /home/mackieg/dev/homelab/storage/network-storage.yaml"
echo "  kubectl apply -f /home/mackieg/dev/homelab/services/homelab-services.yaml"
echo "  kubectl apply -f /home/mackieg/dev/homelab/smart-home/home-assistant.yaml"
echo "  kubectl apply -f /home/mackieg/dev/homelab/media/media-stack.yaml"
echo ""
echo "✨ NFS storage infrastructure ready!"
