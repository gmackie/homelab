# Access Control Configuration

This homelab uses Traefik middleware to control access to services.

## Architecture

```
Internet → Router → K3s/Traefik → Services
                         ↓
                    Middleware
                    - local-only
                    - basic-auth
                    - rate-limit
```

## Access Levels

### 1. Public Access
- Main website (mackie.house)
- No authentication required
- Rate limited

### 2. Authenticated Public Access
- Secure dashboard (secure.mackie.house)
- Requires basic authentication
- Provides monitoring APIs and management links

### 3. Local Network Only
- All administrative interfaces
- Direct service access
- No external access possible

## Configuration

### Changing Local Network Ranges

Edit `k3s/traefik-config.yaml` and modify the `sourceRange` list:

```yaml
spec:
  ipWhiteList:
    sourceRange:
      - 192.168.1.0/24  # Your specific subnet
      - 10.0.0.0/8
```

### Updating Basic Auth Credentials

1. Generate new credentials:
   ```bash
   htpasswd -nb myusername mypassword
   ```

2. Base64 encode the output:
   ```bash
   echo -n "myusername:$2y$05$..." | base64
   ```

3. Update `k3s/traefik-config.yaml` with the new value

4. Apply changes:
   ```bash
   kubectl apply -f k3s/traefik-config.yaml
   ```

### Making Services Public

To make a local-only service publicly accessible:

1. Remove the middleware annotation from the service's ingress
2. Or change it to use `secure-external` for authenticated access

Example:
```yaml
# From (local-only):
annotations:
  traefik.ingress.kubernetes.io/router.middlewares: kube-system-local-only@kubernetescrd

# To (authenticated public):
annotations:
  traefik.ingress.kubernetes.io/router.middlewares: kube-system-secure-external@kubernetescrd

# To (fully public):
# Remove the middleware annotation entirely
```

## Security Best Practices

1. **Regular Updates**: Update basic auth credentials regularly
2. **Monitor Access**: Check Grafana dashboards for unusual access patterns
3. **Firewall Rules**: Ensure router firewall only forwards ports 80/443
4. **Certificate Management**: Let cert-manager handle SSL certificates
5. **Service Isolation**: Keep administrative interfaces local-only

## Troubleshooting

### Can't Access Local Services Remotely
- This is by design - use VPN or access from local network
- Check if your IP is in the allowed ranges

### Basic Auth Not Working
- Verify credentials are base64 encoded correctly
- Check if the secret was applied: `kubectl get secret -n kube-system basic-auth-secret`

### Services Accessible When They Shouldn't Be
- Verify middleware is applied: `kubectl describe ingress -n <namespace> <ingress-name>`
- Check for the middleware annotation in the output