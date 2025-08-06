#!/bin/bash

echo "Installing cert-manager..."

# Add Jetstack Helm repository
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install cert-manager
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.13.3 \
  --set installCRDs=true \
  --wait

echo "Waiting for cert-manager to be ready..."
kubectl wait --for=condition=Ready pods --all -n cert-manager --timeout=300s

echo "Applying ClusterIssuers..."
kubectl apply -f cert-manager.yaml

echo "cert-manager installation complete!"