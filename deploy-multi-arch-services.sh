#!/bin/bash

set -e

echo "🚀 Deploying Multi-Architecture Services to k3s Cluster"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check cluster connectivity
log "Checking cluster connectivity..."
if ! kubectl cluster-info &> /dev/null; then
    error "Cannot connect to Kubernetes cluster"
    exit 1
fi

# Create namespaces
log "Creating namespaces..."
kubectl create namespace web --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace database --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace iot --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace dns --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace dashboard --dry-run=client -o yaml | kubectl apply -f -

# Label nodes with architecture information
log "Labeling nodes..."

# Get all nodes and their architectures
nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
for node in $nodes; do
    arch=$(kubectl get node $node -o jsonpath='{.metadata.labels.kubernetes\.io/arch}')
    
    log "Node: $node (Architecture: $arch)"
    
    # Label based on architecture
    if [ "$arch" = "amd64" ]; then
        kubectl label node $node node-role/compute=true --overwrite
        kubectl label node $node node-role/storage=true --overwrite
        kubectl label node $node workload/heavy=true --overwrite
        kubectl label node $node power-class=high --overwrite
        log "  ✅ Labeled as compute/storage node"
    elif [ "$arch" = "arm64" ]; then
        kubectl label node $node node-role/edge=true --overwrite
        kubectl label node $node node-role/iot=true --overwrite
        kubectl label node $node workload/light=true --overwrite
        kubectl label node $node power-class=low --overwrite
        kubectl label node $node power-efficiency=high --overwrite
        log "  ✅ Labeled as edge/IoT node"
    elif [ "$arch" = "arm" ]; then
        kubectl label node $node node-role/sensor=true --overwrite
        kubectl label node $node workload/minimal=true --overwrite
        kubectl label node $node power-class=ultra-low --overwrite
        log "  ✅ Labeled as sensor node"
    fi
done

# Create secrets
log "Creating secrets..."

# PostgreSQL secret
kubectl create secret generic postgres-secret \
    --from-literal=password="$(openssl rand -base64 32)" \
    --namespace=database \
    --dry-run=client -o yaml | kubectl apply -f -

# PiHole secret
kubectl create secret generic pihole-secret \
    --from-literal=password="$(openssl rand -base64 16)" \
    --namespace=dns \
    --dry-run=client -o yaml | kubectl apply -f -

# Apply multi-arch deployments
log "Applying architecture-aware deployments..."
kubectl apply -f k8s/architecture-aware-deployments.yaml

# Create storage classes and PVs for AMD64 nodes
log "Setting up storage for AMD64 nodes..."
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-ssd
provisioner: rancher.io/local-path
parameters:
  nodePath: /var/lib/rancher/k3s/storage
allowedTopologies:
- matchLabelExpressions:
  - key: kubernetes.io/arch
    values:
    - amd64
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-arm-storage
provisioner: rancher.io/local-path
parameters:
  nodePath: /var/lib/rancher/k3s/storage
allowedTopologies:
- matchLabelExpressions:
  - key: kubernetes.io/arch
    values:
    - arm64
    - arm
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
EOF

# Deploy MetalLB for LoadBalancer services
log "Setting up MetalLB LoadBalancer..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml

# Wait for MetalLB to be ready
log "Waiting for MetalLB to be ready..."
kubectl wait --namespace metallb-system \
    --for=condition=ready pod \
    --selector=app=metallb \
    --timeout=300s

# Configure MetalLB IP pool (adjust IP range for your network)
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: homelab-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.1.200-192.168.1.220  # Adjust for your network
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: homelab-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
  - homelab-pool
EOF

# Build and push dashboard API image (multi-arch)
log "Building multi-architecture dashboard API image..."
cd apps/dashboard/api

# Create multi-arch Dockerfile if it doesn't exist
cat > Dockerfile.multiarch << 'EOF'
FROM --platform=$BUILDPLATFORM golang:1.21-alpine AS builder
ARG TARGETPLATFORM
ARG BUILDPLATFORM
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH:-amd64} go build -o dashboard-api cmd/server/main.go

FROM --platform=$TARGETPLATFORM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /app/dashboard-api .
EXPOSE 8080
CMD ["./dashboard-api"]
EOF

# Build for multiple architectures
if command -v docker &> /dev/null && docker buildx version &> /dev/null; then
    log "Building multi-arch image with Docker Buildx..."
    
    # Create buildx builder if it doesn't exist
    docker buildx create --name homelab-builder --use 2>/dev/null || docker buildx use homelab-builder
    
    # Build and push (or load locally)
    docker buildx build \
        --platform linux/amd64,linux/arm64,linux/arm/v7 \
        --tag homelab/dashboard-api:latest \
        --file Dockerfile.multiarch \
        --load \
        .
else
    warn "Docker Buildx not available, building for current architecture only"
    docker build -t homelab/dashboard-api:latest -f Dockerfile.multiarch .
fi

cd ../../../

# Deploy dashboard
log "Deploying dashboard..."
kubectl apply -f apps/dashboard/k8s/

# Create Prometheus monitoring configuration
log "Setting up monitoring..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: monitoring
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s

    rule_files:
      - "alert_rules.yml"

    scrape_configs:
    - job_name: 'prometheus'
      static_configs:
      - targets: ['localhost:9090']

    - job_name: 'node-exporter'
      kubernetes_sd_configs:
      - role: node
      relabel_configs:
      - source_labels: [__address__]
        regex: '(.*):10250'
        target_label: __address__
        replacement: '\${1}:9100'
      - source_labels: [__meta_kubernetes_node_label_kubernetes_io_arch]
        target_label: architecture
      - source_labels: [__meta_kubernetes_node_label_node_role_compute]
        target_label: node_role_compute
      - source_labels: [__meta_kubernetes_node_label_node_role_edge]
        target_label: node_role_edge

    - job_name: 'kubernetes-pods'
      kubernetes_sd_configs:
      - role: pod
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: \$1:\$2
        target_label: __address__
      - action: labelmap
        regex: __meta_kubernetes_pod_label_(.+)
      - source_labels: [__meta_kubernetes_namespace]
        action: replace
        target_label: kubernetes_namespace
      - source_labels: [__meta_kubernetes_pod_name]
        action: replace
        target_label: kubernetes_pod_name
      - source_labels: [__meta_kubernetes_pod_node_name]
        action: replace
        target_label: kubernetes_node
  
  alert_rules.yml: |
    groups:
    - name: architecture_alerts
      rules:
      - alert: HighCPUOnARM
        expr: (100 - (avg(irate(node_cpu_seconds_total{mode="idle",architecture="arm64"}[5m])) * 100)) > 80
        for: 5m
        labels:
          severity: warning
          architecture: arm64
        annotations:
          summary: "High CPU usage on ARM64 node"
          description: "ARM64 node {{ \$labels.kubernetes_node }} has CPU usage above 80%"

      - alert: HighMemoryOnAMD64
        expr: (node_memory_MemTotal_bytes{architecture="amd64"} - node_memory_MemAvailable_bytes{architecture="amd64"}) / node_memory_MemTotal_bytes{architecture="amd64"} > 0.9
        for: 5m
        labels:
          severity: critical
          architecture: amd64
        annotations:
          summary: "High memory usage on AMD64 node"
          description: "AMD64 node {{ \$labels.kubernetes_node }} has memory usage above 90%"
EOF

# Wait for deployments to be ready
log "Waiting for deployments to be ready..."

# Check each deployment
deployments=("nginx-multi-arch" "postgres" "prometheus")
namespaces=("web" "database" "monitoring")

for i in "${!deployments[@]}"; do
    deployment="${deployments[$i]}"
    namespace="${namespaces[$i]}"
    
    log "Waiting for $deployment in namespace $namespace..."
    kubectl wait --for=condition=available deployment/$deployment -n $namespace --timeout=300s
done

# Display cluster information
log "🎉 Multi-architecture cluster deployment complete!"
echo ""
log "Cluster Information:"
echo "===================="

kubectl get nodes -o custom-columns="NAME:.metadata.name,ARCH:.metadata.labels.kubernetes\.io/arch,ROLE:.metadata.labels.node-role/compute,POWER:.metadata.labels.power-class" --no-headers | while read line; do
    echo "  $line"
done

echo ""
log "Services:"
kubectl get services --all-namespaces -o wide | grep -v "kubernetes\|kube-"

echo ""
log "Dashboard Access:"
dashboard_service=$(kubectl get service -n dashboard homelab-dashboard -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
if [ "$dashboard_service" != "pending" ]; then
    echo "  🎨 Dashboard UI: http://$dashboard_service"
else
    node_port=$(kubectl get service -n dashboard homelab-dashboard-nodeport -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "30080")
    node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    echo "  🎨 Dashboard UI: http://$node_ip:$node_port"
fi

echo ""
log "Power Consumption Estimate:"
amd64_nodes=$(kubectl get nodes -l kubernetes.io/arch=amd64 --no-headers | wc -l)
arm64_nodes=$(kubectl get nodes -l kubernetes.io/arch=arm64 --no-headers | wc -l)
arm_nodes=$(kubectl get nodes -l kubernetes.io/arch=arm --no-headers | wc -l)

total_power=$((amd64_nodes * 45 + arm64_nodes * 7 + arm_nodes * 3))
echo "  ⚡ Estimated Total Power: ${total_power}W"
echo "    - AMD64 nodes ($amd64_nodes): $((amd64_nodes * 45))W"
echo "    - ARM64 nodes ($arm64_nodes): $((arm64_nodes * 7))W"
echo "    - ARM nodes ($arm_nodes): $((arm_nodes * 3))W"

echo ""
log "Next Steps:"
echo "1. Configure your network's IP range in MetalLB pool"
echo "2. Set up external DNS entries for services"  
echo "3. Configure monitoring alerts"
echo "4. Deploy additional workloads using architecture affinity"

warn "Don't forget to update your dashboard environment variables with the new API endpoints!"

log "✅ Multi-architecture homelab is ready!"