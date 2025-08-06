#!/bin/bash

echo "Installing Kubernetes Dashboard..."

# Add kubernetes-dashboard Helm repository
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm repo update

# Create namespace and service account
kubectl apply -f kubernetes-dashboard.yaml

# Install Kubernetes Dashboard
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
  --namespace kubernetes-dashboard \
  --create-namespace \
  -f kubernetes-dashboard-values.yaml \
  --wait

echo "Waiting for dashboard to be ready..."
kubectl wait --for=condition=Ready pods --all -n kubernetes-dashboard --timeout=300s

echo ""
echo "Kubernetes Dashboard installation complete!"
echo "Access at: https://dashboard.mackie.house"
echo ""
echo "To get the admin token for login:"
echo "kubectl -n kubernetes-dashboard create token admin-user"
echo ""
echo "Or use the permanent token:"
echo "kubectl get secret admin-user-token -n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 --decode"