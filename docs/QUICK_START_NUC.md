# 🚀 Quick Start Guide: NUC Setup Tonight

This guide will help you get your homelab running on a single NUC tonight, with the ability to expand to a multi-node cluster later.

## 📋 What You Need

- **1 Intel NUC** with at least 16GB RAM and 256GB storage
- **Ubuntu Server 22.04 LTS** USB installer
- **Network connection** (ethernet preferred)
- **About 1 hour** of time

## 🛠️ Step-by-Step Setup

### Step 1: Install Ubuntu Server (15 minutes)

1. Create Ubuntu Server USB installer:
   ```bash
   # On another machine, download Ubuntu Server 22.04 LTS
   # Use Rufus (Windows) or Etcher (Mac/Linux) to create bootable USB
   ```

2. Boot NUC from USB and install Ubuntu Server:
   - Choose minimal installation
   - Enable OpenSSH server
   - Don't install any additional snaps
   - Set username and password

3. After installation, SSH into your NUC:
   ```bash
   ssh username@<NUC_IP>
   ```

### Step 2: Prepare the System (5 minutes)

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install required tools
sudo apt install -y curl git vim htop net-tools

# Set static IP (optional but recommended)
# Edit netplan configuration
sudo vim /etc/netplan/00-installer-config.yaml
```

Example netplan for static IP:
```yaml
network:
  ethernets:
    enp0s3:  # Your interface name
      dhcp4: no
      addresses:
        - 192.168.1.100/24  # Your desired IP
      gateway4: 192.168.1.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
  version: 2
```

Apply netplan:
```bash
sudo netplan apply
```

### Step 3: Install K3s (5 minutes)

```bash
# Install K3s with specific configuration
curl -sfL https://get.k3s.io | sh -s - \
  --write-kubeconfig-mode 644 \
  --disable traefik \
  --node-label "kubernetes.io/arch=amd64" \
  --node-label "node-role.kubernetes.io/master=true"

# Make kubectl accessible
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
export KUBECONFIG=~/.kube/config

# Add to bashrc for persistence
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc

# Verify installation
kubectl get nodes
# You should see your NUC as Ready
```

### Step 4: Clone the Repository (2 minutes)

```bash
# Clone the homelab repository
cd ~
git clone https://github.com/gmackie/homelab.git
cd homelab

# Make scripts executable
chmod +x setup/*.sh
chmod +x disaster-recovery/*.sh
```

### Step 5: Configure Secrets (5 minutes)

```bash
# Generate random passwords
PIHOLE_PASS=$(openssl rand -base64 32)
GRAFANA_PASS=$(openssl rand -base64 32)
VAULTWARDEN_TOKEN=$(openssl rand -base64 48)

# Replace default passwords in configs
find . -type f -name "*.yaml" -exec sed -i "s/changeme/$PIHOLE_PASS/g" {} \;

# Create secrets file (don't commit this!)
cat > secrets.env << EOF
PIHOLE_PASSWORD=$PIHOLE_PASS
GRAFANA_PASSWORD=$GRAFANA_PASS
VAULTWARDEN_ADMIN_TOKEN=$VAULTWARDEN_TOKEN
EOF

echo "⚠️  Save these passwords somewhere safe!"
cat secrets.env
```

### Step 6: Deploy Core Services (10 minutes)

```bash
# Validate configurations first
./setup/validate-simple.sh

# Deploy storage layer
./setup/deploy-component.sh storage

# Wait for storage to be ready
sleep 30
kubectl get pods -n storage

# Deploy essential services
./setup/deploy-component.sh services

# Deploy smart home platform
./setup/deploy-component.sh smart-home

# Check deployment status
kubectl get pods --all-namespaces
```

### Step 7: Deploy Media & Monitoring (10 minutes)

```bash
# Deploy media services
./setup/deploy-component.sh media

# Deploy monitoring
./setup/deploy-component.sh monitoring

# Deploy touchscreen dashboard
./setup/deploy-component.sh dashboard

# Run health check
./setup/health-check.sh
```

### Step 8: Configure DNS/Hosts (5 minutes)

For testing without proper DNS, add entries to your local machine's hosts file:

**On Windows:** Edit `C:\Windows\System32\drivers\etc\hosts`
**On Mac/Linux:** Edit `/etc/hosts`

Add:
```
<NUC_IP>  homer.homelab.local
<NUC_IP>  homeassistant.homelab.local
<NUC_IP>  jellyfin.homelab.local
<NUC_IP>  grafana.homelab.local
<NUC_IP>  pihole.homelab.local
<NUC_IP>  portainer.homelab.local
<NUC_IP>  nextcloud.homelab.local
<NUC_IP>  vault.homelab.local
```

### Step 9: Access Your Services (2 minutes)

Open your browser and visit:

1. **Homer Dashboard**: http://homer.homelab.local
   - Main interface for all services
   - Perfect for touchscreen display

2. **Home Assistant**: http://homeassistant.homelab.local
   - Complete the setup wizard
   - Add your smart devices

3. **Jellyfin**: http://jellyfin.homelab.local
   - Create admin account
   - Add media libraries

4. **Pi-hole**: http://pihole.homelab.local/admin
   - Password is in your secrets.env

5. **Portainer**: http://portainer.homelab.local
   - Create admin account on first visit

## 🎯 What's Working Now

✅ **Single-node K3s cluster** running on your NUC
✅ **Core services** deployed and accessible
✅ **Storage layer** with MinIO and Nextcloud
✅ **Smart home platform** with Home Assistant
✅ **Media server** with Jellyfin and automation
✅ **Monitoring** with Grafana dashboards
✅ **Beautiful dashboard** for touchscreen

## 🔧 Troubleshooting

### If services aren't accessible:

```bash
# Check if pods are running
kubectl get pods --all-namespaces | grep -v Running

# Get logs for failed pods
kubectl logs -n <namespace> <pod-name>

# Use the troubleshooting tool
./setup/troubleshoot.sh
```

### If you need to start over:

```bash
# Uninstall K3s completely
/usr/local/bin/k3s-uninstall.sh

# Start from Step 3 again
```

### Port conflicts:

```bash
# Check what's using ports
sudo netstat -tulpn | grep LISTEN

# Common conflicts:
# Port 80/443: Apache/Nginx (stop with: sudo systemctl stop apache2)
# Port 53: systemd-resolved (disable with: sudo systemctl disable systemd-resolved)
```

## 📊 Resource Usage

On a typical NUC with 16GB RAM:
- **K3s + Core Services**: ~4GB RAM
- **Home Assistant**: ~500MB RAM
- **Jellyfin**: ~1GB RAM (more during transcoding)
- **All services**: ~8GB RAM total

CPU usage is minimal except during:
- Media transcoding (Jellyfin)
- Large file operations (Nextcloud)
- Backup operations

## 🚀 Next Steps

### Tomorrow:
1. **Configure Home Assistant**: Add rooms, devices, automations
2. **Set up media libraries**: Add your movies/shows to Jellyfin
3. **Customize dashboards**: Modify Homer for your needs
4. **Enable backups**: Configure automated backups

### This Week:
1. **Add domain**: Configure mackie.house or your domain
2. **SSL certificates**: Enable HTTPS with Let's Encrypt
3. **External access**: Set up Cloudflare tunnel
4. **Mobile app**: Install PWA on your phone

### This Month:
1. **Add Raspberry Pis**: Expand to multi-architecture cluster
2. **Power optimization**: Enable day/night scaling
3. **Advanced monitoring**: Set up alerts and notifications
4. **Development environment**: Deploy GitLab and Code-Server

## 📱 Mobile Access

Even without external access, you can use the mobile PWA on your home network:

1. On your phone, visit: http://<NUC_IP>
2. Add to home screen (iOS: Share → Add to Home Screen)
3. The PWA works offline and updates in real-time

## ✅ Success Checklist

- [ ] Ubuntu Server installed and updated
- [ ] K3s running (`kubectl get nodes` shows Ready)
- [ ] Repository cloned and scripts executable
- [ ] Core services deployed
- [ ] Homer dashboard accessible
- [ ] At least 3 services working
- [ ] Passwords changed from defaults

## 🎉 Congratulations!

You now have a working Kubernetes homelab! It's running on a single NUC now but is ready to scale to multiple nodes whenever you want.

**Enjoy your new homelab! 🏠**

---

*Need help? Check `./setup/troubleshoot.sh` or open an issue on GitHub*