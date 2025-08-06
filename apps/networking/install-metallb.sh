#!/bin/bash

echo "Installing MetalLB..."

# Install MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml

echo "Waiting for MetalLB to be ready..."
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=90s

echo "Applying MetalLB configuration..."
kubectl apply -f metallb-config.yaml

echo "MetalLB installation complete!"
echo "LoadBalancer services will now get IPs from: 192.168.1.200-192.168.1.250"
echo "Update the IP range in metallb-config.yaml to match your network"