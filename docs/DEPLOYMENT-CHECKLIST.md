# Homelab Deployment Checklist

## Pre-Deployment

- [ ] NUC with Ubuntu Server 22.04 LTS installed
- [ ] Static IP configured for NUC
- [ ] Domain (mackie.house) DNS configured
- [ ] Router port forwarding (80, 443, 51820/UDP for VPN)
- [ ] At least 16GB RAM, 256GB storage

## Core Infrastructure

- [ ] Install K3s: `cd k3s && sudo ./install.sh`
- [ ] Export KUBECONFIG: `export KUBECONFIG=/etc/rancher/k3s/k3s.yaml`
- [ ] Update email in `k3s/cert-manager.yaml`
- [ ] Run core deployment: `cd scripts && ./deploy-all.sh`
- [ ] Apply access control: `cd k3s && ./setup-access-control.sh`
- [ ] Update basic auth in `k3s/traefik-config.yaml`
- [ ] Apply resource quotas: `kubectl apply -f k3s/resource-quotas.yaml`

## Storage & Networking

- [ ] Configure Longhorn backup target (S3)
- [ ] Update Pi-hole admin password
- [ ] Configure router to use Pi-hole DNS (192.168.1.53)
- [ ] Install MetalLB: `cd apps/networking && ./install-metallb.sh`
- [ ] Update IP range in `metallb-config.yaml`

## Monitoring Stack

- [ ] Deploy Prometheus stack: `helm install...` (see SETUP.md)
- [ ] Update Grafana admin password
- [ ] Deploy InfluxDB
- [ ] Configure Exportarr API keys after media stack
- [ ] Apply alerting rules: `kubectl apply -f apps/monitoring/alerts.yaml`
- [ ] Configure AlertManager webhooks/email

## Media Stack

- [ ] Update Usenet credentials in `sabnzbd.yaml`
- [ ] Deploy media stack: `cd apps/media && ./deploy-media-stack.sh`
- [ ] Configure SABnzbd with provider
- [ ] Add indexers to Prowlarr
- [ ] Connect Sonarr/Radarr to Prowlarr
- [ ] Configure Jellyfin libraries
- [ ] Set up Overseerr with services

## Backup & Security

- [ ] Configure S3 credentials in `backup/backup-cronjobs.yaml`
- [ ] Deploy backup jobs: `kubectl apply -f apps/backup/`
- [ ] Generate WireGuard keys
- [ ] Update VPN config in `wireguard-vpn.yaml`
- [ ] Deploy VPN: `kubectl apply -f apps/networking/wireguard-vpn.yaml`
- [ ] Configure certificate monitoring

## Post-Deployment

- [ ] Verify all services are accessible
- [ ] Test local-only access restrictions
- [ ] Configure Grafana dashboards
- [ ] Set up mobile apps (Jellyfin, Home Assistant)
- [ ] Document all API keys securely
- [ ] Test backup restoration
- [ ] Configure UPS monitoring (if applicable)

## Service URLs

### External Access
- https://mackie.house - Landing page
- https://secure.mackie.house - Monitoring dashboard (auth required)
- https://requests.mackie.house - Media requests

### Local Network Only
- https://dashboard.mackie.house - K8s Dashboard
- https://pihole.mackie.house - Pi-hole
- https://longhorn.mackie.house - Storage
- https://grafana.mackie.house - Grafana
- https://prometheus.mackie.house - Prometheus
- https://alertmanager.mackie.house - Alerts
- https://influxdb.mackie.house - InfluxDB
- https://sonarr.mackie.house - TV management
- https://radarr.mackie.house - Movie management
- https://prowlarr.mackie.house - Indexers
- https://sabnzbd.mackie.house - Downloads
- https://bazarr.mackie.house - Subtitles
- https://jellyfin.mackie.house - Media server
- https://ha.mackie.house - Home Assistant
- https://nodered.mackie.house - Node-RED

## Maintenance Tasks

### Daily
- Check backup job status
- Monitor disk usage
- Review any alerts

### Weekly
- Check for system updates
- Review Grafana dashboards
- Verify certificate status

### Monthly
- Test backup restoration
- Review resource usage trends
- Update container images
- Security audit

## Troubleshooting Commands

```bash
# Check pod status
kubectl get pods -A | grep -v Running

# View logs
kubectl logs -n <namespace> <pod-name>

# Check certificates
kubectl get certificates -A

# Check storage
kubectl get pvc -A

# View events
kubectl get events -A --sort-by='.lastTimestamp'

# Check ingress
kubectl get ingress -A
```