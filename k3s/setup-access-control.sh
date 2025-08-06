#!/bin/bash

echo "Setting up access control middleware..."

# Apply Traefik middleware configurations
kubectl apply -f traefik-config.yaml

echo "Waiting for middleware to be ready..."
sleep 5

echo ""
echo "Access control setup complete!"
echo ""
echo "Configuration:"
echo "- Local-only services: Only accessible from 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12"
echo "- Secure dashboard: Accessible externally with basic auth at https://secure.mackie.house"
echo ""
echo "IMPORTANT: Update the basic auth secret in traefik-config.yaml"
echo "Generate new credentials with: htpasswd -nb username password | base64"