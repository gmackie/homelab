#!/bin/bash

# K3s installation script for homelab
# Single node configuration with room for expansion

set -e

echo "Installing K3s for homelab..."

# Install K3s with:
# - Traefik enabled (default ingress)
# - Default local storage
# - Metrics server
# - Service load balancer
curl -sfL https://get.k3s.io | sh -s - \
  --write-kubeconfig-mode 644 \
  --disable servicelb \
  --cluster-init

echo "Waiting for K3s to be ready..."
sudo kubectl wait --for=condition=Ready node --all --timeout=300s

echo "K3s installation complete!"
echo "Export kubeconfig: export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"