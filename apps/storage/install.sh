#!/bin/bash

echo "Installing Longhorn storage..."

# Add Longhorn Helm repository
helm repo add longhorn https://charts.longhorn.io
helm repo update

# Install Longhorn
helm upgrade --install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  -f longhorn-values.yaml \
  --wait

echo "Longhorn installation complete!"
echo "Access UI at: https://longhorn.mackie.house"