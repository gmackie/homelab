# 🔐 Security Notes

## Placeholder Credentials

This repository contains **NO real secrets**. All credentials are placeholder values that must be replaced before deployment:

### 📝 Credentials to Replace

| Service | File | Credential | Default Value |
|---------|------|------------|---------------|
| WiFi | `smart-home/esphome-devices.yaml` | WiFi Password | `homelab-wifi-password` |
| MQTT | `smart-home/home-assistant.yaml` | MQTT Password | `edgepassword` |
| Grafana | `apps/monitoring/kube-prometheus-stack-values.yaml` | Admin Password | `changeme` |
| Pi-hole | `apps/networking/pihole-values.yaml` | Admin Password | `changeme` |
| Vaultwarden | `apps/tools/vaultwarden.yaml` | Admin Token | `your_very_secure_admin_token` |
| AWS S3 | `apps/backup/backup-cronjobs.yaml` | Access Keys | `your-access-key` |

### ⚠️ Before Deployment

1. **Search and replace** all placeholder values:
   ```bash
   rg -i "changeme|your-.*-key|edgepassword|homelab-wifi-password"
   ```

2. **Generate secure passwords**:
   ```bash
   # Random password
   openssl rand -base64 32
   
   # Admin token
   openssl rand -base64 48
   ```

3. **Use Kubernetes secrets** for sensitive data:
   ```bash
   kubectl create secret generic my-secret --from-literal=password="$(openssl rand -base64 32)"
   ```

### 🛡️ Security Best Practices

- **Never commit real credentials** to version control
- **Use strong, unique passwords** for each service
- **Enable 2FA** where supported (Vaultwarden, Grafana)
- **Regularly rotate** passwords and API keys
- **Monitor access logs** for unauthorized access
- **Use HTTPS/TLS** for all web interfaces

### 🔍 Credential Locations

All placeholder credentials are clearly marked with comments like:
- `# CHANGE THIS!`
- `# Change this!`
- `# Generate with: openssl rand -base64 48`
- `# Update after service is configured`

### ✅ Repository Security Status

- ✅ No real secrets committed
- ✅ All credentials are placeholders
- ✅ Security scanning patterns included
- ✅ Clear documentation for replacement
- ✅ Best practices documented

**Safe to commit and share publicly!** 🚀