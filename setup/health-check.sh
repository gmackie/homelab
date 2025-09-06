#!/bin/bash

# Comprehensive Health Check Script for Homelab
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

FAILED_CHECKS=0
TOTAL_CHECKS=0

check_result() {
    local check_name="$1"
    local status="$2"
    ((TOTAL_CHECKS++))
    
    if [[ "$status" == "0" ]]; then
        log_success "$check_name"
    else
        log_error "$check_name"
        ((FAILED_CHECKS++))
    fi
}

echo -e "${CYAN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                  Homelab Health Check                        ║
║              Comprehensive System Validation                 ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Cluster connectivity
log_info "🔌 Checking cluster connectivity..."
if kubectl cluster-info &> /dev/null 2>&1; then
    check_result "Cluster connectivity" 0
    
    # Get cluster info
    log_info "Cluster details:"
    kubectl cluster-info | head -2
else
    check_result "Cluster connectivity" 1
    log_error "Cannot proceed without cluster access"
    exit 1
fi

# Node health
log_info "🖥️ Checking node health..."
node_status=$(kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}' | grep -v Ready | wc -l)
total_nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)

if [[ "$node_status" == "0" ]] && [[ "$total_nodes" -gt "0" ]]; then
    check_result "All $total_nodes nodes Ready" 0
    
    # Show architecture distribution
    log_info "Node architecture distribution:"
    kubectl get nodes -o wide | awk 'NR>1 {arch[$6]++} END {for (a in arch) printf "  %s: %d nodes\n", a, arch[a]}'
else
    check_result "Node health ($node_status/$total_nodes not Ready)" 1
fi

# Core namespaces
log_info "📁 Checking core namespaces..."
required_namespaces=("storage" "homelab-services" "smart-home" "media" "monitoring")

for ns in "${required_namespaces[@]}"; do
    if kubectl get namespace "$ns" &> /dev/null 2>&1; then
        check_result "Namespace: $ns" 0
    else
        check_result "Namespace: $ns" 1
    fi
done

# Storage layer health
log_info "💾 Checking storage layer..."
storage_checks=(
    "minio:deployment"
    "nextcloud:deployment" 
    "filebrowser:deployment"
    "nfs-server:deployment"
)

for check in "${storage_checks[@]}"; do
    service=$(echo "$check" | cut -d: -f1)
    resource=$(echo "$check" | cut -d: -f2)
    
    if kubectl get "$resource" "$service" -n storage &> /dev/null 2>&1; then
        ready=$(kubectl get "$resource" "$service" -n storage -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        desired=$(kubectl get "$resource" "$service" -n storage -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
        
        if [[ "$ready" == "$desired" ]] && [[ "$ready" != "0" ]]; then
            check_result "Storage: $service ($ready/$desired ready)" 0
        else
            check_result "Storage: $service ($ready/$desired ready)" 1
        fi
    else
        check_result "Storage: $service (not found)" 1
    fi
done

# Essential services health
log_info "🛠️ Checking essential services..."
service_checks=(
    "pihole:deployment"
    "portainer:deployment"
    "homer:deployment"
    "uptime-kuma:deployment"
    "vaultwarden:deployment"
)

for check in "${service_checks[@]}"; do
    service=$(echo "$check" | cut -d: -f1)
    resource=$(echo "$check" | cut -d: -f2)
    
    if kubectl get "$resource" "$service" -n homelab-services &> /dev/null 2>&1; then
        ready=$(kubectl get "$resource" "$service" -n homelab-services -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        desired=$(kubectl get "$resource" "$service" -n homelab-services -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
        
        if [[ "$ready" == "$desired" ]] && [[ "$ready" != "0" ]]; then
            check_result "Service: $service ($ready/$desired ready)" 0
        else
            check_result "Service: $service ($ready/$desired ready)" 1
        fi
    else
        check_result "Service: $service (not found)" 1
    fi
done

# Smart home platform health
log_info "🏠 Checking smart home platform..."
if kubectl get deployment home-assistant -n smart-home &> /dev/null 2>&1; then
    ha_ready=$(kubectl get deployment home-assistant -n smart-home -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    ha_desired=$(kubectl get deployment home-assistant -n smart-home -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
    
    if [[ "$ha_ready" == "$ha_desired" ]] && [[ "$ha_ready" != "0" ]]; then
        check_result "Home Assistant ($ha_ready/$ha_desired ready)" 0
    else
        check_result "Home Assistant ($ha_ready/$ha_desired ready)" 1
    fi
else
    check_result "Home Assistant (not found)" 1
fi

# Media stack health
log_info "🎬 Checking media stack..."
media_services=("jellyfin" "radarr" "sonarr" "qbittorrent" "sabnzbd" "nzbhydra2")

for service in "${media_services[@]}"; do
    if kubectl get deployment "$service" -n media &> /dev/null 2>&1; then
        ready=$(kubectl get deployment "$service" -n media -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        desired=$(kubectl get deployment "$service" -n media -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
        
        if [[ "$ready" == "$desired" ]] && [[ "$ready" != "0" ]]; then
            check_result "Media: $service ($ready/$desired ready)" 0
        else
            check_result "Media: $service ($ready/$desired ready)" 1
        fi
    else
        check_result "Media: $service (not found)" 1
    fi
done

# Monitoring health
log_info "📊 Checking monitoring stack..."
if kubectl get deployment grafana -n monitoring &> /dev/null 2>&1; then
    grafana_ready=$(kubectl get deployment grafana -n monitoring -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    grafana_desired=$(kubectl get deployment grafana -n monitoring -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
    
    if [[ "$grafana_ready" == "$grafana_desired" ]] && [[ "$grafana_ready" != "0" ]]; then
        check_result "Grafana ($grafana_ready/$grafana_desired ready)" 0
    else
        check_result "Grafana ($grafana_ready/$grafana_desired ready)" 1
    fi
else
    check_result "Grafana (not found)" 1
fi

# Storage persistence check
log_info "💽 Checking persistent storage..."
pvc_count=$(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | wc -l)
bound_pvcs=$(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | grep Bound | wc -l)

if [[ "$pvc_count" -gt "0" ]] && [[ "$bound_pvcs" == "$pvc_count" ]]; then
    check_result "Persistent storage ($bound_pvcs/$pvc_count PVCs bound)" 0
else
    check_result "Persistent storage ($bound_pvcs/$pvc_count PVCs bound)" 1
fi

# Ingress connectivity
log_info "🌐 Checking ingress connectivity..."
ingress_count=$(kubectl get ingress --all-namespaces --no-headers 2>/dev/null | wc -l)

if [[ "$ingress_count" -gt "0" ]]; then
    check_result "Ingress resources ($ingress_count configured)" 0
    
    log_info "Available services:"
    kubectl get ingress --all-namespaces -o custom-columns="SERVICE:.metadata.name,HOST:.spec.rules[0].host,NAMESPACE:.metadata.namespace" --no-headers 2>/dev/null | \
        head -10 | while read line; do echo "  $line"; done
else
    check_result "Ingress resources (none found)" 1
fi

# Resource utilization
log_info "🔋 Checking resource utilization..."
if command -v kubectl top &> /dev/null && kubectl top nodes &> /dev/null 2>&1; then
    log_info "Node resource usage:"
    kubectl top nodes 2>/dev/null | head -5
    
    check_result "Resource metrics available" 0
else
    check_result "Resource metrics available" 1
    log_warning "Install metrics-server for resource monitoring"
fi

# Final summary
echo
echo "═══════════════════════════════════════════════════════════════════"
echo "                        HEALTH CHECK SUMMARY"
echo "═══════════════════════════════════════════════════════════════════"

if [[ "$FAILED_CHECKS" == "0" ]]; then
    log_success "ALL CHECKS PASSED! ($TOTAL_CHECKS/$TOTAL_CHECKS) 🎉"
    echo
    echo "🚀 Your homelab is healthy and ready!"
    echo "📱 Touchscreen URL: http://homer.homelab.local"
    echo "🏠 Home Assistant: http://homeassistant.homelab.local"
    echo "📊 Grafana: http://grafana.homelab.local"
    echo
elif [[ "$FAILED_CHECKS" -lt 5 ]]; then
    log_warning "MINOR ISSUES DETECTED ($((TOTAL_CHECKS - FAILED_CHECKS))/$TOTAL_CHECKS passed)"
    echo
    echo "✅ Core functionality should work"
    echo "⚠️  Check failed services for full functionality"
else
    log_error "SIGNIFICANT ISSUES DETECTED ($((TOTAL_CHECKS - FAILED_CHECKS))/$TOTAL_CHECKS passed)"
    echo
    echo "❌ Homelab may not function properly"
    echo "🔧 Review failed checks and redeploy services"
fi

echo "═══════════════════════════════════════════════════════════════════"

exit $FAILED_CHECKS