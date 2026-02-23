# Homelab K3s Deployment Plan

## Current Status
- **Date**: 2025-11-16
- **Server**: labnuc
- **K3s Status**: ✅ Installed and running (v1.33.5+k3s1)
- **Node**: labnuc (Ready, control-plane,master, 103m old)

## Issue to Resolve
kubectl cannot connect to K3s cluster from user context. Need to configure kubeconfig.

## Next Steps After Restart

### 1. Configure kubectl Access (5 min)
```bash
# Copy K3s kubeconfig to user home directory
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown mackieg:mackieg ~/.kube/config
chmod 600 ~/.kube/config

# Verify it works
kubectl get nodes
kubectl get namespaces
```

Expected output:
```
NAME     STATUS   ROLES                  AGE    VERSION
labnuc   Ready    control-plane,master   XXXm   v1.33.5+k3s1
```

### 2. Validate Configuration Files (5 min)
```bash
cd /home/mackieg/dev/homelab
./setup/validate-simple.sh
```

This will check all YAML files for syntax errors before deployment.

### 3. Deploy Components in Order (30-40 min)

#### Phase 1: Storage Layer (10 min)
```bash
./setup/deploy-component.sh storage
```

This deploys:
- MinIO (object storage)
- Longhorn (persistent volume management)
- NFS provisioner
- FileBrowser
- Nextcloud

Wait for all pods to be ready:
```bash
kubectl get pods -n storage -w
```

#### Phase 2: Core Services (10 min)
```bash
./setup/deploy-component.sh services
```

This deploys:
- Pi-hole (DNS and ad blocking)
- Portainer (container management UI)
- Homer (dashboard)
- Vaultwarden (password manager)
- Uptime Kuma (monitoring)

Wait for all pods:
```bash
kubectl get pods -n services -w
```

#### Phase 3: Smart Home (5 min)
```bash
./setup/deploy-component.sh smart-home
```

This deploys:
- Home Assistant
- ESPHome
- HVAC automation
- Smart home monitoring

Wait for pods:
```bash
kubectl get pods -n home-automation -w
```

#### Phase 4: Media Stack (10 min)
```bash
./setup/deploy-component.sh media
```

This deploys:
- Jellyfin (media server)
- Radarr (movie management)
- Sonarr (TV show management)
- SABnzbd (usenet downloader)
- Prowlarr (indexer manager)
- Jackett (torrent indexer)

Wait for pods:
```bash
kubectl get pods -n media -w
```

#### Phase 5: Monitoring (5 min)
```bash
./setup/deploy-component.sh monitoring
```

This deploys:
- Grafana
- Prometheus
- Home Assistant integration dashboards

Wait for pods:
```bash
kubectl get pods -n monitoring -w
```

#### Phase 6: Dashboard UI (Optional - 5 min)
```bash
./setup/deploy-component.sh dashboard-ui
./setup/deploy-component.sh touchscreen
```

### 4. Verify Deployment (5 min)
```bash
# Run comprehensive health checks
./setup/health-check.sh

# Check all namespaces
kubectl get pods --all-namespaces

# Check services
kubectl get svc --all-namespaces

# Verify ingress
kubectl get ingress --all-namespaces
```

### 5. Access Services

#### Add to /etc/hosts (or configure DNS)
```bash
sudo nano /etc/hosts
```

Add these entries (replace with your actual server IP):
```
192.168.0.6 homer.homelab.local
192.168.0.6 homeassistant.homelab.local
192.168.0.6 jellyfin.homelab.local
192.168.0.6 grafana.homelab.local
192.168.0.6 pihole.homelab.local
192.168.0.6 portainer.homelab.local
192.168.0.6 nextcloud.homelab.local
192.168.0.6 vault.homelab.local
192.168.0.6 mobile.homelab.local
```

#### Service URLs
- **Homer Dashboard**: http://homer.homelab.local
- **Home Assistant**: http://homeassistant.homelab.local
- **Jellyfin**: http://jellyfin.homelab.local
- **Grafana**: http://grafana.homelab.local
- **Pi-hole**: http://pihole.homelab.local/admin
- **Portainer**: http://portainer.homelab.local
- **Nextcloud**: http://nextcloud.homelab.local
- **Vaultwarden**: http://vault.homelab.local

## Alternative: Complete Deployment (One Command)

Instead of deploying components individually, you can run:
```bash
./setup/deploy-complete-homelab.sh
```

This will deploy all 150+ resources in the correct order automatically.

## Troubleshooting

### If pods are stuck in Pending
```bash
kubectl describe pod <pod-name> -n <namespace>
```

### If services aren't accessible
```bash
# Check ingress
kubectl get ingress --all-namespaces

# Check service endpoints
kubectl get endpoints --all-namespaces
```

### Run the troubleshooting script
```bash
./setup/troubleshoot.sh
```

### Fix common issues automatically
```bash
./setup/fix-common-issues.sh
```

## Important Configuration Notes

### Security
Before deploying, update passwords in these files:
- Replace all `changeme` passwords
- Update API keys and secrets
- Configure authentication for services

### Storage
- MinIO will need persistent storage
- Longhorn will use local disk
- Ensure you have enough disk space (recommend 128GB minimum)

### Network
- Default configuration assumes 192.168.0.x network
- Update IP addresses if your network is different
- Configure firewall rules if needed

## Resource Requirements

**Current Single NUC Setup:**
- CPU: Intel NUC (control-plane,master)
- Expected RAM usage: ~8GB for all services
- Expected storage: ~50GB for apps, more for media
- Network: 1Gbps recommended

## Post-Deployment Tasks

1. **Configure Pi-hole**
   - Set admin password
   - Add blocklists
   - Configure DHCP to use Pi-hole as DNS

2. **Configure Home Assistant**
   - Initial setup wizard
   - Add integrations
   - Configure automations

3. **Configure Jellyfin**
   - Add media libraries
   - Set up users
   - Configure hardware transcoding

4. **Set up backups**
   ```bash
   ./setup/backup-homelab.sh
   ```

5. **Configure GitOps (Optional)**
   ```bash
   ./setup/deploy-gitops.sh
   ```

## Monitoring Deployment Progress

Watch all pods across namespaces:
```bash
watch -n 2 'kubectl get pods --all-namespaces'
```

Check cluster events:
```bash
kubectl get events --all-namespaces --sort-by='.lastTimestamp'
```

## Expected Timeline

- kubectl setup: 5 min
- Validation: 5 min
- Storage deployment: 10 min
- Services deployment: 10 min
- Smart home deployment: 5 min
- Media deployment: 10 min
- Monitoring deployment: 5 min
- Verification: 5 min

**Total: ~55 minutes**

## Notes

- K3s was installed with `--disable traefik` as configured
- Using custom ingress from /k3s/ingress-config.yaml
- Node is labeled as AMD64 architecture
- All configurations are in /home/mackieg/dev/homelab

## Resume Point

After restart, start with:
```bash
cd /home/mackieg/dev/homelab
kubectl get nodes
```

If kubectl works, proceed to Phase 1 (Storage Layer).
