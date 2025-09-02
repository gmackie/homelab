#!/bin/bash

# Simple YAML Validation for Existing Files
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

HOMELAB_DIR="${HOMELAB_DIR:-/Volumes/dev/homelab}"
total=0
valid=0
invalid=0

echo "🔍 Validating existing YAML files in homelab..."
echo

validate_file() {
    local file=$1
    ((total++))
    
    if python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
        log_success "✓ $(basename "$file")"
        ((valid++))
    else
        log_error "✗ $(basename "$file")"
        ((invalid++))
    fi
}

# Find and validate all YAML files
while IFS= read -r -d '' file; do
    validate_file "$file"
done < <(find "$HOMELAB_DIR" -name "*.yaml" -type f -print0)

echo
echo "════════════════════════════════════════"
echo "            VALIDATION RESULTS"
echo "════════════════════════════════════════"
echo "Total files:  $total"
echo -e "Valid:        ${GREEN}$valid${NC}"
if [[ $invalid -gt 0 ]]; then
    echo -e "Invalid:      ${RED}$invalid${NC}"
else
    echo "Invalid:      $invalid"
fi
echo

if [[ $invalid -eq 0 ]]; then
    log_success "🎉 All YAML files are valid!"
    echo "Your homelab configuration is ready for deployment."
else
    log_error "❌ Some YAML files have validation errors."
    echo "Please fix the invalid files before deployment."
fi