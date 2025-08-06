#!/bin/bash

set -e

echo "=== Homelab Deployment Script ==="
echo "This will deploy all core services to your k3s cluster"
echo

# Check if kubectl is configured
if ! kubectl cluster-info &> /dev/null; then
    echo "ERROR: kubectl not configured or cluster not accessible"
    echo "Please ensure k3s is installed and KUBECONFIG is set"
    exit 1
fi

echo "Creating namespaces..."
kubectl apply -f k3s/namespaces.yaml

echo "Installing cert-manager..."
./k3s/install-cert-manager.sh

echo "Setting up access control..."
./k3s/setup-access-control.sh

echo "Installing Longhorn storage..."
cd apps/storage && ./install.sh && cd ../..

echo "Installing Pi-hole..."
cd apps/networking && ./install.sh && cd ../..

echo "Deploying static website..."
kubectl apply -f apps/web/static-site.yaml

echo "Deploying secure dashboard..."
kubectl apply -f apps/web/secure-dashboard.yaml

echo "Installing Kubernetes Dashboard..."
cd apps/monitoring && ./install-dashboard.sh && cd ../..

echo
echo "=== Deployment Complete ==="
echo
echo "Services will be available at:"
echo "  - https://mackie.house (static site)"
echo "  - https://pihole.mackie.house (Pi-hole admin)"
echo "  - https://longhorn.mackie.house (Longhorn UI)"
echo "  - https://dashboard.mackie.house (Kubernetes Dashboard)"
echo
echo "Next steps:"
echo "1. Update Pi-hole admin password in apps/networking/pihole-values.yaml"
echo "2. Configure your router to use Pi-hole as DNS server"
echo "3. Update cert-manager email in k3s/cert-manager.yaml"
echo "4. Configure Usenet credentials in apps/media/sabnzbd.yaml"
echo "5. Deploy media stack: cd apps/media && ./deploy-media-stack.sh"
echo "6. Follow setup guide in docs/MEDIA-STACK.md"