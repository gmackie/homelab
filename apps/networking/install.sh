#!/bin/bash

echo "Installing Pi-hole..."

# Add mojo2600 Helm repository for Pi-hole
helm repo add mojo2600 https://mojo2600.github.io/pihole-kubernetes/
helm repo update

# Install Pi-hole
helm upgrade --install pihole mojo2600/pihole \
  --namespace pihole \
  --create-namespace \
  -f pihole-values.yaml \
  --wait

echo "Pi-hole installation complete!"
echo "Access admin UI at: https://pihole.mackie.house/admin"
echo "Remember to update your router's DNS settings to use Pi-hole"