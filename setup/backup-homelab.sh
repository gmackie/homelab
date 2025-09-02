#!/bin/bash

# Homelab Backup Script - Backs up critical configurations and data
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/tmp/homelab-backup-$(date +%Y%m%d-%H%M%S)}"
HOMELAB_DIR="${HOMELAB_DIR:-/Volumes/dev/homelab}"

echo -e "${CYAN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                   Homelab Backup Tool                        ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Create backup directory
mkdir -p "$BACKUP_DIR"
log_info "Backup directory: $BACKUP_DIR"

# Backup YAML configurations
log_info "Backing up YAML configurations..."
mkdir -p "$BACKUP_DIR/configs"

configs=(
    "storage/network-storage.yaml"
    "services/homelab-services.yaml"
    "smart-home/home-assistant.yaml"
    "smart-home/esphome-devices.yaml"
    "media/media-stack.yaml"
    "media/sabnzbd.yaml"
    "monitoring/grafana-homeassistant.yaml"
    "apps/dashboard/api/deployment.yaml"
    "apps/dashboard/ui/deployment.yaml"
)

for config in "${configs[@]}"; do
    if [[ -f "$HOMELAB_DIR/$config" ]]; then
        cp "$HOMELAB_DIR/$config" "$BACKUP_DIR/configs/$(basename $config)"
        log_success "Backed up: $config"
    fi
done

# Backup Kubernetes resources if cluster is available
if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null 2>&1; then
    log_info "Backing up Kubernetes resources..."
    mkdir -p "$BACKUP_DIR/k8s"
    
    # Export namespaces
    namespaces=("storage" "media" "smart-home" "homelab-services" "monitoring")
    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &> /dev/null 2>&1; then
            kubectl get all -n "$ns" -o yaml > "$BACKUP_DIR/k8s/$ns-resources.yaml" 2>/dev/null
            log_success "Exported namespace: $ns"
        fi
    done
    
    # Export persistent volume claims
    kubectl get pvc --all-namespaces -o yaml > "$BACKUP_DIR/k8s/pvcs.yaml" 2>/dev/null
    
    # Export configmaps
    kubectl get configmaps --all-namespaces -o yaml > "$BACKUP_DIR/k8s/configmaps.yaml" 2>/dev/null
    
    # Export secrets (encrypted)
    kubectl get secrets --all-namespaces -o yaml | \
        sed 's/\(data:\)/\1\n  # ENCRYPTED - Restore manually/g' > "$BACKUP_DIR/k8s/secrets.yaml" 2>/dev/null
else
    log_warning "Kubernetes cluster not accessible - skipping resource backup"
fi

# Create backup manifest
log_info "Creating backup manifest..."
cat > "$BACKUP_DIR/manifest.txt" << EOF
Homelab Backup Manifest
========================
Date: $(date)
Host: $(hostname)
Directory: $BACKUP_DIR

Files Backed Up:
$(ls -la "$BACKUP_DIR/configs" 2>/dev/null | tail -n +2 || echo "No configs")

Kubernetes Resources:
$(ls -la "$BACKUP_DIR/k8s" 2>/dev/null | tail -n +2 || echo "No K8s resources")
EOF

# Create restore script
cat > "$BACKUP_DIR/restore.sh" << 'EOF'
#!/bin/bash
# Homelab Restore Script

echo "Restoring homelab configurations..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Restore configurations
if [[ -d "$SCRIPT_DIR/configs" ]]; then
    echo "Found configuration backups"
    echo "Copy these to your homelab directory and apply with kubectl"
    ls -la "$SCRIPT_DIR/configs"
fi

# Restore Kubernetes resources
if [[ -d "$SCRIPT_DIR/k8s" ]]; then
    echo "Found Kubernetes resource backups"
    echo "Review and apply with: kubectl apply -f <file>"
    ls -la "$SCRIPT_DIR/k8s"
fi

echo "Restore complete. Review files before applying."
EOF

chmod +x "$BACKUP_DIR/restore.sh"

# Compress backup
log_info "Compressing backup..."
tar -czf "$BACKUP_DIR.tar.gz" -C "$(dirname "$BACKUP_DIR")" "$(basename "$BACKUP_DIR")"

echo
echo "═══════════════════════════════════════════════════════════════════"
echo "                      BACKUP COMPLETE"
echo "═══════════════════════════════════════════════════════════════════"
echo
log_success "Backup saved to: $BACKUP_DIR.tar.gz"
echo
echo "To restore:"
echo "1. Extract: tar -xzf $BACKUP_DIR.tar.gz"
echo "2. Run: $BACKUP_DIR/restore.sh"
echo
echo "💡 TIP: Store this backup in a safe location!"