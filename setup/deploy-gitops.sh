#!/bin/bash

# GitOps Deployment Script - Automated cluster deployment with ArgoCD
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

HOMELAB_DIR="${HOMELAB_DIR:-/Volumes/dev/homelab}"
REPO_URL="${REPO_URL:-}" # Set this to your git repository

echo -e "${CYAN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                   GitOps Homelab Deployment                  ║
║                  Automated with ArgoCD                       ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is required but not installed"
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null 2>&1; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check if ArgoCD CRDs exist
    if ! kubectl get crd applications.argoproj.io &> /dev/null 2>&1; then
        log_info "Installing ArgoCD CRDs..."
        kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
        kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
        
        log_info "Waiting for ArgoCD to be ready..."
        kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
        
        log_success "ArgoCD installed successfully"
    else
        log_info "ArgoCD CRDs already exist"
    fi
}

# Deploy GitOps applications
deploy_gitops() {
    log_info "Deploying GitOps configuration..."
    
    if [[ -z "$REPO_URL" ]]; then
        log_warning "REPO_URL not set - using placeholder"
        log_warning "Update gitops/applications/*.yaml with your repository URL"
    fi
    
    # Apply ArgoCD bootstrap
    if kubectl apply -f "$HOMELAB_DIR/gitops/argocd-bootstrap.yaml"; then
        log_success "ArgoCD bootstrap applied"
    else
        log_error "Failed to apply ArgoCD bootstrap"
        return 1
    fi
    
    # Wait for ArgoCD server
    log_info "Waiting for ArgoCD server to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
    
    # Apply application definitions
    log_info "Deploying homelab applications..."
    kubectl apply -f "$HOMELAB_DIR/gitops/applications/"
    
    log_success "GitOps applications deployed"
}

# Show deployment status
show_status() {
    log_info "Checking deployment status..."
    
    echo
    echo "ArgoCD Applications:"
    kubectl get applications -n argocd -o wide 2>/dev/null || echo "No applications found"
    
    echo
    echo "Homelab Namespaces:"
    kubectl get namespaces | grep -E "(storage|media|smart-home|homelab-services|monitoring|touchscreen)" || echo "No homelab namespaces found"
    
    echo
    echo "ArgoCD Server URL:"
    if kubectl get ingress -n argocd argocd-server &> /dev/null 2>&1; then
        echo "  http://argocd.homelab.local"
    else
        local_port=$(kubectl get svc -n argocd argocd-server -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
        echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
        echo "  Then visit: https://localhost:8080"
    fi
    
    echo
    echo "Initial ArgoCD admin password:"
    kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "Not available yet"
}

# Get ArgoCD password
get_argocd_password() {
    log_info "Getting ArgoCD admin password..."
    
    # Wait for secret to be created
    local retries=30
    while [[ $retries -gt 0 ]]; do
        if kubectl -n argocd get secret argocd-initial-admin-secret &> /dev/null 2>&1; then
            local password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
            echo
            echo "═══════════════════════════════════════════════════════════════════"
            echo "                     ArgoCD CREDENTIALS"
            echo "═══════════════════════════════════════════════════════════════════"
            echo "Username: admin"
            echo "Password: $password"
            echo "URL: http://argocd.homelab.local"
            echo "═══════════════════════════════════════════════════════════════════"
            return 0
        fi
        sleep 5
        ((retries--))
    done
    
    log_warning "ArgoCD password not available yet - check later with:"
    echo "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
}

# Main deployment flow
main() {
    case "${1:-deploy}" in
        "check")
            check_prerequisites
            ;;
        "deploy")
            check_prerequisites
            deploy_gitops
            show_status
            get_argocd_password
            ;;
        "status")
            show_status
            ;;
        "password")
            get_argocd_password
            ;;
        "help"|*)
            echo "Usage: $0 [check|deploy|status|password|help]"
            echo
            echo "  check    - Check prerequisites only"
            echo "  deploy   - Full GitOps deployment (default)"
            echo "  status   - Show deployment status"
            echo "  password - Get ArgoCD admin password"
            echo "  help     - Show this help"
            ;;
    esac
}

main "$@"