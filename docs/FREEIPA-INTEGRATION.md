# FreeIPA Integration Guide

## Initial Setup

### 1. Deploy FreeIPA
```bash
kubectl apply -f apps/auth/freeipa.yaml
# Wait for initialization (can take 10-15 minutes)
kubectl logs -n identity freeipa-0 -f
```

### 2. Access FreeIPA Web UI
- URL: https://ipa.mackie.house
- Username: admin
- Password: (from your secret)

### 3. Initial Configuration

#### Create User Groups
```bash
# Access FreeIPA pod
kubectl exec -it -n identity freeipa-0 -- bash

# Authenticate
kinit admin

# Create groups
ipa group-add family-admins --desc="Family Administrators"
ipa group-add family-users --desc="Family Users"
ipa group-add media-users --desc="Media Access"
ipa group-add home-automation --desc="Home Automation Access"
ipa group-add guests --desc="Guest Access"
```

#### Create Users
```bash
# Create family members
ipa user-add john --first=John --last=Doe --email=john@mackie.house
ipa user-add jane --first=Jane --last=Doe --email=jane@mackie.house

# Set passwords
ipa passwd john
ipa passwd jane

# Add to groups
ipa group-add-member family-admins --users=john
ipa group-add-member family-users --users=jane
```

## Service Integration

### Authelia with FreeIPA LDAP

Update `apps/auth/authelia.yaml`:

```yaml
authentication_backend:
  ldap:
    url: ldap://freeipa.identity:389
    start_tls: false
    tls:
      skip_verify: true
    base_dn: dc=mackie,dc=house
    username_attribute: uid
    additional_users_dn: cn=users,cn=accounts
    users_filter: (&(objectClass=person)(uid={username}))
    additional_groups_dn: cn=groups,cn=accounts
    groups_filter: (&(objectClass=groupOfNames)(member={dn}))
    group_name_attribute: cn
    mail_attribute: mail
    display_name_attribute: displayName
    user: uid=authelia,cn=sysaccounts,cn=etc,dc=mackie,dc=house
    password: 'authelia_bind_password'
```

### Jellyfin LDAP

1. Install LDAP plugin in Jellyfin
2. Configure:
   - LDAP Server: `freeipa.identity`
   - Port: `389`
   - Base DN: `dc=mackie,dc=house`
   - Bind DN: `uid=jellyfin,cn=sysaccounts,cn=etc,dc=mackie,dc=house`
   - User Search Base: `cn=users,cn=accounts,dc=mackie,dc=house`
   - User Search Filter: `(uid={username})`

### Grafana LDAP

Update Grafana configuration:

```ini
[auth.ldap]
enabled = true
config_file = /etc/grafana/ldap.toml

[auth]
disable_login_form = false
```

LDAP config (`ldap.toml`):
```toml
[[servers]]
host = "freeipa.identity"
port = 389
use_ssl = false
bind_dn = "uid=grafana,cn=sysaccounts,cn=etc,dc=mackie,dc=house"
bind_password = 'grafana_bind_password'
search_filter = "(uid=%s)"
search_base_dns = ["cn=users,cn=accounts,dc=mackie,dc=house"]

[servers.attributes]
username = "uid"
name = "cn"
surname = "sn"
email = "mail"
member_of = "memberOf"

[[servers.group_mappings]]
group_dn = "cn=family-admins,cn=groups,cn=accounts,dc=mackie,dc=house"
org_role = "Admin"

[[servers.group_mappings]]
group_dn = "cn=family-users,cn=groups,cn=accounts,dc=mackie,dc=house"
org_role = "Editor"
```

### Home Assistant LDAP

Add to `configuration.yaml`:

```yaml
auth_providers:
  - type: command_line
    command: /config/ldap_auth.sh
    meta: true
```

Create `/config/ldap_auth.sh`:
```bash
#!/bin/bash
ldapsearch -x -H ldap://freeipa.identity:389 \
  -D "uid=$1,cn=users,cn=accounts,dc=mackie,dc=house" \
  -w "$2" \
  -b "dc=mackie,dc=house" \
  "(uid=$1)" > /dev/null 2>&1
```

### Sonarr/Radarr LDAP

These don't support LDAP directly, but you can:
1. Use Authelia in front with ForwardAuth
2. Or use Organizr as a frontend with LDAP

### WiFi RADIUS Integration

Deploy FreeRADIUS:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: freeradius
  namespace: identity
spec:
  replicas: 1
  selector:
    matchLabels:
      app: freeradius
  template:
    metadata:
      labels:
        app: freeradius
    spec:
      containers:
      - name: freeradius
        image: freeradius/freeradius-server:latest
        ports:
        - containerPort: 1812
          name: radius-auth
          protocol: UDP
        - containerPort: 1813
          name: radius-acct
          protocol: UDP
        volumeMounts:
        - name: config
          mountPath: /etc/freeradius
      volumes:
      - name: config
        configMap:
          name: freeradius-config
```

## Service Accounts

Create service accounts for each integration:

```bash
# Create service accounts
ipa service-add authelia/ipa.mackie.house
ipa service-add jellyfin/ipa.mackie.house
ipa service-add grafana/ipa.mackie.house
ipa service-add radius/ipa.mackie.house

# Create bind users
echo 'password123' | ipa user-add authelia --first=Authelia --last=Service --password
echo 'password123' | ipa user-add jellyfin --first=Jellyfin --last=Service --password
```

## DNS Integration with Pi-hole

Configure Pi-hole to forward internal queries to FreeIPA:

1. In Pi-hole admin:
   - Settings → DNS → Conditional Forwarding
   - Local network: `192.168.1.0/24`
   - Domain: `mackie.house`
   - Router IP: `192.168.1.54` (FreeIPA DNS)

2. Or add custom DNS:
   ```
   server=/mackie.house/192.168.1.54
   server=/1.168.192.in-addr.arpa/192.168.1.54
   ```

## Kerberos SSO (Optional)

For services that support Kerberos:

```bash
# Generate keytab for service
ipa-getkeytab -s ipa.mackie.house -p HTTP/service.mackie.house -k /etc/krb5.keytab

# Configure browser for SSO
# Firefox: about:config
# network.negotiate-auth.trusted-uris = .mackie.house
```

## Backup and Recovery

### Backup FreeIPA
```bash
# Full backup
kubectl exec -n identity freeipa-0 -- ipa-backup

# Copy backup locally
kubectl cp identity/freeipa-0:/var/lib/ipa/backup/ ./freeipa-backup/
```

### Restore FreeIPA
```bash
# Copy backup to pod
kubectl cp ./freeipa-backup/ identity/freeipa-0:/var/lib/ipa/backup/

# Restore
kubectl exec -n identity freeipa-0 -- ipa-restore
```

## Monitoring

Add to Prometheus:
```yaml
- job_name: 'freeipa'
  static_configs:
  - targets: ['freeipa.identity:443']
  metrics_path: '/metrics'
  scheme: https
  tls_config:
    insecure_skip_verify: true
```

## Troubleshooting

### Check FreeIPA Status
```bash
kubectl exec -n identity freeipa-0 -- ipactl status
```

### Test LDAP Connection
```bash
ldapsearch -x -H ldap://freeipa.identity:389 \
  -D "uid=admin,cn=users,cn=accounts,dc=mackie,dc=house" \
  -W -b "dc=mackie,dc=house" "(objectclass=*)"
```

### Reset Admin Password
```bash
kubectl exec -n identity freeipa-0 -- bash
kinit admin
ipa passwd admin
```

### Common Issues

1. **Services can't connect**: Check DNS resolution and firewall rules
2. **Authentication fails**: Verify bind DN and password
3. **Groups not working**: Check group membership and filters
4. **Slow performance**: Increase memory/CPU limits