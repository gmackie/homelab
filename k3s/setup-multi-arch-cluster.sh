#!/bin/bash

set -e

echo "🚀 Setting up Multi-Architecture k3s Cluster"

# Configuration
MASTER_NODE="nuc-1"
MASTER_IP="${1:-192.168.1.100}"  # Pass as first argument or default
ARM_NODES=("pi-1" "pi-2" "pi-3" "pi-4")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if we're on master or worker
detect_node_type() {
    HOSTNAME=$(hostname)
    ARCH=$(uname -m)
    
    case $ARCH in
        x86_64)
            ARCH_LABEL="amd64"
            ;;
        aarch64|arm64)
            ARCH_LABEL="arm64"
            ;;
        armv7l)
            ARCH_LABEL="arm"
            ;;
        *)
            error "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac
    
    log "Detected: $HOSTNAME ($ARCH_LABEL)"
}

# Install k3s master (AMD64)
setup_master() {
    log "Setting up k3s master node on $HOSTNAME"
    
    # Install k3s with specific configurations for multi-arch
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server" sh -s - \
        --disable traefik \
        --disable servicelb \
        --write-kubeconfig-mode 644 \
        --node-label "arch=$ARCH_LABEL" \
        --node-label "node-role/master=true" \
        --node-label "node-role/compute=true" \
        --node-label "node-role/storage=true"
    
    # Wait for k3s to start
    sleep 10
    
    # Get the token
    K3S_TOKEN=$(sudo cat /var/lib/rancher/k3s/server/node-token)
    
    log "Master setup complete!"
    log "Node token: $K3S_TOKEN"
    log "Join workers with: K3S_URL=https://$MASTER_IP:6443 K3S_TOKEN=$K3S_TOKEN"
    
    # Create kubeconfig for non-root access
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown $USER:$USER ~/.kube/config
    
    # Install kubectl if not present
    if ! command -v kubectl &> /dev/null; then
        log "Installing kubectl..."
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/$ARCH_LABEL/kubectl"
        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/
    fi
    
    # Install Helm
    if ! command -v helm &> /dev/null; then
        log "Installing Helm..."
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi
}

# Install k3s worker (ARM)
setup_worker() {
    if [ -z "$K3S_URL" ] || [ -z "$K3S_TOKEN" ]; then
        error "K3S_URL and K3S_TOKEN environment variables must be set for worker nodes"
        error "Example: K3S_URL=https://192.168.1.100:6443 K3S_TOKEN=xxx ./setup-multi-arch-cluster.sh"
        exit 1
    fi
    
    log "Setting up k3s worker node on $HOSTNAME"
    
    # Install k3s agent
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent" sh -s - \
        --node-label "arch=$ARCH_LABEL" \
        --node-label "node-role/edge=true" \
        --node-label "power-efficiency=high"
    
    log "Worker setup complete!"
}

# Setup node-specific configurations
configure_node() {
    log "Configuring node-specific settings..."
    
    if [ "$ARCH_LABEL" = "amd64" ]; then
        # AMD64 specific configurations
        log "Applying AMD64 optimizations..."
        
        # Increase file limits for databases
        echo "* soft nofile 65536" | sudo tee -a /etc/security/limits.conf
        echo "* hard nofile 65536" | sudo tee -a /etc/security/limits.conf
        
        # Configure for storage workloads
        echo 'vm.swappiness=1' | sudo tee -a /etc/sysctl.conf
        echo 'vm.vfs_cache_pressure=50' | sudo tee -a /etc/sysctl.conf
        
    else
        # ARM specific configurations
        log "Applying ARM optimizations..."
        
        # Power management settings
        echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
        
        # GPU memory split for Pi (if applicable)
        if [ -f /boot/config.txt ]; then
            if ! grep -q "gpu_mem=" /boot/config.txt; then
                echo "gpu_mem=16" | sudo tee -a /boot/config.txt
            fi
        fi
    fi
    
    # Apply sysctl changes
    sudo sysctl -p
}

# Main execution
detect_node_type
configure_node

if [ "$HOSTNAME" = "$MASTER_NODE" ] || [ "$ARCH_LABEL" = "amd64" ]; then
    setup_master
else
    setup_worker
fi

# Install monitoring agents
log "Installing node monitoring..."
cat <<EOF | sudo tee /etc/systemd/system/node-metrics.service
[Unit]
Description=Node Metrics Collector
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/node-metrics
Restart=always
RestartSec=10
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
EOF

# Create simple metrics collector
sudo tee /usr/local/bin/node-metrics > /dev/null <<'EOF'
#!/bin/bash
while true; do
    # Basic system metrics
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
    MEM_USAGE=$(free | grep Mem | awk '{printf("%.1f"), $3/$2 * 100.0}')
    ARCH=$(uname -m)
    
    # Power estimation (rough)
    if [ "$ARCH" = "x86_64" ]; then
        POWER_ESTIMATE="45"  # Watts
    else
        POWER_ESTIMATE="7"   # Watts for Pi
    fi
    
    # Log metrics (can be scraped by Prometheus)
    echo "node_cpu_usage{arch=\"$ARCH\",hostname=\"$(hostname)\"} $CPU_USAGE"
    echo "node_memory_usage{arch=\"$ARCH\",hostname=\"$(hostname)\"} $MEM_USAGE"
    echo "node_power_estimate{arch=\"$ARCH\",hostname=\"$(hostname)\"} $POWER_ESTIMATE"
    
    sleep 30
done
EOF

sudo chmod +x /usr/local/bin/node-metrics
sudo systemctl enable node-metrics
sudo systemctl start node-metrics

log "✅ Multi-architecture cluster node setup complete!"
log "Architecture: $ARCH_LABEL"
log "Hostname: $HOSTNAME"

if [ "$ARCH_LABEL" = "amd64" ]; then
    log "🖥️  AMD64 node configured for: compute, storage, control plane"
else
    log "🥧 ARM node configured for: edge services, IoT, power efficiency"
fi

echo ""
log "Next steps:"
echo "1. Run this script on all nodes"
echo "2. Apply the Kubernetes manifests: kubectl apply -f k8s/"
echo "3. Deploy services: ./deploy-multi-arch-services.sh"