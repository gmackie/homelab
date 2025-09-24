# 🏠 Multi-Architecture Kubernetes Homelab

A comprehensive, power-efficient Kubernetes homelab featuring multi-architecture support (AMD64 + ARM64 + ARM), smart home integration, media automation, and a beautiful touchscreen interface optimized for 1024x600 displays.

## 🎯 Key Features

- **🏗️ Multi-Architecture Cluster**: Seamlessly runs AMD64, ARM64, and ARM nodes in a single cluster
- **⚡ Power Optimized**: Targets ~79W total consumption with intelligent workload placement
- **📱 Touchscreen Interface**: Beautiful dashboard optimized for 1024x600 display
- **🏠 Smart Home Platform**: Full Home Assistant integration with room temperature monitoring
- **🎬 Media Automation**: Complete *arr stack with Jellyfin and Usenet support
- **📊 Advanced Monitoring**: Grafana dashboards with Home Assistant metrics integration
- **🔒 Security First**: Network isolation, secret management, and automated backups
- **🚀 GitOps Ready**: ArgoCD for declarative cluster management
- **📲 Mobile Access**: Progressive Web App for remote monitoring and control

## 📋 Prerequisites

### Hardware Requirements
- **Minimum**: 1 NUC (AMD64) + 2 Raspberry Pi 4 (ARM64) + 1 Raspberry Pi Zero (ARM)
- **Recommended**: 2 NUCs + 2 Raspberry Pi 4 + 2 Raspberry Pi Zero
- **Storage**: At least 256GB SSD on NUC, 64GB SD cards for Pis
- **Network**: Gigabit ethernet for all nodes (except Pi Zero - WiFi acceptable)
- **Display**: 1024x600 touchscreen (optional but recommended)

### Software Requirements
- **OS**: Ubuntu Server 22.04 LTS (NUC) or Raspberry Pi OS Lite 64-bit (Pis)
- **Kubernetes**: K3s (lightweight, perfect for homelab)
- **Local Tools**: kubectl, git, curl

## 🚀 Quick Start

### 1. Clone the Repository
```bash
git clone git@git.gmac.io:gmackie/homelab.git
cd homelab
```

### 2. Set Up Your NUC (Master Node)

```bash
# Install K3s on NUC (master node)
curl -sfL https://get.k3s.io | sh -s - \
  --write-kubeconfig-mode 644 \
  --disable traefik \
  --node-label "kubernetes.io/arch=amd64" \
  --node-label "node-role.kubernetes.io/master=true"

# Get the node token for worker nodes
sudo cat /var/lib/rancher/k3s/server/node-token

# Export kubeconfig
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Verify installation
kubectl get nodes
```

### 3. Add Worker Nodes (Optional - can start with single NUC)

On each Raspberry Pi:
```bash
# For ARM64 nodes (Raspberry Pi 4)
curl -sfL https://get.k3s.io | K3S_URL=https://<NUC_IP>:6443 \
  K3S_TOKEN=<NODE_TOKEN> sh -s - \
  --node-label "kubernetes.io/arch=arm64"

# For ARM nodes (Raspberry Pi Zero)
curl -sfL https://get.k3s.io | K3S_URL=https://<NUC_IP>:6443 \
  K3S_TOKEN=<NODE_TOKEN> sh -s - \
  --node-label "kubernetes.io/arch=arm"
```

### 4. Validate Configuration
```bash
# Check prerequisites
./setup/check-prerequisites.sh

# Validate all YAML files
./setup/validate-simple.sh
```

### 5. Deploy the Homelab

#### Option A: Complete Automated Deployment (Recommended)
```bash
# Deploy everything in the correct order
./setup/deploy-complete-homelab.sh
```

#### Option B: GitOps Deployment with ArgoCD
```bash
# Deploy ArgoCD and let it manage everything
./setup/deploy-gitops.sh
```

#### Option C: Manual Component Deployment
```bash
# Deploy components individually
./setup/deploy-component.sh storage
./setup/deploy-component.sh services
./setup/deploy-component.sh smart-home
./setup/deploy-component.sh media
./setup/deploy-component.sh monitoring
./setup/deploy-component.sh dashboard
```

### 6. Configure Touchscreen Display
Point your 1024x600 touchscreen browser to:
```
http://homer.homelab.local
```

## 📦 Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    HOMELAB CLUSTER                          │
├─────────────────────────────────────────────────────────────┤
│  NUC (AMD64) - 45W                                         │
│  • Jellyfin (transcoding)                                  │
│  • GitLab CE                                               │
│  • PostgreSQL                                              │
│  • Heavy compute workloads                                 │
├─────────────────────────────────────────────────────────────┤
│  Raspberry Pi 4 (ARM64) - 7W each                          │
│  • Home Assistant                                          │
│  • Grafana                                                 │
│  • ArgoCD                                                  │
│  • Balanced workloads                                      │
├─────────────────────────────────────────────────────────────┤
│  Raspberry Pi Zero (ARM) - 3W each                         │
│  • Pi-hole                                                 │
│  • MQTT Broker                                            │
│  • Backup scheduler                                        │
│  • Ultra-low power services                                │
└─────────────────────────────────────────────────────────────┘
Total Power Target: ~79W (vs 200W+ traditional setup)
```

## 🗂️ Repository Structure

```
homelab/
├── apps/                    # Application deployments
│   ├── dashboard/          # Cluster dashboard UI & API
│   └── touchscreen-monitor/ # Touchscreen-optimized interface
├── autoscaling/            # HPA, VPA, and power optimization
├── development/            # Dev tools (Code-Server, GitLab, Jenkins)
├── disaster-recovery/      # Backup and restore automation
├── gitops/                # ArgoCD applications and bootstrap
├── integrations/          # External APIs and mobile backend
├── media/                 # Media stack (Jellyfin, *arr apps)
├── monitoring/            # Grafana dashboards and Prometheus
├── networking/            # Ingress, load balancing, tunnels
├── services/              # Core services (Pi-hole, Portainer)
├── setup/                 # Deployment and management scripts
├── smart-home/            # Home Assistant and IoT devices
└── storage/               # Network storage (MinIO, Nextcloud)
```

## 🌐 Service URLs

Once deployed, access your services at:

| Service | URL | Purpose |
|---------|-----|---------|
| 🏠 **Homer Dashboard** | http://homer.homelab.local | Main touchscreen interface |
| 📱 **Mobile PWA** | http://mobile.homelab.local | Phone/tablet access |
| 🏠 **Home Assistant** | http://homeassistant.homelab.local | Smart home control |
| 📊 **Grafana** | http://grafana.homelab.local | Metrics and monitoring |
| 🎬 **Jellyfin** | http://jellyfin.homelab.local | Media streaming |
| 📥 **Radarr** | http://radarr.homelab.local | Movie automation |
| 📺 **Sonarr** | http://sonarr.homelab.local | TV show automation |
| 💾 **SABnzbd** | http://sabnzbd.homelab.local | Usenet downloads |
| 🛡️ **Pi-hole** | http://pihole.homelab.local/admin | Ad blocking |
| 📦 **Portainer** | http://portainer.homelab.local | Container management |
| ☁️ **Nextcloud** | http://nextcloud.homelab.local | File sync & share |
| 🔐 **Vaultwarden** | http://vault.homelab.local | Password manager |
| 🚀 **ArgoCD** | http://argocd.homelab.local | GitOps dashboard |
| 💻 **Code-Server** | http://code.homelab.local | Web-based IDE |

## 🔧 Management Scripts

### Deployment
- `./setup/deploy-complete-homelab.sh` - Complete cluster deployment
- `./setup/deploy-component.sh <component>` - Deploy individual components
- `./setup/deploy-gitops.sh` - Deploy ArgoCD for GitOps management

### Validation & Health
- `./setup/check-prerequisites.sh` - Verify system requirements
- `./setup/validate-simple.sh` - Validate YAML configurations
- `./setup/health-check.sh` - Comprehensive health checks
- `./setup/verify-deployment.sh` - Post-deployment verification

### Troubleshooting
- `./setup/troubleshoot.sh` - Interactive troubleshooting tool
- `./setup/fix-common-issues.sh` - Automated fixes for common problems

### Backup & Recovery
- `./setup/backup-homelab.sh` - Backup configurations
- `./disaster-recovery/restore-data.sh` - Restore from backup

## 🎨 Touchscreen Interface

The homelab includes a custom interface optimized for 1024x600 touchscreens:

- **Homer Dashboard**: Beautiful service directory with status indicators
- **Real-time Monitoring**: Live cluster metrics and power consumption
- **Temperature Display**: Room-by-room temperature monitoring
- **Quick Actions**: One-touch access to common tasks
- **Screensaver Mode**: Load-dependent animations when idle

Configure by editing: `services/homelab-services.yaml` (Homer config)

## 🔐 Security Notes

⚠️ **Important**: All credentials in this repository are placeholders!

Before deployment:
1. Search and replace all default passwords:
   ```bash
   grep -r "changeme\|your-.*-key\|edgepassword" .
   ```

2. Generate secure passwords:
   ```bash
   openssl rand -base64 32
   ```

3. Store secrets properly:
   ```bash
   kubectl create secret generic my-secret \
     --from-literal=password="$(openssl rand -base64 32)"
   ```

See `SECURITY_NOTES.md` for detailed security guidelines.

## 🚦 Power Management

The cluster automatically optimizes power consumption:

- **Day Mode** (8 AM - 10 PM): All services active
- **Night Mode** (10 PM - 8 AM): Non-critical services scaled down
- **Weekend Mode**: Media services scaled up
- **Temperature-based**: Automatic throttling if nodes overheat

Target consumption: **79W** (actual may vary based on load)

## 📱 Mobile Access

### Progressive Web App
Access the mobile-optimized interface at:
```
http://mobile.homelab.local
```

Features:
- Install as app on iOS/Android
- Real-time WebSocket updates
- Touch-optimized controls
- Offline capability

### API Access
Secure API endpoint for external integrations:
```
http://api.homelab.local
```

Includes rate limiting, authentication, and comprehensive documentation.

## 🔄 CI/CD Integration

### GitHub Actions
Automated workflows for:
- YAML validation on push
- Security scanning
- Deployment planning
- Architecture compatibility checks

### GitLab CI/CD
Self-hosted GitLab instance includes:
- Container registry
- CI/CD pipelines
- Code quality scanning
- Deployment automation

## 🆘 Disaster Recovery

### Automated Backups
- **Daily**: Configuration backups
- **Weekly**: Full system backups
- **Retention**: 7 daily, 4 weekly backups

### Emergency Recovery
```bash
# Restore from latest backup
./disaster-recovery/restore-data.sh latest

# Restore specific service
./disaster-recovery/restore-data.sh homeassistant 20241201
```

## 📊 Monitoring & Alerts

### Grafana Dashboards
Pre-configured dashboards for:
- Smart home temperature monitoring
- Media service statistics
- Cluster resource usage
- Power consumption tracking

### Alert Channels
- Telegram notifications
- Discord webhooks
- Email alerts
- Home Assistant automations

## 🏠 Domain Configuration

Primary domain: `mackie.house` (or configure your own)

For custom domains:
1. Update ingress configurations in each service YAML
2. Configure DNS A records pointing to your load balancer IP
3. Optional: Set up Cloudflare tunnel for external access

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Validate changes: `./setup/validate-simple.sh`
4. Test deployment: `./setup/deploy-component.sh <component>`
5. Submit a pull request

## 📄 License

MIT License - See `LICENSE` file for details

## 🙏 Acknowledgments

- **K3s** - Lightweight Kubernetes distribution
- **Home Assistant** - Smart home platform
- **Jellyfin** - Media server
- **ArgoCD** - GitOps continuous delivery
- **Homer** - Static dashboard

## 💬 Support

- **Issues**: [GitHub Issues](https://github.com/gmackie/homelab/issues)
- **GitLab**: [git.gmac.io](https://git.gmac.io/gmackie/homelab)
- **Documentation**: Check `/docs` folder for detailed guides

## 🚀 Tonight's Setup Plan

### Step 1: Prepare the NUC
1. Install Ubuntu Server 22.04 LTS
2. Update system: `sudo apt update && sudo apt upgrade -y`
3. Install K3s using the command above
4. Clone this repository

### Step 2: Initial Deployment
Start with single-node deployment on your NUC:
```bash
# Deploy core services first
./setup/deploy-component.sh storage
./setup/deploy-component.sh services
./setup/deploy-component.sh smart-home

# Then add media and monitoring
./setup/deploy-component.sh media
./setup/deploy-component.sh monitoring
```

### Step 3: Verify Everything Works
```bash
# Run health check
./setup/health-check.sh

# Check service status
kubectl get pods --all-namespaces
```

### Step 4: Access Your Services
- Homer Dashboard: `http://<NUC_IP>:80`
- Home Assistant: `http://<NUC_IP>:8123`
- Jellyfin: `http://<NUC_IP>:8096`

You can add Raspberry Pis later for true multi-architecture support!

---

**Built with ❤️ for the homelab community**

*Power-efficient, multi-architecture, enterprise-grade homelab that fits in your closet!*