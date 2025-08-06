# Identity Management Strategy

## Current State
- **Gitea**: Already running on ci.gmac.io
- **Nextcloud**: Already on NAS
- **Homelab Auth**: Currently using Authelia for SSO

## Identity Management Options

### Option 1: Separate Domains (Recommended)

**Business Domain (gmac.io/gmacko.com)**
- Full Active Directory or FreeIPA
- Professional services (Gitea, business apps)
- Client/employee accounts
- Strict security policies
- Compliance requirements

**Homelab Domain (mackie.house)**
- Lightweight identity solution
- Family/personal accounts
- Media and home automation
- Relaxed security policies
- Integration with smart home

**Pros:**
- Clear separation of business/personal
- Different security policies
- Easier compliance for business
- Simpler disaster recovery

**Cons:**
- Manage two identity systems
- Some account duplication
- Separate credentials

### Option 2: Unified Domain

Single AD/FreeIPA for everything

**Pros:**
- Single sign-on everywhere
- One system to manage
- Consistent policies

**Cons:**
- Business and personal data mixed
- Complex security policies
- Harder to sell/separate business
- Overkill for home use

### Option 3: Federated Approach (Hybrid)

**Structure:**
- Business AD/FreeIPA as primary
- Homelab uses LDAP/SAML from business
- Local accounts for family-only services

**Pros:**
- Best of both worlds
- Can selectively share accounts
- Business remains portable

**Cons:**
- Most complex setup
- Dependency between systems

## Recommended Architecture

### For Homelab (mackie.house)

```yaml
# Lightweight FreeIPA setup
Primary Services:
  - DNS (integrated with Pi-hole)
  - LDAP for user auth
  - Kerberos (optional)
  - Certificate Authority
  
User Groups:
  - family-admins (full access)
  - family-users (media, home automation)
  - guests (limited media access)
  
Integration Points:
  - Authelia → LDAP
  - Jellyfin → LDAP
  - Home Assistant → LDAP
  - WiFi → RADIUS → LDAP
```

### For Business (gmac.io)

```yaml
# Full Active Directory or FreeIPA
Primary Services:
  - DNS
  - LDAP/AD
  - Kerberos
  - PKI/Certificate Authority
  - Group Policy (if AD)
  
User Groups:
  - domain-admins
  - developers
  - contractors
  - clients
  
Integration Points:
  - Gitea → LDAP/AD
  - CI/CD → LDAP/AD
  - VPN → RADIUS → AD
  - Business apps → SAML/OIDC
```

## Implementation Plan

### Phase 1: Homelab Identity (FreeIPA)
1. Deploy FreeIPA in homelab
2. Migrate Authelia users to FreeIPA
3. Configure LDAP integration
4. Set up WiFi RADIUS

### Phase 2: Service Integration
1. Configure all services for LDAP
2. Set up groups and permissions
3. Enable Kerberos (optional)
4. Configure certificate auto-enrollment

### Phase 3: Business Identity (Separate)
1. Deploy AD/FreeIPA on gmac.io
2. Migrate existing accounts
3. Set up trust relationship (optional)
4. Configure SAML for cross-domain (if needed)

## Technology Comparison

### FreeIPA (Recommended for Homelab)
- **Pros**: Open source, full featured, good web UI
- **Cons**: Resource intensive, complex
- **Use case**: Perfect for homelab scale

### Samba AD
- **Pros**: AD compatible, Windows friendly
- **Cons**: Less polished UI, some limitations
- **Use case**: If you need real AD compatibility

### OpenLDAP + Keycloak
- **Pros**: Lightweight, modern auth
- **Cons**: More pieces to manage
- **Use case**: Microservices architecture

### Authentik
- **Pros**: Modern, container-native
- **Cons**: Newer, less battle-tested
- **Use case**: Cloud-native environments

## Security Considerations

### Homelab
- Relaxed password policies
- Longer session timeouts
- Simple MFA (TOTP only)
- Local network trust

### Business
- Strong password policies
- Short session timeouts
- Hardware token support
- Zero trust networking
- Audit logging
- Compliance requirements

## Decision Matrix

| Factor | Separate | Unified | Federated |
|--------|----------|---------|-----------|
| Complexity | Low | Medium | High |
| Security | High | Medium | High |
| Maintenance | Medium | Low | High |
| Flexibility | High | Low | Medium |
| Cost | Medium | Low | Medium |

## Recommendation

**Use Option 1: Separate Domains**

1. **Homelab**: Deploy FreeIPA for family/personal use
2. **Business**: Deploy separate AD/FreeIPA for business
3. **Integration**: Use SAML/OIDC for specific cross-domain needs

This provides:
- Clear separation of concerns
- Appropriate security levels
- Business portability
- Family-friendly homelab