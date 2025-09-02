#!/bin/bash

set -e

echo "🏠 Complete Homelab Multi-Architecture Setup"
echo "============================================"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${PURPLE}[SUCCESS]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    step "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Deploy networking
deploy_networking() {
    step "Deploying networking components..."
    
    log "Installing Traefik ingress controller..."
    kubectl apply -f networking/ingress-controller.yaml
    
    log "Setting up internal DNS with PiHole..."
    kubectl apply -f networking/internal-dns.yaml
    
    log "Waiting for networking components to be ready..."
    kubectl wait --for=condition=ready pod -l app=traefik -n traefik-system --timeout=300s
    kubectl wait --for=condition=ready pod -l app=pihole -n dns-system --timeout=300s
    
    success "Networking deployed successfully"
}

# Deploy storage
deploy_storage() {
    step "Deploying storage components..."
    
    log "Installing Longhorn distributed storage..."
    kubectl apply -f storage/longhorn-multiarch.yaml
    
    log "Setting up backup strategy..."
    kubectl apply -f storage/backup-strategy.yaml
    
    log "Waiting for storage to be ready..."
    kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=600s
    
    success "Storage deployed successfully"
}

# Deploy security
deploy_security() {
    step "Deploying security components..."
    
    log "Setting up RBAC and security policies..."
    kubectl apply -f security/rbac-multiarch.yaml
    
    log "Installing cert-manager..."
    # First install cert-manager CRDs and main components
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.1/cert-manager.crds.yaml
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.1/cert-manager.yaml
    
    log "Waiting for cert-manager to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=cert-manager -n cert-manager --timeout=300s
    
    log "Setting up certificate issuers..."
    kubectl apply -f security/cert-manager-multiarch.yaml
    
    success "Security components deployed successfully"
}

# Deploy monitoring
deploy_monitoring() {
    step "Deploying monitoring stack..."
    
    log "Installing Prometheus with multi-arch support..."
    kubectl apply -f monitoring/prometheus-multiarch.yaml
    
    log "Waiting for monitoring to be ready..."
    kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=300s
    
    success "Monitoring deployed successfully"
}

# Deploy maintenance
deploy_maintenance() {
    step "Setting up maintenance automation..."
    
    log "Installing update and maintenance jobs..."
    kubectl apply -f maintenance/auto-update-multiarch.yaml
    
    # Create k3s token secret (user needs to provide this)
    warn "Please create k3s token secret:"
    echo "kubectl create secret generic k3s-token --from-literal=token=\$K3S_TOKEN -n system-maintenance"
    
    success "Maintenance automation configured"
}

# Deploy multi-arch services
deploy_services() {
    step "Deploying multi-architecture services..."
    
    log "Running multi-arch service deployment..."
    ./deploy-multi-arch-services.sh
    
    success "Multi-architecture services deployed"
}

# Configure dashboard
configure_dashboard() {
    step "Configuring dashboard with architecture support..."
    
    log "Building and deploying dashboard API..."
    cd apps/dashboard/api
    
    # Build multi-arch image
    if command -v docker &> /dev/null && docker buildx version &> /dev/null; then
        docker buildx create --name homelab-builder --use 2>/dev/null || docker buildx use homelab-builder
        docker buildx build \
            --platform linux/amd64,linux/arm64 \
            --tag homelab/dashboard-api:latest \
            --load \
            .
    else
        docker build -t homelab/dashboard-api:latest .
    fi
    
    cd ../../../
    
    log "Deploying dashboard..."
    kubectl apply -f apps/dashboard/k8s/
    
    log "Waiting for dashboard to be ready..."
    kubectl wait --for=condition=ready pod -l app=homelab-dashboard -n dashboard --timeout=300s
    
    success "Dashboard configured and deployed"
}

# Generate configuration summary
generate_summary() {
    step "Generating deployment summary..."
    
    echo ""
    echo "🎉 HOMELAB DEPLOYMENT COMPLETE! 🎉"
    echo "=================================="
    echo ""
    
    # Cluster information
    log "Cluster Information:"
    kubectl get nodes -o custom-columns="NAME:.metadata.name,ARCH:.metadata.labels.kubernetes\.io/arch,ROLE:.metadata.labels.node-role/compute,POWER:.metadata.labels.power-class" --no-headers | while read line; do
        echo "  $line"
    done
    
    echo ""
    
    # Service URLs
    log "Service Access URLs:"
    
    # Get LoadBalancer IPs
    TRAEFIK_IP=$(kubectl get service traefik -n traefik-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
    DASHBOARD_IP=$(kubectl get service homelab-dashboard-nodeport -n dashboard -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "30080")
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    
    if [ "$TRAEFIK_IP" != "pending" ]; then
        echo "  🌐 Traefik Dashboard: https://$TRAEFIK_IP:8080"
        echo "  🏠 Dashboard: https://$TRAEFIK_IP (dashboard.homelab.local)"
        echo "  🔍 Prometheus: https://$TRAEFIK_IP (prometheus.homelab.local)"
        echo "  🛡️  PiHole: https://$TRAEFIK_IP (pihole.homelab.local)"
    else
        echo "  🏠 Dashboard: http://$NODE_IP:$DASHBOARD_IP"
        echo "  (Configure LoadBalancer for other services)"
    fi
    
    echo ""
    
    # Power consumption
    log "Power Consumption Estimate:"
    amd64_nodes=$(kubectl get nodes -l kubernetes.io/arch=amd64 --no-headers | wc -l)
    arm64_nodes=$(kubectl get nodes -l kubernetes.io/arch=arm64 --no-headers | wc -l)
    arm_nodes=$(kubectl get nodes -l kubernetes.io/arch=arm --no-headers | wc -l)
    
    total_power=$((amd64_nodes * 45 + arm64_nodes * 7 + arm_nodes * 3))
    echo "  ⚡ Total Estimated Power: ${total_power}W"
    echo "    - AMD64 nodes ($amd64_nodes): $((amd64_nodes * 45))W (compute/storage)"
    echo "    - ARM64 nodes ($arm64_nodes): $((arm64_nodes * 7))W (edge services)"
    echo "    - ARM nodes ($arm_nodes): $((arm_nodes * 3))W (sensors/IoT)"
    
    echo ""
    
    # Architecture distribution
    log "Workload Distribution:"
    echo "  🖥️  AMD64: Databases, media servers, CI/CD, heavy compute"
    echo "  🥧 ARM64: Web servers, DNS, monitoring, edge services"
    echo "  📱 ARM: Sensors, probes, lightweight monitoring"
    
    echo ""
    
    # Next steps
    log "Next Steps:"
    echo "  1. Update DNS entries to point to your services"
    echo "  2. Configure external domain for Let's Encrypt certificates"
    echo "  3. Set up monitoring alerts and notifications"
    echo "  4. Deploy additional applications using architecture affinity"
    echo "  5. Configure backup destinations (external storage)"
    
    echo ""
    
    # Credentials and tokens
    warn "Important Credentials:"
    echo "  - PiHole Admin: Check secret 'pihole-secret' in dns-system namespace"
    echo "  - PostgreSQL: Check secret 'postgres-secret' in database namespace"
    echo "  - Certificates: Auto-generated by cert-manager"
    
    echo ""
    success "Your multi-architecture homelab is ready! 🚀"
}

# Main execution
main() {
    echo "Starting complete homelab deployment..."
    echo "This will set up a production-ready multi-architecture cluster"
    echo ""
    
    read -p "Continue with deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled"
        exit 1
    fi
    
    check_prerequisites
    deploy_networking
    deploy_storage
    deploy_security
    deploy_monitoring
    deploy_maintenance
    deploy_services
    configure_dashboard
    generate_summary
}

# Handle script arguments
case "${1:-}" in
    "networking")
        deploy_networking
        ;;
    "storage")
        deploy_storage
        ;;
    "security")
        deploy_security
        ;;
    "monitoring")
        deploy_monitoring
        ;;
    "maintenance")
        deploy_maintenance
        ;;
    "services")
        deploy_services
        ;;
    "dashboard")
        configure_dashboard
        ;;
    "summary")
        generate_summary
        ;;
    *)
        main
        ;;
esac