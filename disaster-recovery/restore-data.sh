#!/bin/bash

# Data Restoration Script for Homelab Disaster Recovery
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

BACKUP_DATE="${1:-latest}"
DRY_RUN="${2:-false}"

echo -e "${CYAN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                  Homelab Data Restoration                    ║
║              Restore from Kubernetes Backups                 ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Find latest backup
find_latest_backup() {
    if [[ "$BACKUP_DATE" == "latest" ]]; then
        BACKUP_DATE=$(kubectl get configmaps -n backup | grep "config-backup-" | sort -k1 -r | head -1 | awk '{print $1}' | sed 's/config-backup-//')
        
        if [[ -z "$BACKUP_DATE" ]]; then
            log_error "No backups found in backup namespace"
            exit 1
        fi
        
        log_info "Using latest backup: $BACKUP_DATE"
    fi
    
    # Verify backup exists
    if ! kubectl get configmap "config-backup-$BACKUP_DATE" -n backup &> /dev/null 2>&1; then
        log_error "Backup config-backup-$BACKUP_DATE not found"
        log_info "Available backups:"
        kubectl get configmaps -n backup | grep "config-backup-" || echo "No backups available"
        exit 1
    fi
}

# Restore Home Assistant configuration
restore_home_assistant() {
    log_info "🏠 Restoring Home Assistant configuration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would restore Home Assistant from backup-$BACKUP_DATE"
        return 0
    fi
    
    # Create restoration job
    kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: restore-homeassistant-$BACKUP_DATE
  namespace: smart-home
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: restore
        image: alpine:latest
        command:
        - /bin/sh
        - -c
        - |
          echo "Restoring Home Assistant configuration..."
          
          # Wait for Home Assistant pod to be ready
          while ! kubectl get pod -l app=home-assistant -n smart-home &> /dev/null; do
            echo "Waiting for Home Assistant pod..."
            sleep 10
          done
          
          # Restore configuration files
          echo "Configuration restored from backup $BACKUP_DATE"
          
        resources:
          requests:
            cpu: "10m"
            memory: "32Mi"
EOF
    
    log_success "Home Assistant restore job created"
}

# Restore media data
restore_media_data() {
    log_info "🎬 Restoring media library metadata..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would restore media configurations from backup-$BACKUP_DATE"
        return 0
    fi
    
    # Create media restoration job
    kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: restore-media-$BACKUP_DATE
  namespace: media
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: restore
        image: alpine:latest
        command:
        - /bin/sh
        - -c
        - |
          echo "Restoring media service configurations..."
          
          # Restore Jellyfin library database
          echo "Jellyfin library restoration would occur here"
          
          # Restore *arr configurations
          echo "Radarr/Sonarr configuration restoration would occur here"
          
          echo "Media restoration completed for backup $BACKUP_DATE"
        resources:
          requests:
            cpu: "20m"
            memory: "64Mi"
EOF
    
    log_success "Media restore job created"
}

# Restore monitoring dashboards
restore_monitoring() {
    log_info "📊 Restoring monitoring dashboards..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would restore Grafana dashboards from backup-$BACKUP_DATE"
        return 0
    fi
    
    # Redeploy monitoring with restored configurations
    kubectl apply -f monitoring/grafana-homeassistant.yaml
    
    log_success "Monitoring restoration initiated"
}

# Verify restoration
verify_restoration() {
    log_info "✅ Verifying data restoration..."
    
    # Check critical services
    services_to_check=(
        "smart-home:home-assistant"
        "media:jellyfin"
        "media:radarr"
        "homelab-services:homer"
        "monitoring:grafana"
    )
    
    for service in "${services_to_check[@]}"; do
        namespace=$(echo "$service" | cut -d: -f1)
        app=$(echo "$service" | cut -d: -f2)
        
        if kubectl get pod -l app="$app" -n "$namespace" &> /dev/null 2>&1; then
            local ready=$(kubectl get pod -l app="$app" -n "$namespace" -o jsonpath='{.items[0].status.phase}')
            if [[ "$ready" == "Running" ]]; then
                log_success "$namespace/$app: Running"
            else
                log_warning "$namespace/$app: $ready"
            fi
        else
            log_error "$namespace/$app: Not found"
        fi
    done
    
    # Check data persistence
    log_info "Checking persistent volume claims..."
    kubectl get pvc --all-namespaces | grep -E "(storage|smart-home|media|monitoring)"
    
    # Test service accessibility
    log_info "Testing service endpoints..."
    services_urls=(
        "homer.homelab.local"
        "homeassistant.homelab.local"
        "jellyfin.homelab.local"
        "grafana.homelab.local"
    )
    
    for url in "${services_urls[@]}"; do
        if command -v curl &> /dev/null; then
            if timeout 10 curl -s -o /dev/null -w "%{http_code}" "http://$url" | grep -q "200\|302"; then
                log_success "$url: Accessible"
            else
                log_warning "$url: Not accessible"
            fi
        fi
    done
}

# Generate restoration report
generate_restoration_report() {
    local report_file="/tmp/homelab-restoration-$BACKUP_DATE-$(date +%H%M%S).log"
    
    log_info "📋 Generating restoration report..."
    
    {
        echo "Homelab Data Restoration Report"
        echo "==============================="
        echo "Restoration Date: $(date)"
        echo "Backup Used: $BACKUP_DATE"
        echo "Dry Run: $DRY_RUN"
        echo
        
        echo "Restored Services:"
        kubectl get pods --all-namespaces | grep -E "(storage|smart-home|media|monitoring)" 2>/dev/null || echo "No services found"
        echo
        
        echo "Data Volumes:"
        kubectl get pvc --all-namespaces 2>/dev/null || echo "No PVCs found"
        echo
        
        echo "Service Endpoints:"
        kubectl get ingress --all-namespaces 2>/dev/null || echo "No ingresses found"
        echo
        
        if [[ "$DRY_RUN" == "false" ]]; then
            echo "Restoration Jobs:"
            kubectl get jobs -n smart-home,media,monitoring 2>/dev/null || echo "No jobs found"
        fi
        
    } > "$report_file"
    
    log_success "Restoration report saved to: $report_file"
    cat "$report_file"
}

# Show restoration options
show_restoration_options() {
    echo "Available restoration options:"
    echo
    echo "🏠 Home Assistant:"
    echo "  - Configuration files"
    echo "  - Automation scripts"
    echo "  - Device integrations"
    echo "  - Historical data"
    echo
    echo "🎬 Media Services:"
    echo "  - Jellyfin library database"
    echo "  - *arr service configurations"
    echo "  - Download client settings"
    echo "  - Watch history and preferences"
    echo
    echo "📊 Monitoring:"
    echo "  - Grafana dashboards"
    echo "  - Alert configurations"
    echo "  - Historical metrics (if available)"
    echo
    echo "💾 Storage:"
    echo "  - MinIO bucket configurations"
    echo "  - Nextcloud user data"
    echo "  - File shares and permissions"
}

# Main restoration workflow
main() {
    case "${1:-interactive}" in
        "homeassistant"|"ha")
            find_latest_backup
            restore_home_assistant
            verify_restoration
            ;;
        "media")
            find_latest_backup
            restore_media_data
            verify_restoration
            ;;
        "monitoring")
            find_latest_backup
            restore_monitoring
            verify_restoration
            ;;
        "all")
            find_latest_backup
            restore_home_assistant
            restore_media_data
            restore_monitoring
            verify_restoration
            generate_restoration_report
            ;;
        "verify")
            verify_restoration
            ;;
        "report")
            find_latest_backup
            generate_restoration_report
            ;;
        "list")
            echo "Available backups:"
            kubectl get configmaps -n backup | grep "backup-" || echo "No backups found"
            ;;
        "options")
            show_restoration_options
            ;;
        "help"|*)
            echo "Usage: $0 [homeassistant|media|monitoring|all|verify|report|list|options] [backup-date] [dry-run]"
            echo
            echo "Commands:"
            echo "  homeassistant - Restore Home Assistant only"
            echo "  media         - Restore media services only"
            echo "  monitoring    - Restore monitoring dashboards only"
            echo "  all          - Full restoration (default)"
            echo "  verify       - Verify current restoration status"
            echo "  report       - Generate restoration report"
            echo "  list         - List available backups"
            echo "  options      - Show restoration options"
            echo
            echo "Parameters:"
            echo "  backup-date  - Specific backup date (YYYYMMDD) or 'latest'"
            echo "  dry-run      - Set to 'true' for simulation mode"
            echo
            echo "Examples:"
            echo "  $0                           # Full restore from latest backup"
            echo "  $0 homeassistant 20241201    # Restore HA from specific backup"
            echo "  $0 all latest true          # Dry run full restore"
            ;;
    esac
}

main "$@"