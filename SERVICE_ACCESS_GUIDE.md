# Homelab Services - Access Guide

## Access Information

| Access Type | Domain Pattern | Notes |
|-------------|----------------|-------|
| **Local (LAN)** | `*.homelab.lan` | Via Traefik ingress at 192.168.0.204 |
| **External** | `*.mackie.house` | Via Cloudflare Tunnel (secure, no port forwarding) |

**Cluster IP:** 192.168.0.204 (labnuc)

---

## Media Services

| Service | Local URL | External URL | Port | Purpose |
|---------|-----------|--------------|------|---------|
| Jellyfin | jellyfin.homelab.lan | jellyfin.mackie.house | 8096 | Media streaming |
| Radarr | radarr.homelab.lan | radarr.mackie.house | 7878 | Movie management |
| Sonarr | sonarr.homelab.lan | sonarr.mackie.house | 8989 | TV show management |
| Lidarr | lidarr.homelab.lan | lidarr.mackie.house | 8686 | Music management |
| Prowlarr | prowlarr.homelab.lan | prowlarr.mackie.house | 9696 | Indexer manager |
| Bazarr | bazarr.homelab.lan | bazarr.mackie.house | 6767 | Subtitle downloads |
| SABnzbd | sabnzbd.homelab.lan | sabnzbd.mackie.house | 8080 | Usenet downloader |
| qBittorrent | qbittorrent.homelab.lan | qbittorrent.mackie.house | 8080 | Torrent client |
| Jackett | jackett.homelab.lan | jackett.mackie.house | 9117 | Torrent indexer proxy |
| Overseerr | overseerr.homelab.lan | overseerr.mackie.house | 5055 | Media requests |
| Tautulli | tautulli.homelab.lan | tautulli.mackie.house | 8181 | Jellyfin analytics |

## Smart Home

| Service | Local URL | External URL | Port | Purpose |
|---------|-----------|--------------|------|---------|
| Home Assistant | homeassistant.homelab.lan | homeassistant.mackie.house | 8123 | Smart home hub |
| Node-RED | nodered.homelab.lan | nodered.mackie.house | 1880 | Flow automation |
| ESPHome | esphome.homelab.lan | esphome.mackie.house | 6052 | ESP device management |
| Zigbee2MQTT | zigbee.homelab.lan | zigbee.mackie.house | 8080 | Zigbee bridge |

## Infrastructure & Management

| Service | Local URL | External URL | Port | Purpose |
|---------|-----------|--------------|------|---------|
| Homer | homer.homelab.lan | homelab.mackie.house | 8080 | Dashboard |
| Portainer | portainer.homelab.lan | portainer.mackie.house | 9000 | Container management |
| Pi-hole | pihole.homelab.lan | - | 80/53 | DNS & ad blocking |
| Uptime Kuma | uptime.homelab.lan | uptime.mackie.house | 3001 | Uptime monitoring |
| Vaultwarden | vaultwarden.homelab.lan | vaultwarden.mackie.house | 80 | Password manager |
| Speedtest | speedtest.homelab.lan | speedtest.mackie.house | 80 | Speed monitoring |
| Nginx Proxy Manager | http://192.168.0.204:81 | - | 81 | Reverse proxy admin |

## Storage Services

| Service | Local URL | External URL | Port | Purpose |
|---------|-----------|--------------|------|---------|
| Nextcloud | nextcloud.homelab.lan | nextcloud.mackie.house | 80 | Cloud storage |
| MinIO Console | minio.homelab.lan | minio.mackie.house | 9001 | S3 storage UI |
| MinIO API | minio-api.homelab.lan | - | 9000 | S3 API |
| FileBrowser | filebrowser.homelab.lan | filebrowser.mackie.house | 80 | File management |

## Monitoring

| Service | Local URL | External URL | Port | Purpose |
|---------|-----------|--------------|------|---------|
| Grafana | grafana.homelab.lan | grafana.mackie.house | 3000 | Dashboards |
| Longhorn UI | longhorn.homelab.lan | - | 80 | Storage management |

---

## DNS Configuration

### Option 1: Pi-hole (Recommended)
Add local DNS record in Pi-hole:
```
*.homelab.lan → 192.168.0.204
```

### Option 2: Router DNS
Configure your router to resolve `*.homelab.lan` to `192.168.0.204`

### Option 3: /etc/hosts
```bash
# Add to /etc/hosts
192.168.0.204 jellyfin.homelab.lan radarr.homelab.lan sonarr.homelab.lan
192.168.0.204 homeassistant.homelab.lan homer.homelab.lan portainer.homelab.lan
```

---

## Cloudflare Tunnel

**Status:** Active
**Tunnel ID:** a0b1dc34-d66b-4e48-809e-186bd6dc9838

Configured routes:
- `homelab.mackie.house` → Homer dashboard
- `jellyfin.mackie.house` → Jellyfin
- `homeassistant.mackie.house` → Home Assistant
- `grafana.mackie.house` → Grafana
- `*.mackie.house` → Nginx Proxy Manager (for other services)

---

## Storage Overview

### NFS Storage (from NAS at 192.168.0.250)
| Volume | Size | Path | Used By |
|--------|------|------|---------|
| Movies | 5 TiB | /share/homelab/movies | Radarr, Jellyfin |
| TV | 3 TiB | /share/homelab/tv | Sonarr, Jellyfin |
| Music | 2 TiB | /share/homelab/music | Lidarr, Jellyfin |
| Downloads | 1 TiB | /share/homelab/downloads | SABnzbd, qBittorrent |
| Media General | 500 GiB | /share/homelab/media-general | Shared media |
| Shared | 2 TiB | /share/homelab/shared | Cross-service sharing |

### Local Storage (K3s local-path)
Used for: Config files, databases, application state

---

## Quick Commands

```bash
# Check all pods
kubectl get pods --all-namespaces

# Check problem pods only
kubectl get pods -A | grep -v "Running\|Completed"

# View logs
kubectl logs -n media deployment/jellyfin
kubectl logs -n smart-home deployment/home-assistant

# Restart a service
kubectl rollout restart deployment/jellyfin -n media

# Check resource usage
kubectl top pods -n media
```

---

*Last Updated: 2026-02-03*
