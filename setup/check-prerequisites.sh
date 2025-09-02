#!/bin/bash

# Prerequisites Check for Homelab Deployment
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
log_check() { echo -e "${CYAN}[CHECK]${NC} $1"; }

echo -e "${CYAN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║              Homelab Prerequisites Check                     ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

missing_tools=()
optional_missing=()
warnings=()

# Check essential tools
log_check "Checking essential tools..."

# kubectl
if command -v kubectl &> /dev/null; then
    log_success "kubectl found"
else
    missing_tools+=("kubectl")
    log_error "kubectl not found"
fi

# Git
if command -v git &> /dev/null; then
    log_success "Git found"
else
    missing_tools+=("git")
    log_error "Git not found"
fi

echo

# Check optional tools
log_check "Checking optional tools..."

if command -v yq &> /dev/null; then
    log_success "yq found"
else
    optional_missing+=("yq")
    log_warning "yq not found (recommended)"
fi

if command -v helm &> /dev/null; then
    log_success "Helm found"
else
    optional_missing+=("helm")
    log_warning "Helm not found (useful for charts)"
fi

echo

# Check cluster connectivity
log_check "Checking Kubernetes cluster..."

if command -v kubectl &> /dev/null; then
    if kubectl cluster-info &> /dev/null 2>&1; then
        log_success "Kubernetes cluster accessible"
        
        node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
        if [[ $node_count -gt 0 ]]; then
            log_success "$node_count nodes found"
        fi
    else
        warnings+=("Kubernetes cluster not accessible")
        log_warning "Cluster not accessible"
    fi
fi

echo
echo "═══════════════════════════════════════════════════════════════════"
echo "                           SUMMARY"
echo "═══════════════════════════════════════════════════════════════════"

if [[ ${#missing_tools[@]} -eq 0 ]]; then
    log_success "✅ All essential tools available"
else
    log_error "❌ Missing: ${missing_tools[*]}"
fi

if [[ ${#optional_missing[@]} -gt 0 ]]; then
    log_warning "Optional missing: ${optional_missing[*]}"
fi

echo
if [[ ${#missing_tools[@]} -eq 0 ]]; then
    echo -e "${GREEN}🎉 Ready for homelab deployment!${NC}"
    echo
    echo "Next steps:"
    echo "1. Configure servers in ../nix-config"
    echo "2. Run: ./setup/validate-simple.sh"
    echo "3. Deploy with kubectl apply"
else
    echo -e "${RED}❌ Install missing tools first${NC}"
fi