#!/bin/bash

# Individual Component Deployment Script
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Available components
get_component_path() {
    case $1 in
        "storage") echo "storage/network-storage.yaml" ;;
        "services") echo "services/homelab-services.yaml" ;;
        "smart-home") echo "smart-home/home-assistant.yaml" ;;
        "esphome") echo "smart-home/esphome-devices.yaml" ;;
        "media") echo "media/media-stack.yaml" ;;
        "usenet") echo "media/sabnzbd.yaml" ;;
        "monitoring") echo "monitoring/grafana-homeassistant.yaml" ;;
        "dashboard-api") echo "apps/dashboard/api/deployment.yaml" ;;
        "dashboard-ui") echo "apps/dashboard/ui/deployment.yaml" ;;
        "touchscreen") echo "apps/touchscreen-monitor/touchscreen-dashboard.yaml" ;;
        *) echo "" ;;
    esac
}

list_components() {
    echo "  storage - storage/network-storage.yaml"
    echo "  services - services/homelab-services.yaml"
    echo "  smart-home - smart-home/home-assistant.yaml"
    echo "  esphome - smart-home/esphome-devices.yaml"
    echo "  media - media/media-stack.yaml"
    echo "  usenet - media/sabnzbd.yaml"
    echo "  monitoring - monitoring/grafana-homeassistant.yaml"
    echo "  dashboard-api - apps/dashboard/api/deployment.yaml"
    echo "  dashboard-ui - apps/dashboard/ui/deployment.yaml"
    echo "  touchscreen - apps/touchscreen-monitor/touchscreen-dashboard.yaml"
}

show_help() {
    echo "Usage: $0 <component> [action]"
    echo
    echo "Components:"
    list_components
    echo
    echo "Actions:"
    echo "  deploy   - Deploy component (default)"
    echo "  delete   - Delete component"
    echo "  status   - Show component status"
    echo "  logs     - Show component logs"
    echo
}

deploy_component() {
    local component=$1
    local manifest_path="/Volumes/dev/homelab/$(get_component_path "$component")"
    
    if [[ ! -f "$manifest_path" ]]; then
        log_error "Manifest not found: $manifest_path"
        return 1
    fi
    
    log_info "Deploying $component..."
    
    if kubectl apply -f "$manifest_path"; then
        log_success "Deployed $component"
        
        # Extract namespace from manifest
        local namespace=$(yq eval '.metadata.namespace // "default"' "$manifest_path" 2>/dev/null | head -1)
        if [[ "$namespace" != "null" && "$namespace" != "default" ]]; then
            log_info "Waiting for deployments in namespace $namespace..."
            sleep 5
            kubectl get pods -n "$namespace" 2>/dev/null || true
        fi
    else
        log_error "Failed to deploy $component"
        return 1
    fi
}

delete_component() {
    local component=$1
    local manifest_path="/Volumes/dev/homelab/$(get_component_path "$component")"
    
    if [[ ! -f "$manifest_path" ]]; then
        log_error "Manifest not found: $manifest_path"
        return 1
    fi
    
    log_info "Deleting $component..."
    
    if kubectl delete -f "$manifest_path" --ignore-not-found; then
        log_success "Deleted $component"
    else
        log_error "Failed to delete $component"
        return 1
    fi
}

show_status() {
    local component=$1
    local manifest_path="/Volumes/dev/homelab/$(get_component_path "$component")"
    
    log_info "Status for $component:"
    
    # Get namespace from manifest
    if command -v yq &> /dev/null; then
        local namespace=$(yq eval '.metadata.namespace // "default"' "$manifest_path" 2>/dev/null | head -1)
    else
        local namespace="default"
    fi
    
    if [[ "$namespace" != "null" ]]; then
        echo
        echo "Pods:"
        kubectl get pods -n "$namespace" 2>/dev/null || echo "No pods found"
        echo
        echo "Services:"
        kubectl get services -n "$namespace" 2>/dev/null || echo "No services found"
        echo
        echo "Ingresses:"
        kubectl get ingresses -n "$namespace" 2>/dev/null || echo "No ingresses found"
    fi
}

show_logs() {
    local component=$1
    local manifest_path="/Volumes/dev/homelab/$(get_component_path "$component")"
    
    # Get namespace from manifest
    if command -v yq &> /dev/null; then
        local namespace=$(yq eval '.metadata.namespace // "default"' "$manifest_path" 2>/dev/null | head -1)
    else
        local namespace="default"
    fi
    
    if [[ "$namespace" != "null" ]]; then
        log_info "Recent logs for $component (namespace: $namespace):"
        
        # Get all pods in namespace and show logs
        local pods=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | awk '{print $1}' | head -3)
        
        for pod in $pods; do
            echo
            echo "=== Logs for $pod ==="
            kubectl logs "$pod" -n "$namespace" --tail=10 2>/dev/null || echo "No logs available"
        done
    fi
}

# Main script
if [[ $# -eq 0 ]]; then
    show_help
    exit 1
fi

component=$1
action=${2:-deploy}

if [[ -z "$(get_component_path "$component")" ]]; then
    log_error "Unknown component: $component"
    echo
    show_help
    exit 1
fi

case $action in
    "deploy")
        deploy_component "$component"
        ;;
    "delete")
        delete_component "$component"
        ;;
    "status")
        show_status "$component"
        ;;
    "logs")
        show_logs "$component"
        ;;
    "help")
        show_help
        ;;
    *)
        log_error "Unknown action: $action"
        show_help
        exit 1
        ;;
esac