#!/bin/bash

# Homelab Deployment Verification Script
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
║              Homelab Deployment Verification                 ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

if ! command -v kubectl &> /dev/null; then
    log_error "kubectl not found. Cannot verify deployment."
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    log_error "Kubernetes cluster not accessible."
    exit 1
fi

echo

# Check cluster health
log_check "Checking cluster health..."

nodes_ready=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo "0")
nodes_total=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')

if [[ $nodes_ready -eq $nodes_total && $nodes_total -gt 0 ]]; then
    log_success "All $nodes_total nodes are ready"
else
    log_warning "$nodes_ready/$nodes_total nodes ready"
fi

echo

# Check homelab namespaces
log_check "Checking homelab namespaces..."

expected_namespaces=("storage" "media" "smart-home" "homelab-services" "monitoring")

for ns in "${expected_namespaces[@]}"; do
    if kubectl get namespace "$ns" &> /dev/null; then
        running_pods=$(kubectl get pods -n "$ns" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
        total_pods=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
        
        if [[ $running_pods -eq $total_pods && $total_pods -gt 0 ]]; then
            log_success "Namespace $ns: $running_pods/$total_pods pods running"
        elif [[ $total_pods -gt 0 ]]; then
            log_warning "Namespace $ns: $running_pods/$total_pods pods running"
        else
            log_info "Namespace $ns: no pods deployed"
        fi
    else
        log_warning "Namespace $ns: not found"
    fi
done

echo

# Check storage
log_check "Checking storage..."

storage_classes=$(kubectl get storageclass --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ $storage_classes -gt 0 ]]; then
    log_success "$storage_classes storage classes available"
else
    log_warning "No storage classes found"
fi

echo

# Summary
total_pods=$(kubectl get pods --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')
running_pods=$(kubectl get pods --all-namespaces --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')

echo "═══════════════════════════════════════════════════════════════════"
echo "                      DEPLOYMENT STATUS"
echo "═══════════════════════════════════════════════════════════════════"
echo
echo "Cluster: $nodes_ready/$nodes_total nodes ready"
echo "Pods: $running_pods/$total_pods running"
echo "Storage: $storage_classes classes available"
echo

if [[ $running_pods -eq $total_pods && $total_pods -gt 0 ]]; then
    log_success "🎉 Homelab deployment is healthy!"
    echo "Access: http://homer.homelab.local"
elif [[ $total_pods -eq 0 ]]; then
    log_warning "⚠️  No services deployed yet"
    echo "Deploy with: kubectl apply -f <manifest>"
else
    log_warning "⚠️  Some services still starting"
fi