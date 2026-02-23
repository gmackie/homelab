# Homelab Deployment - Fixes Applied

## Session Date: 2025-11-16

## Critical Issues Resolved

### 1. DNS Resolution Failure ⚠️ **CRITICAL**
**Problem:**
- All pods experiencing `ImagePullBackOff` errors
- Error: `dial tcp: lookup registry-1.docker.io: Try again`
- Containerd unable to resolve DNS for image pulls
- 50+ pods failing to start

**Root Cause:**
- `/etc/resolv.conf` pointed to systemd-resolved stub resolver (127.0.0.53)
- Containerd unable to access stub resolver from its namespace
- DNS worked fine from within pods (using CoreDNS), but not for image pulls

**Solution Applied:**
```bash
# Created systemd-resolved configuration
sudo mkdir -p /etc/systemd/resolved.conf.d/
sudo tee /etc/systemd/resolved.conf.d/dns.conf << 'EOF'
[Resolve]
DNS=8.8.8.8 8.8.4.4 1.1.1.1
FallbackDNS=9.9.9.9
EOF

# Restarted services
sudo systemctl restart systemd-resolved
sudo systemctl restart k3s
```

**Result:**
- ✅ All 53 pods now running successfully
- ✅ Image pulls working correctly
- ✅ No more DNS errors

**Files Changed:**
- `/etc/systemd/resolved.conf.d/dns.conf` (created)

---

### 2. Zigbee2MQTT Read-Only Filesystem Error
**Problem:**
- Pod crashing with: `EROFS: read-only file system, open '/app/data/configuration.yaml'`
- ConfigMap mounted as subPath on top of PVC, preventing writes

**Root Cause:**
- ConfigMap file mounted directly at `/app/data/configuration.yaml`
- ConfigMaps are read-only
- Application couldn't write to configuration file for migrations

**Solution Applied:**
- Modified deployment to use initContainer
- InitContainer copies ConfigMap to writable PVC on first run
- Main container now has writable configuration file

**Files Changed:**
- `/home/mackieg/dev/homelab/smart-home/home-assistant.yaml`
  - Lines 516-530: Added initContainer
  - Lines 540-542: Removed ConfigMap subPath mount from main container

**Result:**
- ✅ Zigbee2MQTT pod running successfully
- ✅ Configuration file writable
- ✅ Migrations completed successfully

---

### 3. Port Conflict - Nginx Proxy Manager vs Pi-hole
**Problem:**
- Nginx Proxy Manager LoadBalancer stuck in Pending state
- Error: `0/1 nodes are available: 1 node(s) didn't have free ports for the requested pod ports`
- Both services trying to bind to port 80 on same node IP

**Root Cause:**
- Pi-hole LoadBalancer service bound to port 80 first
- Nginx Proxy Manager LoadBalancer couldn't bind to same port
- Single node cluster = single IP for LoadBalancer services

**Solution Applied:**
```bash
# Changed Pi-hole from LoadBalancer to NodePort
kubectl patch service pihole -n homelab-services -p '{"spec":{"type":"NodePort"}}'
```

**Result:**
- ✅ Nginx Proxy Manager now has port 80 and 443
- ✅ Pi-hole accessible via NodePort
- ✅ All LoadBalancer services operational

---

### 4. Cloudflared Configuration Issue
**Problem:**
- Two cloudflared pods in `CreateContainerConfigError`
- Missing secret: `cloudflared-token`

**Solution Applied:**
- Scaled deployment to 0 replicas (requires user configuration)
```bash
kubectl scale deployment cloudflared -n homelab-services --replicas=0
```

**To Enable:**
```bash
# User needs to create secret with their Cloudflare tunnel token
kubectl create secret generic cloudflared-token \
  --from-literal=token=YOUR_TOKEN \
  -n homelab-services

# Then scale back up
kubectl scale deployment cloudflared -n homelab-services --replicas=2
```

**Result:**
- ✅ No failed pods
- ⏸️ Cloudflared disabled until user configures tunnel

---

## Additional Improvements

### CoreDNS Configuration
**Change:** Updated CoreDNS to use public DNS servers directly
```yaml
forward . 8.8.8.8 8.8.4.4 1.1.1.1
```
Previously: `forward . /etc/resolv.conf` (which pointed to 127.0.0.53)

**Files Changed:**
- CoreDNS ConfigMap in kube-system namespace

---

## Final Cluster Status

### Pods
- ✅ **53 Running**
- ✅ **3 Completed** (jobs)
- ✅ **0 Failed**

### Services
- All services operational
- LoadBalancer services properly assigned
- Ingresses configured (require Nginx Proxy Manager setup)

### Storage
- All 38 PVCs bound successfully
- NFS server operational
- Longhorn storage healthy

### Resources
- CPU: ~1% usage (244m cores)
- Memory: ~16% usage (4.6 GiB / 29 GiB)
- Node: Healthy (Ready state)

---

## Post-Deployment Tasks

### Required
1. **Configure Nginx Proxy Manager**
   - Access: http://192.168.0.208:81
   - Add proxy hosts for *.labnuc.local domains

2. **Configure DNS**
   - Add *.labnuc.local → 192.168.0.208 to router/DNS
   - Or add individual entries to /etc/hosts

### Optional
1. **Cloudflare Tunnel** (for external access)
   - Create tunnel in Cloudflare dashboard
   - Add secret to Kubernetes
   - Scale up cloudflared deployment

2. **Zigbee2MQTT USB Device**
   - Verify Zigbee adapter at /dev/ttyUSB0
   - May need to add device mapping to deployment

3. **Ingress Controller**
   - Consider installing nginx-ingress or Traefik
   - Currently ingresses require manual Nginx Proxy Manager configuration

---

## Technical Notes

### DNS Resolution Path
1. **Pod DNS**: Pods → CoreDNS → 8.8.8.8/8.8.4.4/1.1.1.1 ✅
2. **Host DNS**: Host → systemd-resolved → 8.8.8.8/8.8.4.4/1.1.1.1 ✅
3. **Containerd DNS**: Uses host's resolv.conf → systemd-resolved → upstream ✅

### Storage Architecture
- **Local-Path**: Config files, databases (26 PVCs)
- **NFS**: Large media files, shared storage (8 PVCs)
- **Longhorn**: Distributed block storage (installed, available)

### Networking
- **Pod Network**: Flannel (VXLAN)
- **Service Network**: kube-proxy (iptables mode)
- **LoadBalancer**: klipper-lb (K3s built-in)
- **Ingress**: Manual via Nginx Proxy Manager

---

## Files Modified

1. `/etc/systemd/resolved.conf.d/dns.conf` - Created
2. `/home/mackieg/dev/homelab/smart-home/home-assistant.yaml` - Modified (zigbee2mqtt)
3. CoreDNS ConfigMap - Modified (DNS forwarders)
4. Pi-hole Service - Modified (LoadBalancer → NodePort)

## Files Created

1. `/home/mackieg/dev/homelab/SERVICE_ACCESS_GUIDE.md`
2. `/home/mackieg/dev/homelab/FIXES_APPLIED.md` (this file)

---

## Maintenance Recommendations

### Regular Checks
```bash
# Check pod health
kubectl get pods --all-namespaces | grep -v Running | grep -v Completed

# Check resource usage
kubectl top node
kubectl top pods --all-namespaces

# Check storage
kubectl get pvc --all-namespaces | grep -v Bound
```

### Backup Important Data
- Vaultwarden data (password vault)
- Home Assistant configuration
- Nextcloud data
- Media library metadata (*arr configs)

### Monitor
- DNS resolution (critical for image pulls)
- Storage capacity
- Node resources
- Service accessibility

---

*Session completed: 2025-11-16*
*All critical issues resolved ✅*
