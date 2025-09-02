#!/bin/bash

set -e

echo "🚀 Deploying Homelab Dashboard"

# Build and install the bare-metal API
echo "📦 Building bare-metal API..."
cd api
go build -o dashboard-api cmd/server/main.go
sudo mkdir -p /opt/dashboard-api
sudo cp dashboard-api /opt/dashboard-api/
sudo cp systemd/dashboard-api.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable dashboard-api
sudo systemctl restart dashboard-api
cd ..

# Build the UI Docker image
echo "🎨 Building UI Docker image..."
cd ui
docker build -t homelab-dashboard:latest .
cd ..

# Deploy to Kubernetes
echo "☸️ Deploying to Kubernetes..."
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml

echo "✅ Deployment complete!"
echo ""
echo "Access the dashboard at:"
echo "  - Direct NodePort: http://<node-ip>:30080"
echo "  - Via Ingress: http://dashboard.homelab.local"
echo ""
echo "API running on: http://localhost:8080"
echo ""
echo "For touchscreen kiosk mode, open browser in fullscreen at the dashboard URL"