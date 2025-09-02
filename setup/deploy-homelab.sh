#!/bin/bash
# Comprehensive Homelab Multi-Architecture Setup Script
# This script deploys all components in the correct order and validates functionality

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if we can connect to cluster
    if ! kubectl cluster-info &> /dev/null; then
        error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check node architectures
    log "Checking node architectures..."
    kubectl get nodes -o custom-columns="NAME:.metadata.name,ARCH:.metadata.labels.kubernetes\.io/arch,STATUS:.status.conditions[?(@.type=='Ready')].status"
    
    # Count nodes by architecture
    AMD64_NODES=$(kubectl get nodes -o jsonpath='{.items[?(@.metadata.labels.kubernetes\.io/arch=="amd64")].metadata.name}' | wc -w)
    ARM64_NODES=$(kubectl get nodes -o jsonpath='{.items[?(@.metadata.labels.kubernetes\.io/arch=="arm64")].metadata.name}' | wc -w)
    ARM_NODES=$(kubectl get nodes -o jsonpath='{.items[?(@.metadata.labels.kubernetes\.io/arch=="arm")].metadata.name}' | wc -w)
    
    log "Found nodes: AMD64=$AMD64_NODES, ARM64=$ARM64_NODES, ARM=$ARM_NODES"
    
    if [ $((AMD64_NODES + ARM64_NODES + ARM_NODES)) -eq 0 ]; then
        error "No nodes found in cluster"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Wait for deployment to be ready
wait_for_deployment() {
    local namespace=$1
    local deployment=$2
    local timeout=${3:-300}
    
    log "Waiting for deployment $deployment in namespace $namespace..."
    
    if kubectl wait --for=condition=available --timeout="${timeout}s" deployment/$deployment -n $namespace; then
        success "Deployment $deployment is ready"
        return 0
    else
        error "Deployment $deployment failed to become ready within ${timeout}s"
        
        # Show pod status for debugging
        log "Pod status for debugging:"
        kubectl get pods -n $namespace -l app=$deployment
        kubectl describe deployment $deployment -n $namespace
        
        return 1
    fi
}

# Wait for StatefulSet to be ready
wait_for_statefulset() {
    local namespace=$1
    local statefulset=$2
    local replicas=$3
    local timeout=${4:-300}
    
    log "Waiting for StatefulSet $statefulset in namespace $namespace..."
    
    local end_time=$(($(date +%s) + timeout))
    
    while [ $(date +%s) -lt $end_time ]; do
        local ready_replicas=$(kubectl get statefulset $statefulset -n $namespace -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        
        if [ "$ready_replicas" -eq "$replicas" ]; then
            success "StatefulSet $statefulset is ready ($ready_replicas/$replicas)"
            return 0
        fi
        
        log "StatefulSet $statefulset: $ready_replicas/$replicas ready..."
        sleep 10
    done
    
    error "StatefulSet $statefulset failed to become ready within ${timeout}s"
    kubectl get statefulset $statefulset -n $namespace
    kubectl get pods -n $namespace -l app=$statefulset
    return 1
}

# Deploy core infrastructure
deploy_core_infrastructure() {
    log "Deploying core infrastructure..."
    
    # Deploy dashboard first (it's our main UI)
    log "Deploying dashboard system..."
    kubectl apply -f /Volumes/dev/homelab/apps/dashboard/api/deployment.yaml || {
        error "Failed to deploy dashboard API"
        return 1
    }
    kubectl apply -f /Volumes/dev/homelab/apps/dashboard/ui/deployment.yaml || {
        error "Failed to deploy dashboard UI"
        return 1
    }
    
    # Wait for dashboard to be ready
    wait_for_deployment default dashboard-api 180
    wait_for_deployment default dashboard-ui 180
    
    success "Core infrastructure deployed"
}

# Deploy GitOps (ArgoCD)
deploy_gitops() {
    log "Deploying GitOps (ArgoCD)..."
    
    # Create namespace
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy ArgoCD
    kubectl apply -f /Volumes/dev/homelab/gitops/argocd-multiarch.yaml || {
        error "Failed to deploy ArgoCD"
        return 1
    }
    
    # Wait for ArgoCD server
    wait_for_deployment argocd argocd-server 300
    
    success "GitOps (ArgoCD) deployed"
}

# Deploy service mesh
deploy_service_mesh() {
    log "Deploying service mesh (Linkerd)..."
    
    # Create namespace
    kubectl create namespace linkerd --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy Linkerd
    kubectl apply -f /Volumes/dev/homelab/service-mesh/linkerd-multiarch.yaml || {
        error "Failed to deploy Linkerd"
        return 1
    }
    
    # Wait for Linkerd control plane
    wait_for_deployment linkerd linkerd-controller 300
    wait_for_deployment linkerd linkerd-proxy-injector 300
    
    success "Service mesh deployed"
}

# Deploy observability stack
deploy_observability() {
    log "Deploying observability stack..."
    
    # Deploy Jaeger tracing
    log "Deploying Jaeger tracing..."
    kubectl apply -f /Volumes/dev/homelab/observability/jaeger-tracing.yaml || {
        error "Failed to deploy Jaeger"
        return 1
    }
    
    # Deploy ELK logging
    log "Deploying ELK logging..."
    kubectl apply -f /Volumes/dev/homelab/observability/elk-logging.yaml || {
        error "Failed to deploy ELK"
        return 1
    }
    
    # Wait for Elasticsearch (it takes time)
    wait_for_statefulset tracing elasticsearch 1 600
    wait_for_statefulset logging elasticsearch 1 600
    
    # Wait for other components
    wait_for_deployment tracing jaeger-collector 300
    wait_for_deployment tracing jaeger-query 300
    wait_for_deployment logging kibana 300
    
    success "Observability stack deployed"
}

# Deploy event-driven architecture
deploy_event_driven() {
    log "Deploying event-driven architecture (NATS)..."
    
    kubectl apply -f /Volumes/dev/homelab/event-driven/nats-cloudevents.yaml || {
        error "Failed to deploy NATS"
        return 1
    }
    
    # Wait for NATS cluster
    wait_for_statefulset event-driven nats 3 300
    
    # Wait for event components
    wait_for_deployment event-driven event-producer 180
    wait_for_deployment event-driven event-router 180
    
    success "Event-driven architecture deployed"
}

# Deploy ML serving
deploy_ml_serving() {
    log "Deploying ML serving platform..."
    
    kubectl apply -f /Volumes/dev/homelab/ml-serving/kserve-multiarch.yaml || {
        error "Failed to deploy ML serving"
        return 1
    }
    
    # Wait for storage backend (MinIO)
    wait_for_deployment ml-serving minio 180
    
    # Wait for model registry
    wait_for_deployment ml-serving model-registry 180
    
    # Wait for serving components (they depend on architecture)
    if [ $AMD64_NODES -gt 0 ]; then
        wait_for_deployment ml-serving tensorflow-serving-amd64 300 || warning "TensorFlow serving not ready on AMD64"
    fi
    
    if [ $ARM64_NODES -gt 0 ]; then
        wait_for_deployment ml-serving sklearn-serving-arm64 180 || warning "Scikit-learn serving not ready on ARM64"
    fi
    
    # Run model deployment job
    log "Deploying sample ML models..."
    kubectl apply -f /Volumes/dev/homelab/ml-serving/kserve-multiarch.yaml
    
    # Wait for job to complete
    kubectl wait --for=condition=complete --timeout=300s job/ml-model-deployer -n ml-serving || {
        warning "Model deployment job did not complete successfully"
        kubectl logs job/ml-model-deployer -n ml-serving
    }
    
    success "ML serving platform deployed"
}

# Deploy CI/CD
deploy_cicd() {
    log "Deploying CI/CD (Tekton)..."
    
    kubectl apply -f /Volumes/dev/homelab/cicd/tekton-pipelines.yaml || {
        error "Failed to deploy Tekton"
        return 1
    }
    
    # Wait for Tekton dashboard
    wait_for_deployment tekton-pipelines tekton-dashboard 180
    
    # Wait for registry
    wait_for_deployment tekton-pipelines docker-registry 180
    
    success "CI/CD platform deployed"
}

# Deploy progressive delivery
deploy_progressive_delivery() {
    log "Deploying progressive delivery (Flagger)..."
    
    kubectl apply -f /Volumes/dev/homelab/progressive-delivery/flagger-multiarch.yaml || {
        error "Failed to deploy Flagger"
        return 1
    }
    
    # Wait for Flagger
    wait_for_deployment flagger-system flagger 180
    wait_for_deployment flagger-system prometheus 180
    
    success "Progressive delivery deployed"
}

# Deploy chaos engineering
deploy_chaos_engineering() {
    log "Deploying chaos engineering (Litmus)..."
    
    kubectl apply -f /Volumes/dev/homelab/chaos-engineering/litmus-multiarch.yaml || {
        error "Failed to deploy Litmus"
        return 1
    }
    
    # Wait for Litmus components
    wait_for_deployment litmus chaos-center-frontend 300
    wait_for_deployment litmus chaos-center-backend 300
    wait_for_deployment litmus mongo 180
    
    success "Chaos engineering deployed"
}

# Deploy backup and disaster recovery
deploy_backup_system() {
    log "Deploying backup system (Velero)..."
    
    kubectl apply -f /Volumes/dev/homelab/backup/velero-multiarch.yaml || {
        error "Failed to deploy Velero"
        return 1
    }
    
    # Wait for Velero components
    wait_for_deployment velero velero 300
    wait_for_deployment velero backup-minio 180
    wait_for_deployment velero backup-manager 180
    
    success "Backup system deployed"
}

# Validate system functionality
validate_system() {
    log "Validating system functionality..."
    
    # Test dashboard API
    log "Testing dashboard API..."
    if kubectl port-forward -n default svc/dashboard-api 8080:8080 &
    then
        DASHBOARD_PID=$!
        sleep 5
        
        if curl -f http://localhost:8080/health > /dev/null 2>&1; then
            success "Dashboard API is responding"
        else
            warning "Dashboard API is not responding"
        fi
        
        kill $DASHBOARD_PID 2>/dev/null || true
    fi
    
    # Test NATS connectivity
    log "Testing NATS connectivity..."
    if kubectl port-forward -n event-driven svc/nats 4222:4222 &
    then
        NATS_PID=$!
        sleep 5
        
        # Try to connect to NATS
        if curl -f http://localhost:8222/ > /dev/null 2>&1; then
            success "NATS is responding"
        else
            warning "NATS monitoring is not responding"
        fi
        
        kill $NATS_PID 2>/dev/null || true
    fi
    
    # Test MinIO
    log "Testing MinIO (ML model storage)..."
    if kubectl port-forward -n ml-serving svc/minio 9000:9000 &
    then
        MINIO_PID=$!
        sleep 5
        
        if curl -f http://localhost:9000/minio/health/live > /dev/null 2>&1; then
            success "MinIO is responding"
        else
            warning "MinIO is not responding"
        fi
        
        kill $MINIO_PID 2>/dev/null || true
    fi
    
    # Check pod distribution across architectures
    log "Checking pod distribution across architectures..."
    
    if [ $AMD64_NODES -gt 0 ]; then
        AMD64_PODS=$(kubectl get pods --all-namespaces -o wide | grep -E "amd64|x86_64" | wc -l || echo 0)
        log "Pods on AMD64 nodes: $AMD64_PODS"
    fi
    
    if [ $ARM64_NODES -gt 0 ]; then
        ARM64_PODS=$(kubectl get pods --all-namespaces -o wide | grep -E "arm64|aarch64" | wc -l || echo 0)
        log "Pods on ARM64 nodes: $ARM64_PODS"
    fi
    
    if [ $ARM_NODES -gt 0 ]; then
        ARM_PODS=$(kubectl get pods --all-namespaces -o wide | grep -E "\barm\b" | wc -l || echo 0)
        log "Pods on ARM nodes: $ARM_PODS"
    fi
    
    success "System validation completed"
}

# Show access information
show_access_info() {
    log "System deployment complete! Here's how to access your services:"
    
    echo ""
    echo "🖥️  Dashboard:"
    echo "   kubectl port-forward -n default svc/dashboard-ui 3000:3000"
    echo "   Then open: http://localhost:3000"
    echo ""
    
    echo "🚀 ArgoCD:"
    echo "   kubectl port-forward -n argocd svc/argocd-server 8080:80"
    echo "   Then open: http://localhost:8080"
    echo "   Username: admin"
    echo "   Password: kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d"
    echo ""
    
    echo "📊 Jaeger Tracing:"
    echo "   kubectl port-forward -n tracing svc/jaeger-query 16686:80"
    echo "   Then open: http://localhost:16686"
    echo ""
    
    echo "📝 Kibana (Logs):"
    echo "   kubectl port-forward -n logging svc/kibana 5601:5601"
    echo "   Then open: http://localhost:5601"
    echo ""
    
    echo "🤖 ML Model Registry:"
    echo "   kubectl port-forward -n ml-serving svc/model-registry 8000:8000"
    echo "   Then open: http://localhost:8000/docs"
    echo ""
    
    echo "🔄 NATS Monitoring:"
    echo "   kubectl port-forward -n event-driven svc/nats 8222:8222"
    echo "   Then open: http://localhost:8222"
    echo ""
    
    echo "🏗️  Tekton Dashboard:"
    echo "   kubectl port-forward -n tekton-pipelines svc/tekton-dashboard 9097:9097"
    echo "   Then open: http://localhost:9097"
    echo ""
    
    echo "🚀 Flagger Dashboard:"
    echo "   kubectl port-forward -n flagger-system svc/prometheus 9090:9090"
    echo "   Then open: http://localhost:9090"
    echo ""
    
    echo "🔥 Chaos Center (Litmus):"
    echo "   kubectl port-forward -n litmus svc/chaos-center-frontend-service 9091:9091"
    echo "   Then open: http://localhost:9091"
    echo ""
    
    echo "💾 Backup Console (MinIO):"
    echo "   kubectl port-forward -n velero svc/backup-minio 9001:9001"
    echo "   Then open: http://localhost:9001"
    echo "   Username: velero / Password: velero-backup-secret-key"
    echo ""
    
    echo "💾 ML Storage Console:"
    echo "   kubectl port-forward -n ml-serving svc/minio 9001:9001"
    echo "   Then open: http://localhost:9001"
    echo "   Username: admin / Password: minio123"
    echo ""
}

# Troubleshooting function
troubleshoot() {
    log "Running troubleshooting checks..."
    
    # Check failed pods
    echo "❌ Failed/Pending Pods:"
    kubectl get pods --all-namespaces | grep -E "(Error|CrashLoopBackOff|Pending|ImagePullBackOff)" || echo "  No failed pods found"
    
    echo ""
    echo "📊 Resource Usage by Node:"
    kubectl top nodes 2>/dev/null || echo "  Metrics server not available"
    
    echo ""
    echo "🔍 Events (last 10):"
    kubectl get events --all-namespaces --sort-by=.metadata.creationTimestamp | tail -10
    
    echo ""
    echo "💾 Storage Classes:"
    kubectl get storageclass
    
    echo ""
    echo "🌐 Services without Endpoints:"
    for namespace in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
        kubectl get endpoints -n $namespace -o json | jq -r '.items[] | select(.subsets == null) | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null || true
    done
}

# Main deployment function
main() {
    log "Starting Homelab Multi-Architecture System Deployment"
    log "=============================================="
    
    case "${1:-deploy}" in
        "deploy")
            check_prerequisites
            
            deploy_core_infrastructure
            deploy_gitops
            deploy_service_mesh
            deploy_observability
            deploy_event_driven
            deploy_ml_serving
            deploy_cicd
            deploy_progressive_delivery
            deploy_chaos_engineering
            deploy_backup_system
            
            validate_system
            show_access_info
            
            success "🎉 Complete homelab deployment finished successfully!"
            ;;
            
        "validate")
            validate_system
            show_access_info
            ;;
            
        "troubleshoot")
            troubleshoot
            ;;
            
        "clean")
            warning "Cleaning up all resources..."
            kubectl delete namespace argocd --ignore-not-found
            kubectl delete namespace linkerd --ignore-not-found
            kubectl delete namespace tracing --ignore-not-found
            kubectl delete namespace logging --ignore-not-found
            kubectl delete namespace event-driven --ignore-not-found
            kubectl delete namespace ml-serving --ignore-not-found
            kubectl delete namespace tekton-pipelines --ignore-not-found
            
            # Clean up dashboard in default namespace
            kubectl delete deployment dashboard-api dashboard-ui -n default --ignore-not-found
            kubectl delete service dashboard-api dashboard-ui -n default --ignore-not-found
            
            success "Cleanup completed"
            ;;
            
        *)
            echo "Usage: $0 [deploy|validate|troubleshoot|clean]"
            echo ""
            echo "Commands:"
            echo "  deploy       - Deploy the entire homelab system (default)"
            echo "  validate     - Validate system and show access info"
            echo "  troubleshoot - Run troubleshooting checks"
            echo "  clean        - Clean up all deployed resources"
            exit 1
            ;;
    esac
}

main "$@"