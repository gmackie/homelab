# Homelab Observability Guide

## Overview

Complete observability stack with:
- **Prometheus**: Metrics collection
- **Loki**: Log aggregation  
- **Grafana**: Visualization
- **AlertManager**: Alert routing
- **Promtail**: Log shipping

## Architecture

```
Services → Metrics → Prometheus → Grafana
    ↓                                ↑
   Logs → Promtail → Loki ─────────┘
                         ↓
                   AlertManager → Notifications
```

## Deployment

```bash
cd apps/monitoring
./deploy-observability.sh
```

## Metrics Collection

### ServiceMonitors Configured

| Service | Metrics Endpoint | Key Metrics |
|---------|-----------------|-------------|
| Loki | :3100/metrics | Ingestion rate, query performance |
| Promtail | :9080/metrics | Logs shipped, errors |
| Authelia | :9091/api/health | Auth attempts, sessions |
| FreeIPA | :443/metrics | LDAP queries, Kerberos tickets |
| Longhorn | :9500/metrics | Volume health, disk usage |
| Traefik | :8080/metrics | Request rates, latencies |
| Jellyfin | :9090/metrics | Active streams, users |
| Home Assistant | :8123/api/prometheus | Entity states, automations |
| Pi-hole | :9617/metrics | DNS queries, blocked ads |
| Cert-manager | :9402/metrics | Certificate status |

### Custom Exporters

#### Jellyfin Exporter
```yaml
# Provides:
- jellyfin_users_total
- jellyfin_items_total  
- jellyfin_playback_sessions
- jellyfin_bandwidth_bytes
```

#### Exportarr (Sonarr/Radarr)
```yaml
# Provides:
- sonarr_queue_total
- sonarr_series_total
- sonarr_missing_episodes
- radarr_queue_total
- radarr_movies_total
```

## Log Collection

### Promtail Configuration

#### Service-Specific Parsing

**Authelia Logs**
```
level=(?P<level>\w+).*msg="(?P<message>[^"]+)"
```

**Jellyfin Logs**
```
\[(?P<timestamp>[^\]]+)\] \[(?P<level>\w+)\] (?P<message>.*)
```

**Sonarr/Radarr Logs**
```
\|(?P<level>\w+)\|(?P<component>[^\|]+)\|(?P<message>.*)
```

**Home Assistant Logs**
```
(?P<timestamp>\S+\s\S+)\s+(?P<level>\w+)\s+\((?P<component>[^\)]+)\)\s+(?P<message>.*)
```

### Log Labels

Every log entry includes:
- `namespace`: Kubernetes namespace
- `pod`: Pod name
- `container`: Container name
- `app`: Application name
- `level`: Log level (parsed)
- `component`: Component (where applicable)

## Grafana Dashboards

### 1. Homelab Overview
- CPU, Memory, Disk usage gauges
- Service availability status
- Error log stream
- Alert summary

### 2. Authentication & Security  
- Auth success/failure rates
- Active sessions
- Failed login attempts by user
- 2FA adoption rate

### 3. Media Stack
- Active streams count
- Download queue sizes
- Import success/failure
- Bandwidth usage
- Library growth

### 4. Storage & Volumes
- Volume usage by PVC
- Longhorn replica health
- Backup status
- Growth trends

### 5. Network & DNS
- DNS query rate
- Ads blocked percentage
- Service request rates
- Certificate expiration

### 6. Home Automation
- Entity availability
- Automation triggers
- State changes
- Integration health

## Alerting Rules

### Severity Levels

- **Critical**: Service down, data loss risk
- **Warning**: Performance degradation, high usage
- **Info**: Notable events, not actionable

### Alert Categories

#### Infrastructure
- Node down
- High CPU/Memory/Disk
- Network interface down

#### Kubernetes
- Pod crash looping
- Deployment replica mismatch
- PVC almost full

#### Authentication
- High failure rate
- Service down
- Unusual session count

#### Media Stack
- Service down
- Queue stalled
- Import failures

#### Storage
- Volume errors
- Low disk space
- Backup failures

#### Network
- DNS service down
- Certificate expiring
- Backend unreachable

## Query Examples

### Prometheus Queries

```promql
# Service availability
up{namespace="media"}

# Request rate by service
sum(rate(traefik_service_requests_total[5m])) by (service)

# Failed auth attempts last hour
increase(authelia_authentication_attempts_total{success="false"}[1h])

# Storage usage by namespace
sum(kubelet_volume_stats_used_bytes) by (namespace) / 1024 / 1024 / 1024

# Active Jellyfin streams
jellyfin_playback_sessions

# Download speed
rate(sabnzbd_downloaded_bytes[5m]) / 1024 / 1024
```

### Loki Queries

```logql
# All errors
{level=~"error|critical"}

# Auth failures
{app="authelia"} |~ "authentication.*failed"

# Media imports
{app=~"sonarr|radarr"} |~ "Imported|Downloaded"

# Slow requests
{app="traefik"} | json | duration > 1s

# Pod restarts
{namespace="media"} |~ "Back-off restarting"

# Home automation triggers
{app="home-assistant"} |~ "automation.*triggered"
```

## Performance Tuning

### Prometheus Retention
```yaml
retention: 30d  # Adjust based on disk space
scrapeInterval: 30s
evaluationInterval: 30s
```

### Loki Limits
```yaml
ingestion_rate_mb: 50
ingestion_burst_size_mb: 100
max_query_series: 5000
max_query_parallelism: 32
```

### Grafana Caching
```ini
[dataproxy]
timeout = 300
keep_alive_seconds = 300

[rendering]
concurrent_render_request_limit = 4
```

## Backup Considerations

### What to Backup
- Grafana dashboards (exported JSON)
- Prometheus recording rules
- AlertManager configuration
- Loki configuration
- Custom exporters

### Backup Commands
```bash
# Export Grafana dashboards
curl -H "Authorization: Bearer $API_KEY" \
  https://grafana.mackie.house/api/dashboards/uid/homelab-overview \
  > dashboard-backup.json

# Backup Prometheus data
kubectl exec -n monitoring prometheus-0 -- \
  tar czf - /prometheus > prometheus-backup.tar.gz
```

## Troubleshooting

### Missing Metrics
```bash
# Check ServiceMonitor
kubectl get servicemonitor -n monitoring

# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus 9090
# Visit http://localhost:9090/targets

# Check service labels
kubectl get svc -n media jellyfin -o yaml
```

### Missing Logs
```bash
# Check Promtail status
kubectl logs -n logging ds/promtail

# Verify annotations
kubectl get pod -n media -o yaml | grep promtail

# Test Loki query
curl -G -s "http://loki.logging:3100/loki/api/v1/query" \
  --data-urlencode 'query={app="jellyfin"}'
```

### Dashboard Issues
```bash
# Check datasources
kubectl exec -n monitoring deployment/grafana -- \
  cat /etc/grafana/provisioning/datasources/*.yaml

# Reload dashboards
kubectl rollout restart deployment/grafana -n monitoring
```

## Integration Testing

### Metric Verification
```bash
# Test each exporter
for svc in loki promtail authelia jellyfin-exporter; do
  echo "Testing $svc metrics..."
  kubectl exec -n monitoring deployment/prometheus -- \
    wget -O- http://$svc:9090/metrics | head -20
done
```

### Log Flow Test
```bash
# Generate test log
kubectl run test-log --image=busybox --rm -it -- \
  sh -c "echo 'ERROR: Test error message' && sleep 60"

# Query in Loki
curl -G -s "http://loki.logging:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={pod="test-log"}' \
  --data-urlencode 'start=5m'
```

### Alert Test
```bash
# Trigger test alert
kubectl exec -n monitoring prometheus-0 -- \
  promtool test rules /etc/prometheus/rules/*.yaml
```