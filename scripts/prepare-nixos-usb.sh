#!/bin/bash
# Prepare NixOS USB installer for tonight's NUC deployment

set -euo pipefail

echo "🚀 NixOS NUC Installation Helper"
echo "================================"
echo ""
echo "Since we can't build x86_64 ISO on ARM Mac, here's what to do:"
echo ""

# Download official NixOS ISO
echo "📥 Step 1: Download NixOS ISO"
echo "------------------------------"
echo "Run this command to download the latest NixOS minimal ISO:"
echo ""
echo "  wget https://channels.nixos.org/nixos-24.11/latest-nixos-minimal-x86_64-linux.iso"
echo ""
echo "Or if you prefer a graphical installer:"
echo ""
echo "  wget https://channels.nixos.org/nixos-24.11/latest-nixos-gnome-x86_64-linux.iso"
echo ""

# Create configuration file
echo "📝 Step 2: Configuration File Created"
echo "-------------------------------------"

cat > nixos-nuc-config.nix << 'EOF'
# Intel NUC K3s Homelab Configuration
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix  # Generated during install
  ];
  
  # Boot configuration
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };
  
  # Networking
  networking = {
    hostName = "homelab-nuc";
    
    # Static IP configuration
    interfaces.eno1.ipv4.addresses = [{
      address = "192.168.0.6";
      prefixLength = 24;
    }];
    defaultGateway = "192.168.0.1";
    nameservers = [ "8.8.8.8" "8.8.4.4" ];
    
    firewall = {
      enable = true;
      allowedTCPPorts = [ 
        22     # SSH
        80 443 # HTTP/HTTPS
        3000   # Grafana
        6443   # Kubernetes API
        8123   # Home Assistant
        8096   # Jellyfin
        8080   # Homer Dashboard
        9090   # Prometheus
      ];
    };
  };
  
  # User account
  users.users.mackieg = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
    openssh.authorizedKeys.keys = [
      # Add your SSH public key here
      # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... your-key"
    ];
  };
  
  # Enable SSH
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };
  
  # K3s for Kubernetes
  services.k3s = {
    enable = true;
    role = "server";
    extraFlags = toString [
      "--write-kubeconfig-mode=644"
      "--disable=traefik"
      "--node-label=kubernetes.io/arch=amd64"
      "--node-label=homelab.io/node-type=nuc"
    ];
  };
  
  # Container runtime
  virtualisation = {
    docker.enable = true;
    containerd.enable = true;
  };
  
  # Development services
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_15;
  };
  
  services.redis.servers."" = {
    enable = true;
    port = 6379;
  };
  
  # Monitoring
  services.prometheus = {
    enable = true;
    port = 9090;
    exporters.node = {
      enable = true;
      port = 9100;
    };
  };
  
  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "0.0.0.0";
        http_port = 3000;
      };
    };
  };
  
  # Hardware optimization for NUC
  hardware = {
    cpu.intel.updateMicrocode = true;
    opengl = {
      enable = true;
      driSupport = true;
      extraPackages = with pkgs; [
        intel-media-driver
        vaapiIntel
      ];
    };
  };
  
  # Power management
  powerManagement = {
    enable = true;
    cpuFreqGovernor = "ondemand";
  };
  services.thermald.enable = true;
  
  # Essential packages
  environment.systemPackages = with pkgs; [
    # Kubernetes tools
    kubectl
    kubernetes-helm
    k9s
    
    # Development
    git
    vim
    tmux
    curl
    wget
    
    # System monitoring
    htop
    iotop
    lm_sensors
  ];
  
  # Auto updates
  system.autoUpgrade = {
    enable = true;
    dates = "04:00";
  };
  
  # Garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
  
  system.stateVersion = "24.11";
}
EOF

echo "✅ Configuration saved to: nixos-nuc-config.nix"
echo ""

# Flash instructions
echo "💾 Step 3: Flash USB Drive"
echo "--------------------------"
echo "Find your USB device:"
echo "  lsblk"
echo ""
echo "Flash the ISO (replace /dev/sdX with your USB device):"
echo "  sudo dd if=latest-nixos-minimal-x86_64-linux.iso of=/dev/sdX bs=4M status=progress"
echo ""

# Installation instructions
echo "🖥️ Step 4: Install on NUC"
echo "-------------------------"
echo "1. Boot NUC from USB"
echo "2. Once in the installer, run:"
echo ""
echo "   # Partition disk (replace /dev/sda with your disk)"
echo "   parted /dev/sda -- mklabel gpt"
echo "   parted /dev/sda -- mkpart ESP fat32 1MiB 512MiB"
echo "   parted /dev/sda -- set 1 esp on"
echo "   parted /dev/sda -- mkpart primary 512MiB 100%"
echo ""
echo "   # Format partitions"
echo "   mkfs.fat -F 32 -n boot /dev/sda1"
echo "   mkfs.ext4 -L nixos /dev/sda2"
echo ""
echo "   # Mount filesystems"
echo "   mount /dev/disk/by-label/nixos /mnt"
echo "   mkdir -p /mnt/boot"
echo "   mount /dev/disk/by-label/boot /mnt/boot"
echo ""
echo "   # Generate config and copy our custom one"
echo "   nixos-generate-config --root /mnt"
echo "   # Copy nixos-nuc-config.nix to /mnt/etc/nixos/configuration.nix"
echo ""
echo "   # Install"
echo "   nixos-install"
echo "   reboot"
echo ""

# Copy to USB instructions
echo "📋 Step 5: Copy Config to USB (Optional)"
echo "----------------------------------------"
echo "Copy this configuration to a second USB for easy access during install:"
echo ""
echo "  cp nixos-nuc-config.nix /path/to/usb/"
echo ""

echo "🎯 After Installation"
echo "--------------------"
echo "SSH into your NUC and deploy the homelab:"
echo ""
echo "  ssh mackieg@192.168.0.6"
echo "  git clone https://github.com/gmackie/homelab.git"
echo "  cd homelab"
echo "  ./setup/deploy-complete-homelab.sh"
echo ""
echo "Ready for tonight's deployment! 🚀"