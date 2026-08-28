#!/bin/bash

# Simple validation for YAML files with multiple documents
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

total=0
valid=0
invalid=0

echo "🔍 Validating homelab YAML configurations..."
echo

validate_file() {
    local file=$1
    local basename
    basename=$(basename "$file")
    ((total+=1))
    
    # Handle multi-document YAML files
    if python3 -c "
import yaml
try:
    with open('$file') as f:
        docs = list(yaml.safe_load_all(f))
    print(f'Valid: $basename ({len(docs)} documents)')
except Exception as e:
    print(f'Invalid: $basename - {e}')
    exit(1)
" 2>/dev/null; then
        ((valid+=1))
    else
        echo -e "${RED}✗ $basename${NC}"
        ((invalid+=1))
    fi
}

# Validate key files we've created
key_files=(
    "storage/network-storage.yaml"
    "services/homelab-services.yaml"
    "smart-home/home-assistant.yaml"
    "smart-home/esphome-devices.yaml"
    "media/media-stack.yaml"
    "media/sabnzbd.yaml"
    "monitoring/grafana-homeassistant.yaml"
    "apps/dashboard/api/deployment.yaml"
    "apps/dashboard/ui/deployment.yaml"
)

echo "Validating key homelab configurations:"
echo

for file in "${key_files[@]}"; do
    full_path="$REPO_ROOT/$file"
    if [[ -f "$full_path" ]]; then
        validate_file "$full_path"
    else
        echo -e "${RED}✗ $file (not found)${NC}"
        ((total+=1))
        ((invalid+=1))
    fi
done

echo
echo "════════════════════════════════════════"
echo "            SUMMARY"
echo "════════════════════════════════════════"
echo "Total:    $total"
echo -e "Valid:    ${GREEN}$valid${NC}"
echo -e "Invalid:  ${RED}$invalid${NC}"
echo

if [[ $invalid -eq 0 ]]; then
    echo -e "${GREEN}🎉 All key configurations are valid!${NC}"
    echo
    echo "Your homelab is ready for deployment. You can:"
    echo "1. Deploy individual components with kubectl apply -f <file>"
    echo "2. Use the deployment scripts in ./setup/"
    echo "3. Set up your 1024x600 touchscreen with Homer dashboard"
else
    echo -e "${RED}❌ Some configurations need attention.${NC}"
    exit 1
fi
