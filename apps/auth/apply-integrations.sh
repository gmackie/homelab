#!/bin/bash

echo "=== FreeIPA Integration Deployment ==="
echo

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to check if resource exists
resource_exists() {
    kubectl get $1 $2 -n $3 &> /dev/null
    return $?
}

# Function to wait for pod
wait_for_pod() {
    echo -n "Waiting for $1 in namespace $2..."
    kubectl wait --for=condition=Ready pod -l app=$1 -n $2 --timeout=300s
    if [ $? -eq 0 ]; then
        echo -e " ${GREEN}Ready${NC}"
    else
        echo -e " ${RED}Failed${NC}"
        exit 1
    fi
}

echo "Step 1: Deploy FreeIPA"
echo "====================="
kubectl apply -f freeipa.yaml
wait_for_pod "freeipa" "identity"

echo -e "\nStep 2: Run FreeIPA Setup"
echo "========================="
./freeipa-setup.sh

echo -e "\nStep 3: Update Authelia Configuration"
echo "====================================="
# Backup existing Authelia config
kubectl get configmap authelia-config -n auth -o yaml > authelia-config-backup.yaml 2>/dev/null || true

# Apply new Authelia config with FreeIPA
kubectl apply -f authelia-freeipa.yaml

# Sync LDAP password
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: sync-authelia-ldap-password-$(date +%s)
  namespace: auth
spec:
  template:
    spec:
      serviceAccountName: default
      containers:
      - name: sync
        image: bitnami/kubectl:latest
        command:
        - /bin/bash
        - -c
        - |
          LDAP_PASS=\$(kubectl get secret freeipa-service-accounts -n auth -o jsonpath='{.data.authelia-password}')
          kubectl patch secret authelia-secrets -n auth --type='json' \
            -p='[{"op": "replace", "path": "/data/LDAP_PASSWORD", "value": "'\$LDAP_PASS'"}]'
          kubectl rollout restart deployment/authelia -n auth
      restartPolicy: OnFailure
EOF

echo -e "\nStep 4: Apply Service Authentication Patches"
echo "==========================================="
# Apply auth middleware to services
kubectl apply -f service-auth-patches.yaml

echo -e "\nStep 5: Configure Service-Specific LDAP"
echo "======================================="

# Grafana LDAP
echo -e "${YELLOW}Configuring Grafana LDAP...${NC}"
kubectl apply -f grafana-ldap-config.yaml
kubectl rollout restart deployment/kube-prometheus-stack-grafana -n monitoring 2>/dev/null || true

# Jellyfin LDAP (if deployed)
if resource_exists "deployment" "jellyfin" "media"; then
    echo -e "${YELLOW}Configuring Jellyfin LDAP...${NC}"
    kubectl apply -f jellyfin-ldap-config.yaml
fi

echo -e "\nStep 6: Create Test Users"
echo "========================"
kubectl exec -n identity freeipa-0 -- bash -c "
echo 'Creating test users...'
echo 'changeme' | kinit admin

# Create test family admin
ipa user-add john --first=John --last=Doe --email=john@mackie.house --password <<< 'Test123!
Test123!' || true
ipa group-add-member family-admins --users=john || true

# Create test media user
ipa user-add jane --first=Jane --last=Doe --email=jane@mackie.house --password <<< 'Test123!
Test123!' || true
ipa group-add-member media-users --users=jane || true

echo 'Test users created:'
echo '  john (family-admins): Test123!'
echo '  jane (media-users): Test123!'
"

echo -e "\nStep 7: Verification"
echo "==================="

# Test LDAP connectivity
echo -n "Testing LDAP connectivity..."
kubectl run ldap-test --image=alpine --rm -it --restart=Never -- \
    sh -c "apk add openldap-clients && ldapsearch -x -H ldap://freeipa.identity:389 -b 'dc=mackie,dc=house' -s base '(objectclass=*)'" &> /dev/null
if [ $? -eq 0 ]; then
    echo -e " ${GREEN}Success${NC}"
else
    echo -e " ${RED}Failed${NC}"
fi

# Check Authelia
echo -n "Checking Authelia..."
kubectl get pod -n auth -l app=authelia -o jsonpath='{.items[0].status.phase}' | grep -q "Running"
if [ $? -eq 0 ]; then
    echo -e " ${GREEN}Running${NC}"
else
    echo -e " ${RED}Not Running${NC}"
fi

echo -e "\n${GREEN}=== Integration Complete ===${NC}"
echo
echo "Access Points:"
echo "  - FreeIPA Admin: https://ipa.mackie.house"
echo "  - Authelia Portal: https://auth.mackie.house"
echo
echo "Test Accounts:"
echo "  - Admin: john / Test123! (family-admins group)"
echo "  - User: jane / Test123! (media-users group)"
echo
echo "Next Steps:"
echo "1. Access FreeIPA web UI and create real user accounts"
echo "2. Test authentication at https://auth.mackie.house"
echo "3. Try accessing protected services"
echo "4. Configure additional services for LDAP as needed"
echo
echo "Troubleshooting:"
echo "  - Check FreeIPA: kubectl logs -n identity freeipa-0"
echo "  - Check Authelia: kubectl logs -n auth -l app=authelia"
echo "  - Test LDAP: ldapsearch -x -H ldap://freeipa.identity:389 -D 'uid=admin,cn=users,cn=accounts,dc=mackie,dc=house' -W"