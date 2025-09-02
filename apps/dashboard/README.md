# Homelab Dashboard System

A touch-optimized dashboard for monitoring and controlling homelab infrastructure.

## Architecture

### Components

1. **Dashboard UI** (Vite + React)
   - Touch-optimized interface (1024x600)
   - Real-time metrics display
   - Control panels for services
   - WebSocket support for live updates

2. **Bare-Metal API** (Go)
   - Runs on host system
   - Collects system metrics
   - Executes privileged operations
   - WebSocket server for real-time data

3. **K3s Deployment**
   - UI runs in cluster
   - Prometheus/Grafana integration
   - Service discovery

## Features

- System metrics (CPU, Memory, Disk, Network)
- Docker container management
- K3s cluster status
- Service health monitoring
- Power management controls
- Network statistics
- Storage overview
- Quick actions panel

## Directory Structure

```
dashboard/
├── api/                 # Bare-metal API service
│   ├── cmd/
│   ├── systemd/
│   └── go.mod
├── ui/                  # Vite + React dashboard
│   ├── src/
│   ├── index.html
│   └── package.json
├── k8s/                 # Kubernetes manifests
│   ├── deployment.yaml
│   ├── service.yaml
│   └── ingress.yaml
├── deploy.sh           # Production deployment
├── dev.sh              # Development setup
└── kiosk-setup.sh      # Touchscreen kiosk mode
```

## Quick Start

### Development
```bash
# Install dependencies
cd ui && npm install && cd ../api && go mod download

# Start both services
./dev.sh
```

### Production Deployment
```bash
# Configure API URL in k8s/deployment.yaml (VITE_API_URL)
# Then deploy everything
./deploy.sh
```