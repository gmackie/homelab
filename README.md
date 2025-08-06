# Homelab Configuration

K3s-based homelab running on a single NUC with plans for multi-node expansion.

## Stack

### Infrastructure
- **K3s** - Lightweight Kubernetes
- **Traefik** - Ingress controller (included with K3s)
- **Cert-Manager** - SSL certificates
- **Longhorn** - Distributed storage
- **Pi-hole** - Network-wide ad blocking and DNS

### Monitoring
- **Prometheus** - Metrics collection
- **Grafana** - Visualization
- **InfluxDB** - Time series database
- **Exportarr** - Arr stack metrics exporter
- **Kubernetes Dashboard** - Cluster management UI

### Home Automation
- **Home Assistant** - Smart home platform
- **Node-RED** - Automation workflows

### Media
- **Jellyfin** - Media server
- **Sonarr** - TV show management
- **Radarr** - Movie management
- **Bazarr** - Subtitle management
- **Jackett** - Torrent indexer
- **SABnzbd** - Usenet downloader

### Web
- Static website hosted at mackie.house

## Directory Structure

```
.
├── k3s/               # K3s cluster configuration
├── apps/              # Application deployments
│   ├── monitoring/    # Prometheus, Grafana, InfluxDB
│   ├── media/         # Jellyfin, *arr stack
│   ├── home-automation/ # Home Assistant, Node-RED
│   ├── web/           # Static website
│   ├── storage/       # Longhorn storage
│   └── networking/    # Pi-hole DNS
├── scripts/           # Utility scripts
└── docs/              # Documentation
```

## Getting Started

1. Install K3s on your NUC
2. Configure kubectl to connect to your cluster
3. Deploy applications using the provided Helm charts and manifests

## Domain

Primary domain: `mackie.house`