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
