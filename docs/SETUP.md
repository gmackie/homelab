# Homelab Setup Guide

## Prerequisites

- Ubuntu Server 22.04 LTS or similar on your NUC
- At least 16GB RAM and 256GB storage
- Static IP configured for the NUC
- Domain name (mackie.house) pointed to your home IP
- Port forwarding configured for ports 80 and 443

## Installation Steps

### 1. Install K3s

```bash
cd k3s
sudo ./install.sh
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

### 2. Install Core Services

```bash
# Run the deployment script
cd ../scripts
./deploy-all.sh
```

### 3. Configure DNS

1. Update your router to use Pi-hole as DNS server (typically 192.168.1.53)
2. Add local DNS entries in Pi-hole for all *.mackie.house domains

### 4. Update Secrets

Important files to update before production use:
- `k3s/cert-manager.yaml` - Update email address
- `apps/networking/pihole-values.yaml` - Update admin password
- `apps/monitoring/kube-prometheus-stack-values.yaml` - Update Grafana password
- `apps/monitoring/influxdb-values.yaml` - Update admin credentials

### 5. Deploy Additional Services

```bash
# Monitoring Stack
cd apps/monitoring
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add influxdata https://helm.influxdata.com/
helm repo update

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f kube-prometheus-stack-values.yaml

helm upgrade --install influxdb influxdata/influxdb2 \
  --namespace monitoring \
  -f influxdb-values.yaml

# Media Stack
kubectl apply -f apps/media/jellyfin.yaml
kubectl apply -f apps/media/arr-stack.yaml

# Home Automation
kubectl apply -f apps/home-automation/home-assistant.yaml
kubectl apply -f apps/home-automation/node-red.yaml
```

## Service URLs

### Public Services (accessible from internet)
- https://mackie.house - Main landing page
- https://secure.mackie.house - Secure dashboard (requires authentication)

### Local-Only Services (only accessible from local network)
- https://pihole.mackie.house/admin - Pi-hole DNS
- https://longhorn.mackie.house - Storage management
- https://grafana.mackie.house - Monitoring dashboards
- https://prometheus.mackie.house - Metrics
- https://alertmanager.mackie.house - Alerts
- https://influxdb.mackie.house - Time series database
- https://dashboard.mackie.house - Kubernetes Dashboard
- https://jellyfin.mackie.house - Media server (can be made public if desired)
- https://sonarr.mackie.house - TV show management
- https://radarr.mackie.house - Movie management
- https://ha.mackie.house - Home Assistant
- https://nodered.mackie.house - Node-RED

## Access Control

### Local Network Access
Services marked as local-only are restricted to connections from:
- 192.168.0.0/16
- 10.0.0.0/8
- 172.16.0.0/12
- 127.0.0.1/32

### External Access
The secure dashboard at https://secure.mackie.house requires basic authentication.
Update credentials in `k3s/traefik-config.yaml`:
```bash
htpasswd -nb username password | base64
```

## Backup Strategy

1. **Longhorn Backups**: Configure S3 backup target in Longhorn UI
2. **Config Backups**: Regular backups of this git repository
3. **Database Backups**: Set up CronJobs for database dumps

## Scaling to Multiple Nodes

When ready to add more NUCs:

1. Install K3s on additional nodes:
   ```bash
   curl -sfL https://get.k3s.io | K3S_URL=https://<master-ip>:6443 K3S_TOKEN=<node-token> sh -
   ```

2. Update Longhorn replica count in `apps/storage/longhorn-values.yaml`

3. Consider using MetalLB for load balancing:
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml
   ```

## Troubleshooting

- Check pod status: `kubectl get pods -A`
- View logs: `kubectl logs -n <namespace> <pod-name>`
- Check ingress: `kubectl get ingress -A`
- Verify certificates: `kubectl get certificate -A`