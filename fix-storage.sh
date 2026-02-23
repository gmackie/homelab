#!/bin/bash
echo "Fixing storage classes in manifests..."

for file in storage/network-storage.yaml services/homelab-services.yaml smart-home/home-assistant.yaml media/media-stack.yaml; do
  echo "Processing $file..."
  sed -i.bak 's/storageClassName: longhorn-ssd/storageClassName: local-path/g' "$file"
  sed -i 's/storageClassName: longhorn/storageClassName: local-path/g' "$file"
done

echo "✅ Manifests updated to use local-path storage"
