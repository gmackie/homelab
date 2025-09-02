# Multi-Architecture Homelab Setup Guide

Complete guide for setting up a heterogeneous ARM64 + AMD64 k3s cluster with intelligent workload placement.

## 🏗️ Architecture Overview

Your homelab will consist of:

### **2U Rack 1: Control Plane + Compute**
- **NUC (AMD64)**: Master node, databases, heavy compute
- **Power**: ~45W
- **Role**: Control plane, storage, compute workloads

### **2U Rack 2: Edge + IoT**
- **2x Raspberry Pi 4/5 (ARM64)**: Worker nodes for lightweight services
- **2x Pi Zero (ARM)**: Sensors, monitoring, edge functions
- **Power**: ~14-20W total
- **Role**: Edge services, IoT, power-efficient workloads

### **Network**
- **PoE Switch**: Powers ARM nodes via PoE HATs
- **PDU**: Power management for AMD64 nodes
- **Dashboard**: 1024x600 touchscreen showing multi-arch metrics

## 🚀 Quick Setup

### 1. Prepare Nodes

**On all nodes (run as root):**
```bash
# Clone this repository
git clone <your-repo> /opt/homelab
cd /opt/homelab

# Run the multi-arch setup script
chmod +x k3s/setup-multi-arch-cluster.sh
```

**On NUC (AMD64 Master):**
```bash
./k3s/setup-multi-arch-cluster.sh 192.168.1.100  # Use your NUC IP
```

**On each Raspberry Pi:**
```bash
# Get the token from the master node output
K3S_URL=https://192.168.1.100:6443 K3S_TOKEN=<token-from-master> ./k3s/setup-multi-arch-cluster.sh
```

### 2. Deploy Services

**From the master node:**
```bash
chmod +x deploy-multi-arch-services.sh
./deploy-multi-arch-services.sh
```

### 3. Access Dashboard

The dashboard will show:
- 🖥️ **AMD64 Badge**: Blue, showing compute role and ~45W power
- 🥧 **ARM64 Badge**: Green, showing edge role and ~7W power  
- 📱 **ARM Badge**: Purple, showing sensor role and ~3W power

## 📋 Service Placement Strategy

### **AMD64 Nodes (NUCs)**
```yaml
# Heavy workloads that need performance
nodeSelector:
  kubernetes.io/arch: amd64
  node-role/compute: "true"

# Examples:
- PostgreSQL/MySQL databases
- Plex/Jellyfin media servers  
- GitLab/Jenkins CI/CD
- Prometheus (large datasets)
- File servers (NFS/SMB)
```

### **ARM64 Nodes (Pi 4/5)**
```yaml
# Lightweight services optimized for power efficiency
nodeSelector:
  kubernetes.io/arch: arm64
  node-role/edge: "true"

# Examples:
- Nginx/Traefik ingress controllers
- PiHole DNS servers
- MQTT brokers
- Home Assistant
- Grafana dashboards
- Redis caches
```

### **ARM Nodes (Pi Zero)**
```yaml
# Minimal workloads and sensors
nodeSelector:
  kubernetes.io/arch: arm
  node-role/sensor: "true"

# Examples:
- Temperature/humidity sensors
- Network monitoring probes
- Backup DNS servers
- Status indicators
- IoT data collectors
```

## 🔧 Architecture-Specific Optimizations

### **Multi-Arch Image Building**

For custom applications:
```bash
# Build for multiple architectures
docker buildx create --name multi-arch-builder --use
docker buildx build \
  --platform linux/amd64,linux/arm64,linux/arm/v7 \
  --tag your-app:latest \
  --push .
```

### **Deployment Strategies**

**1. Force Specific Architecture:**
```yaml
spec:
  nodeSelector:
    kubernetes.io/arch: amd64  # Only runs on AMD64
```

**2. Prefer Architecture with Fallback:**
```yaml
spec:
  affinity:
    nodeAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        preference:
          matchExpressions:
          - key: kubernetes.io/arch
            operator: In
            values: ["arm64"]  # Prefer ARM64, but can run elsewhere
```

**3. Spread Across Architectures:**
```yaml
spec:
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          topologyKey: kubernetes.io/arch  # Spread across architectures
```

## 📊 Dashboard Features

Your updated dashboard now displays:

### **Architecture Badge**
- **Icon**: 🖥️ (AMD64), 🥧 (ARM64), 📱 (ARM)
- **Color Coding**: Blue (AMD64), Green (ARM64), Purple (ARM)
- **Power Info**: Real-time wattage estimates
- **Efficiency Rating**: Ultra-high, High, Medium
- **Node Role**: Master, Edge, Sensor

### **Multi-Arch Indicators**
- **MULTI-ARCH Badge**: Shows when cluster has mixed architectures
- **Power Consumption**: Live estimates per architecture
- **Workload Distribution**: Visual representation of service placement

### **Kubernetes Integration**
- **Node Labels**: Shows k8s role and capabilities
- **Architecture Detection**: Automatic ARM/AMD64 identification
- **Cluster Status**: Multi-arch cluster health

## ⚡ Power Management

### **Power Consumption Estimates**
- **AMD64 (NUC)**: ~45W per node
- **ARM64 (Pi 4/5)**: ~7W per node
- **ARM (Pi Zero)**: ~2.5W per node

### **Total Cluster Power**
```bash
# Your 6-node setup:
1x NUC:     45W
2x Pi 4/5:  14W  
2x Pi Zero: 5W
+ Network:  15W
-----------------
Total:      ~79W
```

### **Power Efficiency Tips**
1. **Schedule lightweight workloads on ARM nodes**
2. **Use PoE for Pi power management**
3. **Monitor power via dashboard**
4. **Scale down unused AMD64 workloads**

## 🔍 Monitoring & Alerts

### **Architecture-Specific Alerts**
- **High CPU on ARM64**: Alert when ARM nodes exceed 80% CPU
- **Memory pressure on AMD64**: Alert when compute nodes exceed 90% memory
- **Power consumption spikes**: Monitor total cluster power usage
- **Cross-architecture failures**: Alert when services can't schedule

### **Prometheus Queries**
```promql
# CPU usage by architecture
avg by (architecture) (100 - (avg(irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100))

# Memory usage by node role
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100

# Power consumption estimate by architecture
sum by (architecture) (node_power_estimate)
```

## 🛠️ Troubleshooting

### **Common Issues**

**1. Image Architecture Mismatch**
```bash
# Error: exec format error
# Solution: Use multi-arch images
docker manifest inspect nginx:latest  # Check available architectures
```

**2. Pod Stuck Pending**
```bash
# Check node selector conflicts
kubectl describe pod <pod-name>
# Look for: "node(s) didn't match Pod's node affinity/selector"
```

**3. ARM Node Performance Issues**
```bash
# Check if workload is too heavy for ARM
kubectl top nodes
# Move heavy workloads to AMD64 nodes
```

### **Useful Commands**

```bash
# View nodes by architecture
kubectl get nodes -L kubernetes.io/arch,node-role.kubernetes.io/master

# Check pod distribution by architecture
kubectl get pods -o wide --all-namespaces | grep -E "(amd64|arm64|arm)"

# View node resources
kubectl describe node <node-name>

# Check multi-arch image availability
docker manifest inspect <image-name>
```

## 🎯 Best Practices

### **1. Workload Placement**
- **Databases**: Always on AMD64 for performance
- **Web servers**: Prefer ARM64 for power efficiency
- **Monitoring**: Can run on any architecture
- **CI/CD**: AMD64 for build performance
- **IoT services**: ARM nodes for edge computing

### **2. Resource Management**
```yaml
# Set appropriate resources for each architecture
resources:
  requests:
    # ARM nodes - conservative
    memory: "64Mi"
    cpu: "50m"
  limits:
    # Prevent ARM nodes from being overwhelmed
    memory: "256Mi"
    cpu: "500m"
```

### **3. High Availability**
- **Spread critical services across architectures**
- **Use multiple replicas with anti-affinity**
- **Keep ARM64 nodes as backup for essential services**

### **4. Development Workflow**
1. **Build multi-arch images from the start**
2. **Test on both architectures**
3. **Use architecture labels in manifests**
4. **Monitor resource usage per architecture**

## 🚀 Next Steps

1. **Scale Services**: Add more services using architecture affinity
2. **Optimize Power**: Fine-tune service placement for efficiency
3. **Add Monitoring**: Set up architecture-specific dashboards
4. **Implement GitOps**: Use ArgoCD with multi-arch manifests
5. **Edge Computing**: Leverage ARM nodes for IoT workloads

Your multi-architecture homelab is now ready to efficiently handle diverse workloads while providing excellent power efficiency and redundancy! 🎉