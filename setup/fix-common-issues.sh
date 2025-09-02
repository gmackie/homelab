#!/bin/bash
# Quick Fix Script for Common Homelab Issues

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date +'%H:%M:%S')] $1${NC}"; }
success() { echo -e "${GREEN}[$(date +'%H:%M:%S')] ✅ $1${NC}"; }
warning() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] ⚠️  $1${NC}"; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ❌ $1${NC}"; }

# Fix pending pods due to architecture mismatch
fix_pending_pods() {
    log "Fixing pending pods with architecture issues..."
    
    local pending_pods=$(kubectl get pods --all-namespaces | grep Pending | awk '{print $2 " " $1}')
    
    if [ -z "$pending_pods" ]; then
        success "No pending pods found"
        return 0
    fi
    
    echo "$pending_pods" | while read pod namespace; do
        log "Checking pod $pod in namespace $namespace"
        
        # Get pod description to check for scheduling issues
        local describe_output=$(kubectl describe pod "$pod" -n "$namespace")
        
        if echo "$describe_output" | grep -q "didn't match Pod's node affinity/selector"; then
            warning "Pod $pod has node affinity issues, attempting to fix..."
            
            # Get the deployment name
            local deployment=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.metadata.labels.app}')
            
            if [ -n "$deployment" ]; then
                # Make affinity more permissive
                kubectl patch deployment "$deployment" -n "$namespace" --type='merge' -p '{
                  "spec": {
                    "template": {
                      "spec": {
                        "affinity": {
                          "nodeAffinity": {
                            "preferredDuringSchedulingIgnoredDuringExecution": [
                              {
                                "weight": 100,
                                "preference": {
                                  "matchExpressions": [
                                    {
                                      "key": "kubernetes.io/arch",
                                      "operator": "In",
                                      "values": ["amd64", "arm64", "arm"]
                                    }
                                  ]
                                }
                              }
                            ]
                          }
                        }
                      }
                    }
                  }
                }' 2>/dev/null && success "Fixed affinity for $deployment" || warning "Could not patch $deployment"
            fi
        fi
        
        if echo "$describe_output" | grep -q "Insufficient.*resources"; then
            warning "Pod $pod has resource constraints, reducing requirements..."
            
            local deployment=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.metadata.labels.app}')
            
            if [ -n "$deployment" ]; then
                # Reduce resource requirements
                kubectl patch deployment "$deployment" -n "$namespace" --type='json' -p '[{
                  "op": "replace",
                  "path": "/spec/template/spec/containers/0/resources/requests/cpu",
                  "value": "50m"
                }, {
                  "op": "replace", 
                  "path": "/spec/template/spec/containers/0/resources/requests/memory",
                  "value": "128Mi"
                }]' 2>/dev/null && success "Reduced resources for $deployment" || warning "Could not patch resources for $deployment"
            fi
        fi
    done
}

# Fix image pull issues
fix_image_pull_issues() {
    log "Fixing image pull issues..."
    
    local image_pull_pods=$(kubectl get pods --all-namespaces | grep -E "(ImagePullBackOff|ErrImagePull)" | awk '{print $2 " " $1}')
    
    if [ -z "$image_pull_pods" ]; then
        success "No image pull issues found"
        return 0
    fi
    
    echo "$image_pull_pods" | while read pod namespace; do
        log "Fixing image pull for pod $pod in namespace $namespace"
        
        # Get current image
        local image=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.spec.containers[0].image}')
        log "Current image: $image"
        
        # Try common fixes
        local deployment=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.metadata.labels.app}')
        
        if [ -n "$deployment" ]; then
            # Try adding imagePullPolicy: Always
            kubectl patch deployment "$deployment" -n "$namespace" --type='merge' -p '{
              "spec": {
                "template": {
                  "spec": {
                    "containers": [
                      {
                        "name": "'$(kubectl get deployment "$deployment" -n "$namespace" -o jsonpath='{.spec.template.spec.containers[0].name}')'",
                        "imagePullPolicy": "IfNotPresent"
                      }
                    ]
                  }
                }
              }
            }' 2>/dev/null && success "Updated pull policy for $deployment"
            
            # If it's a Python image, try the slim variant
            if [[ "$image" == *"python"* ]] && [[ "$image" != *"slim"* ]]; then
                local new_image="${image%-*}-slim"
                log "Trying slim variant: $new_image"
                
                kubectl patch deployment "$deployment" -n "$namespace" --type='json' -p '[{
                  "op": "replace",
                  "path": "/spec/template/spec/containers/0/image",
                  "value": "'$new_image'"
                }]' 2>/dev/null && success "Updated to slim image for $deployment"
            fi
        fi
    done
}

# Fix service endpoint issues
fix_service_endpoints() {
    log "Fixing service endpoint issues..."
    
    # Find services without endpoints
    local services_without_endpoints=$(kubectl get endpoints --all-namespaces -o json | jq -r '.items[] | select(.subsets == null) | "\(.metadata.name) \(.metadata.namespace)"' 2>/dev/null || echo "")
    
    if [ -z "$services_without_endpoints" ]; then
        success "All services have endpoints"
        return 0
    fi
    
    echo "$services_without_endpoints" | while read service namespace; do
        log "Fixing service $service in namespace $namespace"
        
        # Check if deployment exists and is ready
        local deployment_ready=$(kubectl get deployment "$service" -n "$namespace" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        
        if [ "$deployment_ready" = "0" ]; then
            warning "Deployment $service has 0 ready replicas, attempting restart..."
            kubectl rollout restart deployment/"$service" -n "$namespace" 2>/dev/null || warning "Could not restart $service deployment"
        fi
        
        # Check service selector matches deployment labels
        local service_selector=$(kubectl get service "$service" -n "$namespace" -o jsonpath='{.spec.selector}' 2>/dev/null)
        local pod_labels=$(kubectl get pods -n "$namespace" -l app="$service" --show-labels 2>/dev/null | tail -1 | awk '{print $6}' || echo "")
        
        if [ -n "$pod_labels" ] && ! echo "$pod_labels" | grep -q "app=$service"; then
            log "Service selector might not match pod labels, checking..."
            # This would require more complex logic to automatically fix
            warning "Manual intervention may be needed for service $service"
        fi
    done
}

# Fix NATS cluster issues
fix_nats_cluster() {
    log "Fixing NATS cluster issues..."
    
    # Check NATS pod status
    local nats_pods_ready=$(kubectl get pods -n event-driven -l app=nats | grep Running | wc -l)
    local nats_pods_total=$(kubectl get pods -n event-driven -l app=nats | tail -n +2 | wc -l)
    
    if [ "$nats_pods_ready" -lt 1 ]; then
        warning "NATS cluster not healthy ($nats_pods_ready/$nats_pods_total ready), restarting..."
        
        # Restart NATS StatefulSet
        kubectl rollout restart statefulset/nats -n event-driven 2>/dev/null || {
            warning "Could not restart NATS StatefulSet, trying to recreate..."
            kubectl delete statefulset nats -n event-driven --cascade=false 2>/dev/null || true
            sleep 5
            kubectl apply -f /Volumes/dev/homelab/event-driven/nats-cloudevents.yaml
        }
    else
        success "NATS cluster appears healthy ($nats_pods_ready/$nats_pods_total ready)"
    fi
}

# Fix storage issues
fix_storage_issues() {
    log "Fixing storage issues..."
    
    # Check for pending PVCs
    local pending_pvcs=$(kubectl get pvc --all-namespaces | grep Pending | wc -l)
    
    if [ "$pending_pvcs" -gt 0 ]; then
        warning "Found $pending_pvcs pending PVCs"
        
        # Check if we have a default storage class
        local default_sc=$(kubectl get storageclass | grep "(default)" | awk '{print $1}' || echo "")
        
        if [ -z "$default_sc" ]; then
            warning "No default storage class found, creating a simple one..."
            
            cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: homelab-local-storage
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
EOF
            success "Created default storage class"
        else
            success "Default storage class exists: $default_sc"
        fi
    else
        success "No pending PVCs found"
    fi
}

# Fix resource constraints
fix_resource_constraints() {
    log "Checking and fixing resource constraints..."
    
    # Get nodes with high resource usage
    if kubectl top nodes >/dev/null 2>&1; then
        kubectl top nodes | tail -n +2 | while read line; do
            local node=$(echo "$line" | awk '{print $1}')
            local cpu_percent=$(echo "$line" | awk '{print $3}' | tr -d '%')
            local memory_percent=$(echo "$line" | awk '{print $5}' | tr -d '%')
            
            if [ "$cpu_percent" -gt 80 ] 2>/dev/null; then
                warning "Node $node has high CPU usage: ${cpu_percent}%"
                
                # Find pods with high CPU on this node and reduce their limits
                kubectl get pods --all-namespaces -o wide | grep "$node" | while read namespace pod_name rest; do
                    local deployment=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.metadata.labels.app}' 2>/dev/null || echo "")
                    
                    if [ -n "$deployment" ]; then
                        log "Reducing CPU limits for deployment $deployment on high-usage node $node"
                        kubectl patch deployment "$deployment" -n "$namespace" --type='merge' -p '{
                          "spec": {
                            "template": {
                              "spec": {
                                "containers": [
                                  {
                                    "name": "'$(kubectl get deployment "$deployment" -n "$namespace" -o jsonpath='{.spec.template.spec.containers[0].name}' 2>/dev/null)'",
                                    "resources": {
                                      "limits": {
                                        "cpu": "200m"
                                      }
                                    }
                                  }
                                ]
                              }
                            }
                          }
                        }' 2>/dev/null || true
                    fi
                done
            fi
            
            if [ "$memory_percent" -gt 80 ] 2>/dev/null; then
                warning "Node $node has high memory usage: ${memory_percent}%"
            fi
        done
    else
        warning "Cannot check resource usage - metrics server not available"
    fi
}

# Main function
main() {
    log "🔧 Starting automatic issue fixes for homelab system"
    log "================================================"
    
    case "${1:-all}" in
        "pods")
            fix_pending_pods
            ;;
        "images")
            fix_image_pull_issues
            ;;
        "services")
            fix_service_endpoints
            ;;
        "nats")
            fix_nats_cluster
            ;;
        "storage")
            fix_storage_issues
            ;;
        "resources")
            fix_resource_constraints
            ;;
        "all")
            fix_pending_pods
            fix_image_pull_issues
            fix_service_endpoints
            fix_nats_cluster
            fix_storage_issues
            fix_resource_constraints
            ;;
        *)
            echo "Usage: $0 [pods|images|services|nats|storage|resources|all]"
            echo ""
            echo "Commands:"
            echo "  pods      - Fix pending pods and scheduling issues"
            echo "  images    - Fix image pull problems"
            echo "  services  - Fix service endpoint issues" 
            echo "  nats      - Fix NATS cluster issues"
            echo "  storage   - Fix storage and PVC issues"
            echo "  resources - Fix resource constraint issues"
            echo "  all       - Run all fixes (default)"
            exit 1
            ;;
    esac
    
    success "🎉 Automatic fixes completed!"
    log "Run './setup/test-system.sh test' to verify fixes"
}

main "$@"