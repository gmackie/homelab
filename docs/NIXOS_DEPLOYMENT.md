# 🎯 NixOS + K3s Homelab Deployment Guide

This guide integrates the homelab Kubernetes configurations with your NixOS-based NUC setup from `../nix-config`.

## 📋 Prerequisites

- NixOS installed on NUC using the `nix-config` repository
- K3s enabled via NixOS configuration
- Network configured (static IP recommended: 192.168.0.6)
- This homelab repository cloned

## 🚀 Step 1: Deploy NixOS on NUC

### Option A: Use Pre-built NixOS ISO (Recommended for tonight)

```bash
# Download official NixOS minimal ISO for x86_64
wget https://channels.nixos.org/nixos-24.11/latest-nixos-minimal-x86_64-linux.iso

# Or use the graphical installer if preferred
wget https://channels.nixos.org/nixos-24.11/latest-nixos-gnome-x86_64-linux.iso

# Flash to USB (replace /dev/sdX with your USB device)
sudo dd if=latest-nixos-minimal-x86_64-linux.iso of=/dev/sdX bs=4M status=progress
```

### Option B: Build Custom ISO (Requires x86_64 Linux machine)

```bash
# This requires an x86_64 Linux machine or remote builder
# In the nix-config directory
cd ../nix-config
./build-nuc-iso.sh

# Flash to USB and install following NUC_K3S_INSTALL.md
```

**Note**: Since you're on ARM macOS, use Option A with the pre-built ISO and manually copy the NUC configuration during installation.

### Copy NUC Configuration During Installation

After booting from the NixOS ISO:

```bash
# On the NixOS installer, get the configuration from your repo
curl -o /tmp/nuc-configuration.nix https://raw.githubusercontent.com/gmackie/nix-config/main/templates/nuc/configuration.nix

# Or copy via USB if you have it prepared
mount /dev/sdb1 /mnt/usb  # Your USB device
cp /mnt/usb/configuration.nix /tmp/nuc-configuration.nix
```

### Verify NixOS + K3s Installation

```bash
# SSH into your NUC
ssh mackieg@192.168.0.6

# Check K3s is running
sudo systemctl status k3s
kubectl get nodes

# Should show your NUC as Ready
```

## 📦 Step 2: Prepare Homelab Deployment

### Clone Homelab Repository on NUC

```bash
# On your NUC
cd ~
git clone git@git.gmac.io:gmackie/homelab.git
cd homelab

# Make scripts executable
chmod +x setup/*.sh
chmod +x disaster-recovery/*.sh
```

### Configure kubectl

```bash
# K3s kubeconfig should already be at /etc/rancher/k3s/k3s.yaml
# Copy for user access
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config

# Add to shell profile
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
source ~/.bashrc

# Verify access
kubectl get nodes
```

## 🏗️ Step 3: Integrate NixOS Services with Kubernetes

### Update NixOS Configuration for Homelab Services

Create `/etc/nixos/homelab-integration.nix`:

```nix
{ config, pkgs, lib, ... }:

{
  # Disable conflicting services in NixOS since we're running them in K8s
  services.traefik.enable = false;  # Using ingress in K8s
  
  # K3s configuration optimized for homelab
  services.k3s = {
    enable = true;
    role = "server";
    
    extraFlags = toString [
      "--write-kubeconfig-mode=644"
      "--disable=traefik"  # We'll use our own ingress
      "--node-label=kubernetes.io/arch=amd64"
      "--node-label=node-role.kubernetes.io/master=true"
      "--node-label=homelab.io/node-type=nuc"
    ];
  };
  
  # Additional ports for homelab services
  networking.firewall.allowedTCPPorts = [ 
    22     # SSH
    80 443 # HTTP/HTTPS
    3000   # Grafana
    6443   # Kubernetes API
    8123   # Home Assistant
    8096   # Jellyfin
    8080   # Homer Dashboard
    9090   # Prometheus
    53     # Pi-hole DNS
  ];
  
  networking.firewall.allowedUDPPorts = [
    53     # Pi-hole DNS
    1883   # MQTT
  ];
  
  # DNS configuration to use Pi-hole once deployed
  # networking.nameservers = [ "127.0.0.1" "8.8.8.8" ];
  
  # Storage for Kubernetes PVs
  fileSystems."/var/lib/rancher/k3s/storage" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    options = [ "defaults" "noatime" ];
  };
  
  # Hardware acceleration for Jellyfin
  hardware.opengl = {
    enable = true;
    driSupport = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vaapiIntel
      vaapiVdpau
      libvdpau-va-gl
    ];
  };
  
  # Additional packages for homelab management
  environment.systemPackages = with pkgs; [
    # Homelab management
    argocd
    fluxcd
    
    # Media tools (for host-level operations)
    ffmpeg
    mediainfo
    
    # Smart home
    mosquitto
    
    # Backup tools
    restic
    rclone
  ];
  
  # Host-level monitoring that integrates with Kubernetes
  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = [ 
      "systemd" 
      "diskstats" 
      "filesystem" 
      "loadavg" 
      "meminfo" 
      "netdev" 
      "stat" 
      "time" 
      "uname" 
      "vmstat" 
    ];
    port = 9100;
  };
  
  # Automatic homelab updates
  systemd.services.homelab-update = {
    description = "Update homelab configurations";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      User = "mackieg";
      WorkingDirectory = "/home/mackieg/homelab";
      ExecStart = "${pkgs.git}/bin/git pull";
    };
  };
  
  systemd.timers.homelab-update = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };
}
```

Add to your main configuration:

```bash
# Edit configuration
sudo vim /etc/nixos/configuration.nix

# Add the import
imports = [
  ./hardware-configuration.nix
  ./homelab-integration.nix  # Add this line
  # ... other imports
];

# Rebuild NixOS
sudo nixos-rebuild switch
```

## 🚀 Step 4: Deploy Homelab Services

### Validate Configurations

```bash
cd ~/homelab

# Check prerequisites
./setup/check-prerequisites.sh

# Validate YAML files
./setup/validate-simple.sh
```

### Deploy Core Services

Since NixOS already provides some services (PostgreSQL, Redis, Prometheus), we'll deploy the Kubernetes-specific ones:

```bash
# Deploy storage layer
./setup/deploy-component.sh storage

# Deploy homelab services (Pi-hole, Homer, etc.)
./setup/deploy-component.sh services

# Deploy smart home platform
./setup/deploy-component.sh smart-home

# Deploy media stack
./setup/deploy-component.sh media

# Deploy monitoring (integrates with NixOS Prometheus)
./setup/deploy-component.sh monitoring

# Deploy dashboard
./setup/deploy-component.sh dashboard
```

## 🔗 Step 5: Configure Service Integration

### Link NixOS Services with Kubernetes

```bash
# Create ConfigMap for NixOS services
kubectl create configmap nixos-services \
  --from-literal=prometheus-url=http://192.168.0.6:9090 \
  --from-literal=grafana-url=http://192.168.0.6:3000 \
  --from-literal=postgres-host=192.168.0.6 \
  --from-literal=redis-host=192.168.0.6 \
  -n monitoring
```

### Configure Grafana to Use NixOS Prometheus

```bash
# Add Prometheus data source to Grafana
kubectl exec -it -n monitoring \
  $(kubectl get pod -n monitoring -l app=grafana -o jsonpath='{.items[0].metadata.name}') \
  -- grafana-cli admin data-source add prometheus \
  --url=http://192.168.0.6:9090 \
  --access=proxy
```

## 🌐 Step 6: Configure DNS and Ingress

### Update /etc/hosts for Local Access

```bash
# On NixOS, add to configuration.nix
networking.extraHosts = ''
  192.168.0.6 homer.homelab.local
  192.168.0.6 homeassistant.homelab.local
  192.168.0.6 jellyfin.homelab.local
  192.168.0.6 grafana.homelab.local
  192.168.0.6 pihole.homelab.local
  192.168.0.6 portainer.homelab.local
  192.168.0.6 nextcloud.homelab.local
  192.168.0.6 vault.homelab.local
  192.168.0.6 mobile.homelab.local
  192.168.0.6 api.homelab.local
'';

# Rebuild
sudo nixos-rebuild switch
```

### Configure LoadBalancer IP Pool

Since K3s servicelb is disabled, deploy MetalLB:

```bash
kubectl apply -f networking/advanced-networking.yaml

# Configure IP pool for your network
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - 192.168.0.100-192.168.0.110  # Adjust for your network
EOF
```

## 🎨 Step 7: Access Your Services

### Primary Dashboard
Open browser to: `http://192.168.0.6` or `http://homer.homelab.local`

### Service URLs
All services are accessible at their configured URLs:
- Homer: http://homer.homelab.local
- Home Assistant: http://homeassistant.homelab.local
- Jellyfin: http://jellyfin.homelab.local
- Grafana: http://192.168.0.6:3000 (NixOS native)
- Pi-hole: http://pihole.homelab.local/admin

### Mobile Access
- Progressive Web App: http://mobile.homelab.local
- API Gateway: http://api.homelab.local

## 🔧 Step 8: NixOS-Specific Optimizations

### Power Management

Add to your NixOS configuration:

```nix
# Power optimization for homelab
powerManagement = {
  enable = true;
  cpuFreqGovernor = "ondemand";  # Balance performance and power
  
  # Scale down during low usage
  powertop.enable = true;
};

# Thermal management
services.thermald.enable = true;

# Automatic suspend/wake (optional)
systemd.services.auto-suspend = {
  description = "Auto suspend when idle";
  wantedBy = [ "multi-user.target" ];
  
  serviceConfig = {
    Type = "simple";
    ExecStart = pkgs.writeShellScript "auto-suspend" ''
      while true; do
        if [[ $(kubectl top nodes | awk 'NR>1 {print $3}' | sed 's/%//') -lt 20 ]]; then
          # Low usage, could suspend (implement your logic)
          echo "System idle"
        fi
        sleep 300
      done
    '';
  };
};
```

### Backup Integration

```nix
# Automated backups using NixOS
services.restic.backups = {
  homelab = {
    paths = [
      "/home/mackieg/homelab"
      "/var/lib/rancher/k3s/storage"
    ];
    
    repository = "s3:s3.amazonaws.com/your-backup-bucket";
    passwordFile = "/etc/nixos/secrets/restic-password";
    
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
    
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 12"
    ];
  };
};
```

## 🚦 Troubleshooting NixOS + K3s

### Common Issues

1. **K3s not starting after NixOS rebuild**:
```bash
sudo systemctl restart k3s
journalctl -u k3s -f
```

2. **Pods can't resolve DNS**:
```bash
# Check CoreDNS
kubectl get pods -n kube-system
kubectl logs -n kube-system -l k8s-app=kube-dns
```

3. **Storage permission issues**:
```bash
# Fix storage permissions
sudo chown -R 1000:1000 /var/lib/rancher/k3s/storage
```

4. **Service conflicts with NixOS**:
```bash
# Check for port conflicts
sudo netstat -tulpn | grep LISTEN
```

### NixOS-Specific Commands

```bash
# Rebuild with homelab config
sudo nixos-rebuild switch

# Clean old generations
sudo nix-collect-garbage -d

# Update flake inputs
sudo nix flake update /etc/nixos

# Check system health
systemctl status k3s
systemctl status prometheus
systemctl status grafana
```

## 🎯 Success Checklist

- [ ] NixOS installed and configured
- [ ] K3s running (`kubectl get nodes` shows Ready)
- [ ] Homelab repository cloned
- [ ] Core services deployed
- [ ] Homer dashboard accessible
- [ ] DNS resolution working
- [ ] At least 3 services accessible
- [ ] NixOS Prometheus integrated with Grafana
- [ ] Backups configured

## 🚀 What's Next?

1. **Add Raspberry Pis**: Extend to multi-architecture cluster
2. **Configure GitOps**: Deploy ArgoCD for automated deployments
3. **External Access**: Set up Cloudflare tunnel
4. **Development Environment**: Use NixOS development tools
5. **Monitoring**: Integrate NixOS metrics with Kubernetes monitoring

## 📚 Resources

- NixOS K3s Module: https://nixos.wiki/wiki/K3s
- K3s Documentation: https://docs.k3s.io
- Homelab Repository: git@git.gmac.io:gmackie/homelab
- NixOS Configuration: ../nix-config

---

*The power of NixOS declarative configuration + Kubernetes orchestration = Ultimate Homelab!*