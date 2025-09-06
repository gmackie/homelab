#!/bin/bash

# Homelab Troubleshooting Script - Diagnose and fix common issues
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_debug() { echo -e "${MAGENTA}[DEBUG]${NC} $1"; }

echo -e "${CYAN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                Homelab Troubleshooting Tool                  ║
║              Diagnose & Fix Common Issues                     ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Check for common issues
check_pod_issues() {
    log_info "🔍 Checking for pod issues..."
    
    # Find failed pods
    local failed_pods=$(kubectl get pods --all-namespaces --field-selector=status.phase=Failed --no-headers 2>/dev/null | wc -l)
    local pending_pods=$(kubectl get pods --all-namespaces --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l)
    
    if [[ "$failed_pods" -gt "0" ]]; then
        log_error "Found $failed_pods failed pods:"
        kubectl get pods --all-namespaces --field-selector=status.phase=Failed 2>/dev/null
        
        echo
        log_info "Getting logs from failed pods..."
        kubectl get pods --all-namespaces --field-selector=status.phase=Failed --no-headers 2>/dev/null | \
            head -3 | while read ns pod rest; do
                echo "=== Logs for $ns/$pod ==="
                kubectl logs "$pod" -n "$ns" --tail=10 2>/dev/null || echo "No logs available"
                echo
            done
    fi
    
    if [[ "$pending_pods" -gt "0" ]]; then
        log_warning "Found $pending_pods pending pods:"
        kubectl get pods --all-namespaces --field-selector=status.phase=Pending 2>/dev/null
        
        echo
        log_info "Checking pending pod events..."
        kubectl get pods --all-namespaces --field-selector=status.phase=Pending --no-headers 2>/dev/null | \
            head -3 | while read ns pod rest; do
                echo "=== Events for $ns/$pod ==="
                kubectl describe pod "$pod" -n "$ns" | grep -A 10 "Events:" || echo "No events"
                echo
            done
    fi
    
    if [[ "$failed_pods" == "0" ]] && [[ "$pending_pods" == "0" ]]; then
        log_success "No problematic pods found"
    fi
}

# Check resource constraints
check_resources() {
    log_info "📊 Checking resource constraints..."
    
    if command -v kubectl top &> /dev/null && kubectl top nodes &> /dev/null 2>&1; then
        log_info "Node resource usage:"
        kubectl top nodes 2>/dev/null
        
        # Check for resource pressure
        kubectl describe nodes 2>/dev/null | grep -A 5 "Conditions:" | grep -E "(MemoryPressure|DiskPressure|PIDPressure)" | \
            grep "True" && log_warning "Found resource pressure on nodes" || log_success "No resource pressure detected"
    else
        log_warning "Metrics server not available - cannot check resource usage"
    fi
    
    # Check PVC status
    log_info "Persistent Volume Claims:"
    kubectl get pvc --all-namespaces 2>/dev/null | head -10
}

# Check network connectivity
check_networking() {
    log_info "🌐 Checking network connectivity..."
    
    # Check ingress controller
    if kubectl get pods -l app.kubernetes.io/name=ingress-nginx --all-namespaces &> /dev/null 2>&1; then
        log_success "Ingress controller found"
    else
        log_warning "No ingress controller detected"
        log_info "Consider installing nginx-ingress or traefik"
    fi
    
    # Check DNS resolution
    if kubectl get service kube-dns -n kube-system &> /dev/null 2>&1; then
        log_success "CoreDNS service found"
    else
        log_warning "DNS service issues detected"
    fi
    
    # Check service endpoints
    log_info "Checking service endpoints..."
    problematic_services=$(kubectl get endpoints --all-namespaces --no-headers 2>/dev/null | awk '$3 == "" || $3 == "<none>" {print $1"/"$2}' | wc -l)
    
    if [[ "$problematic_services" -gt "0" ]]; then
        log_warning "Found $problematic_services services without endpoints:"
        kubectl get endpoints --all-namespaces --no-headers 2>/dev/null | awk '$3 == "" || $3 == "<none>" {print "  " $1"/"$2}'
    else
        log_success "All services have healthy endpoints"
    fi
}

# Check storage issues
check_storage_issues() {
    log_info "💾 Checking storage issues..."
    
    # Check PV status
    pv_issues=$(kubectl get pv --no-headers 2>/dev/null | grep -v Available | grep -v Bound | wc -l)
    if [[ "$pv_issues" -gt "0" ]]; then
        log_warning "Found PV issues:"
        kubectl get pv | grep -v Available | grep -v Bound
    else
        log_success "All Persistent Volumes healthy"
    fi
    
    # Check storage classes
    if kubectl get storageclass &> /dev/null 2>&1; then
        log_info "Available storage classes:"
        kubectl get storageclass
    else
        log_warning "No storage classes found"
    fi
}

# Architecture-specific checks
check_architecture_placement() {
    log_info "🏗️ Checking architecture placement..."
    
    # Get node architectures
    log_info "Node architecture distribution:"
    kubectl get nodes -o custom-columns="NAME:.metadata.name,ARCH:.status.nodeInfo.architecture" --no-headers 2>/dev/null
    
    # Check pod placement
    log_info "Checking pod placement across architectures..."
    
    # Heavy workloads should be on AMD64
    heavy_workloads=("jellyfin" "radarr" "sonarr" "sabnzbd")
    for workload in "${heavy_workloads[@]}"; do
        if kubectl get pod -l app="$workload" --all-namespaces -o wide 2>/dev/null | grep -q .; then
            local arch=$(kubectl get pod -l app="$workload" --all-namespaces -o jsonpath='{.items[0].spec.nodeSelector.kubernetes\.io/arch}' 2>/dev/null || echo "not-specified")
            if [[ "$arch" == "amd64" ]] || [[ "$arch" == "not-specified" ]]; then
                log_success "$workload: optimal placement"
            else
                log_warning "$workload: running on $arch (consider AMD64)"
            fi
        fi
    done
}

# Show service URLs
show_service_urls() {
    log_info "🔗 Service URLs for troubleshooting..."
    
    echo "Main Services:"
    echo "  🏠 Homer Dashboard: http://homer.homelab.local"
    echo "  📱 Touchscreen Monitor: http://touchscreen.homelab.local"
    echo "  🏠 Home Assistant: http://homeassistant.homelab.local"
    echo "  📊 Grafana: http://grafana.homelab.local"
    echo "  🎬 Jellyfin: http://jellyfin.homelab.local"
    echo "  🛡️ Pi-hole: http://pihole.homelab.local/admin"
    echo "  📦 Portainer: http://portainer.homelab.local"
    echo
    
    if kubectl get ingress --all-namespaces &> /dev/null 2>&1; then
        log_info "All configured ingresses:"
        kubectl get ingress --all-namespaces -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,HOST:.spec.rules[0].host" --no-headers 2>/dev/null | \
            sort | while read line; do echo "  $line"; done
    fi
}

# Quick fixes
apply_quick_fixes() {
    log_info "🔧 Applying quick fixes..."
    
    # Restart failed deployments
    failed_deployments=$(kubectl get deployments --all-namespaces --no-headers 2>/dev/null | awk '$3 != $4 {print $1"/"$2}')
    
    if [[ -n "$failed_deployments" ]]; then
        log_info "Restarting problematic deployments..."
        echo "$failed_deployments" | while read deploy; do
            ns=$(echo "$deploy" | cut -d/ -f1)
            name=$(echo "$deploy" | cut -d/ -f2)
            log_info "Restarting $ns/$name..."
            kubectl rollout restart deployment "$name" -n "$ns" 2>/dev/null || true
        done
        
        log_info "Waiting for rollouts to complete..."
        sleep 10
    fi
    
    # Clean up completed jobs
    completed_jobs=$(kubectl get jobs --all-namespaces --field-selector=status.conditions[0].type=Complete --no-headers 2>/dev/null | wc -l)
    if [[ "$completed_jobs" -gt "0" ]]; then
        log_info "Cleaning up $completed_jobs completed jobs..."
        kubectl delete jobs --all-namespaces --field-selector=status.conditions[0].type=Complete 2>/dev/null || true
    fi
}

# Generate troubleshooting report
generate_report() {
    local report_file="/tmp/homelab-troubleshooting-$(date +%Y%m%d-%H%M%S).log"
    
    log_info "📋 Generating troubleshooting report..."
    
    {
        echo "Homelab Troubleshooting Report"
        echo "=============================="
        echo "Generated: $(date)"
        echo "Host: $(hostname)"
        echo
        
        echo "Cluster Info:"
        kubectl cluster-info 2>/dev/null || echo "Cluster not accessible"
        echo
        
        echo "Nodes:"
        kubectl get nodes -o wide 2>/dev/null || echo "Cannot get nodes"
        echo
        
        echo "Problematic Pods:"
        kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null || echo "Cannot get pods"
        echo
        
        echo "Recent Events:"
        kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20 2>/dev/null || echo "Cannot get events"
        echo
        
        echo "Resource Usage:"
        kubectl top nodes 2>/dev/null || echo "Metrics not available"
        echo
        
    } > "$report_file"
    
    log_success "Report saved to: $report_file"
}

# Interactive mode
interactive_mode() {
    while true; do
        echo
        echo "═══════════════════════════════════════════════════════════════════"
        echo "Select troubleshooting action:"
        echo "1) Check pod issues"
        echo "2) Check resources"
        echo "3) Check networking" 
        echo "4) Check storage"
        echo "5) Check architecture placement"
        echo "6) Show service URLs"
        echo "7) Apply quick fixes"
        echo "8) Generate full report"
        echo "9) Run all checks"
        echo "0) Exit"
        echo "═══════════════════════════════════════════════════════════════════"
        
        read -p "Enter choice [0-9]: " choice
        
        case $choice in
            1) check_pod_issues ;;
            2) check_resources ;;
            3) check_networking ;;
            4) check_storage_issues ;;
            5) check_architecture_placement ;;
            6) show_service_urls ;;
            7) apply_quick_fixes ;;
            8) generate_report ;;
            9) 
                check_pod_issues
                check_resources
                check_networking
                check_storage_issues
                check_architecture_placement
                ;;
            0) 
                log_info "Exiting troubleshooting tool"
                exit 0 ;;
            *) 
                log_error "Invalid choice: $choice" ;;
        esac
    done
}

# Main function
main() {
    case "${1:-interactive}" in
        "pods")
            check_pod_issues
            ;;
        "resources")
            check_resources
            ;;
        "network")
            check_networking
            ;;
        "storage")
            check_storage_issues
            ;;
        "arch")
            check_architecture_placement
            ;;
        "urls")
            show_service_urls
            ;;
        "fix")
            apply_quick_fixes
            ;;
        "report")
            generate_report
            ;;
        "all")
            check_pod_issues
            check_resources
            check_networking
            check_storage_issues
            check_architecture_placement
            show_service_urls
            ;;
        "interactive"|"help"|*)
            echo "Usage: $0 [pods|resources|network|storage|arch|urls|fix|report|all|interactive]"
            echo
            echo "  pods        - Check pod issues"
            echo "  resources   - Check resource constraints"
            echo "  network     - Check networking issues"
            echo "  storage     - Check storage issues"
            echo "  arch        - Check architecture placement"
            echo "  urls        - Show service URLs"
            echo "  fix         - Apply quick fixes"
            echo "  report      - Generate troubleshooting report"
            echo "  all         - Run all checks"
            echo "  interactive - Interactive mode (default)"
            echo
            
            if [[ "${1:-}" != "help" ]]; then
                interactive_mode
            fi
            ;;
    esac
}

main "$@"