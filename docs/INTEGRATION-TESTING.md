# FreeIPA Integration Testing Guide

## Overview

This guide helps verify that all services are properly integrated with FreeIPA for centralized authentication.

## Test Scenarios

### 1. Basic LDAP Connectivity

```bash
# Test from any pod
kubectl run ldap-test --rm -it --image=alpine -- sh
apk add openldap-clients
ldapsearch -x -H ldap://freeipa.identity:389 -b "dc=mackie,dc=house" "(objectclass=*)"
```

### 2. Authelia Authentication Flow

#### Test Login
1. Navigate to any protected service (e.g., https://grafana.mackie.house)
2. You should be redirected to https://auth.mackie.house
3. Login with test credentials:
   - Username: john
   - Password: Test123!
4. Complete 2FA setup if required
5. You should be redirected back to the original service

#### Test Group Access
1. Login as `john` (family-admins group)
   - ✅ Should access: All services
   - ✅ Admin privileges in Grafana
   
2. Login as `jane` (media-users group)
   - ✅ Should access: Jellyfin, Sonarr, Radarr
   - ❌ Should NOT access: Dashboard, Longhorn, Pi-hole
   - ✅ Viewer privileges in Grafana

### 3. Service-Specific Tests

#### Grafana LDAP
```bash
# Check LDAP config
kubectl exec -n monitoring deployment/kube-prometheus-stack-grafana -- cat /etc/grafana/ldap.toml

# Check logs for LDAP
kubectl logs -n monitoring deployment/kube-prometheus-stack-grafana | grep -i ldap

# Test login
# 1. Go to https://grafana.mackie.house
# 2. Click "Sign in with LDAP"
# 3. Use FreeIPA credentials
```

#### Jellyfin LDAP
```bash
# Check plugin status
kubectl exec -n media deployment/jellyfin -- ls /config/plugins/

# Test login
# 1. Go to https://jellyfin.mackie.house
# 2. Use FreeIPA credentials
# 3. Check user was auto-created
```

#### Home Assistant
```bash
# Check auth providers
kubectl exec -n home-automation deployment/home-assistant -- cat /config/configuration.yaml | grep -A5 auth_providers

# Test login with FreeIPA credentials
```

### 4. DNS Integration Test

```bash
# Test from Pi-hole
kubectl exec -n pihole deployment/pihole -- dig ipa.mackie.house @192.168.1.54

# Test reverse DNS
kubectl exec -n pihole deployment/pihole -- dig -x 192.168.1.54 @192.168.1.54
```

### 5. Session Management

#### Single Sign-On Test
1. Login to Authelia portal
2. Navigate to different services without re-authenticating
3. Verify session persists across services

#### Logout Test
1. Go to https://auth.mackie.house/logout
2. Try accessing protected service
3. Should be redirected to login

### 6. API Authentication

```bash
# Get Authelia session cookie
SESSION=$(curl -c - -X POST https://auth.mackie.house/api/firstfactor \
  -H "Content-Type: application/json" \
  -d '{"username":"john","password":"Test123!"}' | grep authelia_session | awk '{print $7}')

# Use session for API calls
curl -H "Cookie: authelia_session=$SESSION" https://grafana.mackie.house/api/org
```

## Troubleshooting

### FreeIPA Issues

```bash
# Check FreeIPA status
kubectl exec -n identity freeipa-0 -- ipactl status

# Check FreeIPA logs
kubectl logs -n identity freeipa-0

# Test admin login
kubectl exec -n identity freeipa-0 -- bash -c "echo 'Test123!' | kinit john"

# List users
kubectl exec -n identity freeipa-0 -- ipa user-find

# List groups
kubectl exec -n identity freeipa-0 -- ipa group-find
```

### Authelia Issues

```bash
# Check Authelia logs
kubectl logs -n auth deployment/authelia -f

# Check LDAP connection
kubectl exec -n auth deployment/authelia -- wget -O- http://localhost:9091/api/health

# Test LDAP bind
kubectl exec -n auth deployment/authelia -- sh -c \
  "apk add openldap-clients && ldapwhoami -x -H ldap://freeipa.identity:389 \
   -D 'uid=authelia,cn=users,cn=accounts,dc=mackie,dc=house' -W"
```

### Service Integration Issues

```bash
# Check if service has auth middleware
kubectl get ingress -A -o yaml | grep -B5 -A5 "authelia"

# Check service account passwords
kubectl get secret freeipa-service-accounts -n auth -o yaml

# Verify LDAP search from service namespace
kubectl run -n media test-ldap --rm -it --image=alpine -- sh -c \
  "apk add openldap-clients && ldapsearch -x -H ldap://freeipa.identity:389 \
   -D 'uid=jellyfin,cn=users,cn=accounts,dc=mackie,dc=house' -W \
   -b 'cn=users,cn=accounts,dc=mackie,dc=house' '(uid=john)'"
```

## Performance Testing

### LDAP Query Performance
```bash
# Time LDAP queries
time kubectl exec -n auth deployment/authelia -- sh -c \
  "for i in {1..100}; do \
     ldapsearch -x -H ldap://freeipa.identity:389 \
     -D 'uid=authelia,cn=users,cn=accounts,dc=mackie,dc=house' \
     -w 'password' -b 'dc=mackie,dc=house' '(uid=john)' >/dev/null; \
   done"
```

### Authentication Load Test
```bash
# Simple load test (adjust URL and credentials)
for i in {1..10}; do
  curl -X POST https://auth.mackie.house/api/firstfactor \
    -H "Content-Type: application/json" \
    -d '{"username":"john","password":"Test123!"}' &
done
wait
```

## Security Verification

### 1. Access Control Matrix

| Service | family-admins | media-users | family-users | guests |
|---------|--------------|-------------|--------------|--------|
| Dashboard | ✅ | ❌ | ❌ | ❌ |
| Grafana | ✅ Admin | ✅ Viewer | ✅ Viewer | ❌ |
| Jellyfin | ✅ | ✅ | ✅ | ❌ |
| Sonarr | ✅ | ✅ | ❌ | ❌ |
| Pi-hole | ✅ | ❌ | ❌ | ❌ |
| Home Assistant | ✅ | ❌ | ✅ | ❌ |

### 2. Password Policy Test
```bash
# Try weak password (should fail)
kubectl exec -n identity freeipa-0 -- ipa user-add testuser \
  --first=Test --last=User --password <<< 'weak
weak'

# Check password policy
kubectl exec -n identity freeipa-0 -- ipa pwpolicy-show
```

### 3. Certificate Validation
```bash
# Check FreeIPA CA cert
kubectl exec -n identity freeipa-0 -- ipa ca-show ipa

# Verify service certificates
openssl s_client -connect ipa.mackie.house:443 -servername ipa.mackie.house
```

## Monitoring Integration

### Prometheus Metrics
Add to Grafana dashboard:
- LDAP query duration
- Authentication success/failure rate
- Active sessions count
- Group membership queries

### Alerts
```yaml
- alert: HighAuthenticationFailureRate
  expr: rate(authelia_authentication_attempts_total{success="false"}[5m]) > 0.1
  annotations:
    summary: "High authentication failure rate"
    
- alert: FreeIPADown
  expr: up{job="freeipa"} == 0
  for: 5m
  annotations:
    summary: "FreeIPA is down"
```

## Backup Verification

```bash
# Backup FreeIPA data
kubectl exec -n identity freeipa-0 -- ipa-backup

# List backups
kubectl exec -n identity freeipa-0 -- ipa-backup --list

# Test restore in separate namespace
kubectl create ns identity-test
# ... deploy FreeIPA and restore
```