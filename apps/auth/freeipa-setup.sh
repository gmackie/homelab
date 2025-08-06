#!/bin/bash

# FreeIPA Service Account Setup Script
# Run this after FreeIPA is deployed and initialized

echo "Setting up FreeIPA service accounts and groups..."

# Wait for FreeIPA to be ready
kubectl wait --for=condition=Ready pod/freeipa-0 -n identity --timeout=600s

# Function to run commands in FreeIPA pod
ipa_exec() {
    kubectl exec -n identity freeipa-0 -- bash -c "$1"
}

# Get admin password from secret
ADMIN_PASS=$(kubectl get secret -n identity freeipa-passwords -o jsonpath='{.data.admin_password}' | base64 -d)

echo "Creating groups..."
ipa_exec "echo '$ADMIN_PASS' | kinit admin"

# Create groups
ipa_exec "ipa group-add family-admins --desc='Family Administrators' || true"
ipa_exec "ipa group-add family-users --desc='Family Users' || true"
ipa_exec "ipa group-add media-users --desc='Media Access' || true"
ipa_exec "ipa group-add media-admins --desc='Media Administrators' || true"
ipa_exec "ipa group-add home-automation --desc='Home Automation Access' || true"
ipa_exec "ipa group-add monitoring-users --desc='Monitoring Access' || true"
ipa_exec "ipa group-add guests --desc='Guest Access' || true"

echo "Creating service accounts..."

# Create system accounts container if it doesn't exist
ipa_exec "ipa automember-add --type=group system-accounts --desc='System Service Accounts' || true"

# Function to create service account
create_service_account() {
    local service=$1
    local password=$2
    echo "Creating service account for $service..."
    
    ipa_exec "ipa user-add $service --first='$service' --last='Service' --password <<< '$password
$password' || true"
    ipa_exec "ipa group-add-member system-accounts --users=$service || true"
    
    # Set password never expires
    ipa_exec "ipa user-mod $service --setattr=krbPasswordExpiration=20380119031407Z || true"
}

# Generate passwords (you should change these!)
AUTHELIA_PASS="AutheliaServicePass123!"
JELLYFIN_PASS="JellyfinServicePass123!"
GRAFANA_PASS="GrafanaServicePass123!"
RADIUS_PASS="RadiusServicePass123!"
SONARR_PASS="SonarrServicePass123!"
RADARR_PASS="RadarrServicePass123!"

# Create service accounts
create_service_account "authelia" "$AUTHELIA_PASS"
create_service_account "jellyfin" "$JELLYFIN_PASS"
create_service_account "grafana" "$GRAFANA_PASS"
create_service_account "radius" "$RADIUS_PASS"
create_service_account "sonarr" "$SONARR_PASS"
create_service_account "radarr" "$RADARR_PASS"

echo "Creating HBAC rules..."

# Create HBAC rules for service access
ipa_exec "ipa hbacrule-add allow_all_services --desc='Allow all users to access all services' || true"
ipa_exec "ipa hbacrule-add-user allow_all_services --groups=family-users || true"
ipa_exec "ipa hbacrule-add-user allow_all_services --groups=family-admins || true"
ipa_exec "ipa hbacrule-add-host allow_all_services --hostgroups=ipaservers || true"
ipa_exec "ipa hbacrule-add-service allow_all_services --hbacservicegroups=all || true"

echo "Setting up sudo rules..."

# Create sudo rules for admins
ipa_exec "ipa sudorule-add admin_all --desc='Admin users can run all commands' || true"
ipa_exec "ipa sudorule-add-user admin_all --groups=family-admins || true"
ipa_exec "ipa sudorule-mod admin_all --hostcat=all || true"
ipa_exec "ipa sudorule-add-option admin_all --sudooption='!authenticate' || true"
ipa_exec "ipa sudorule-mod admin_all --cmdcat=all || true"

echo "Creating permission sets..."

# Media permissions
ipa_exec "ipa privilege-add media-management --desc='Media service management' || true"
ipa_exec "ipa role-add media-manager --desc='Media Manager Role' || true"
ipa_exec "ipa role-add-privilege media-manager --privileges=media-management || true"
ipa_exec "ipa role-add-member media-manager --groups=media-admins || true"

echo "Storing service account passwords in Kubernetes secrets..."

# Store passwords in Kubernetes secrets for service use
kubectl create secret generic freeipa-service-accounts -n auth \
  --from-literal=authelia-password="$AUTHELIA_PASS" \
  --from-literal=jellyfin-password="$JELLYFIN_PASS" \
  --from-literal=grafana-password="$GRAFANA_PASS" \
  --from-literal=radius-password="$RADIUS_PASS" \
  --from-literal=sonarr-password="$SONARR_PASS" \
  --from-literal=radarr-password="$RADARR_PASS" \
  --dry-run=client -o yaml | kubectl apply -f -

# Copy to other namespaces
for ns in monitoring media tools identity; do
  kubectl create secret generic freeipa-service-accounts -n $ns \
    --from-literal=authelia-password="$AUTHELIA_PASS" \
    --from-literal=jellyfin-password="$JELLYFIN_PASS" \
    --from-literal=grafana-password="$GRAFANA_PASS" \
    --from-literal=radius-password="$RADIUS_PASS" \
    --from-literal=sonarr-password="$SONARR_PASS" \
    --from-literal=radarr-password="$RADARR_PASS" \
    --dry-run=client -o yaml | kubectl apply -f -
done

echo ""
echo "FreeIPA setup complete!"
echo ""
echo "Service accounts created with passwords stored in Kubernetes secrets."
echo "You should change these passwords in production!"
echo ""
echo "Next steps:"
echo "1. Create user accounts through the FreeIPA web UI"
echo "2. Update service configurations to use LDAP"
echo "3. Test authentication with: ldapsearch -x -H ldap://freeipa.identity:389 -D uid=authelia,cn=users,cn=accounts,dc=mackie,dc=house -W"