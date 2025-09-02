#!/bin/bash

# Homelab YAML Validation Script
# Compatible with older bash versions

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
HOMELAB_DIR="${HOMELAB_DIR:-/Volumes/dev/homelab}"

# Display banner
echo -e "${PURPLE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║           Homelab YAML Validation Tool                       ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Validation summary
total_files=0
valid_files=0
invalid_files=0
missing_files=0

# Function to validate YAML file
validate_yaml() {
    local file=$1
    
    if [[ ! -f "$file" ]]; then
        log_warning "File not found: $file"
        ((missing_files++))
        return 1
    fi
    
    ((total_files++))
    
    # Try different validation methods
    if command -v yq &> /dev/null; then
        if yq eval '.' "$file" > /dev/null 2>&1; then
            log_success "✓ Valid: $file"
            ((valid_files++))
            return 0
        else
            log_error "✗ Invalid YAML: $file"
            ((invalid_files++))
            return 1
        fi
    elif command -v python3 &> /dev/null; then
        if python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
            log_success "✓ Valid: $file"
            ((valid_files++))
            return 0
        else
            log_error "✗ Invalid YAML: $file"
            ((invalid_files++))
            return 1
        fi
    elif command -v python &> /dev/null; then
        if python -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
            log_success "✓ Valid: $file"
            ((valid_files++))
            return 0
        else
            log_error "✗ Invalid YAML: $file"
            ((invalid_files++))
            return 1
        fi
    else
        # Basic syntax check using grep
        if grep -q "^[[:space:]]*[^#].*:[[:space:]]*$" "$file"; then
            log_warning "⚠ Basic check passed (no full validation): $file"
            ((valid_files++))
            return 0
        else
            log_error "✗ Appears invalid: $file"
            ((invalid_files++))
            return 1
        fi
    fi
}

# Check for validation tools
log_info "Checking for validation tools..."
if command -v yq &> /dev/null; then
    log_success "Found yq for YAML validation"
elif command -v python3 &> /dev/null && python3 -c "import yaml" 2>/dev/null; then
    log_success "Found python3 with yaml module"
elif command -v python &> /dev/null && python -c "import yaml" 2>/dev/null; then
    log_success "Found python with yaml module"
else
    log_warning "No YAML validation tool found. Will perform basic syntax check only."
    log_info "Install yq or python-yaml for full validation."
fi

echo

# Validate Core Infrastructure
log_info "=== Validating Core Infrastructure ==="
validate_yaml "${HOMELAB_DIR}/infrastructure/core-infrastructure.yaml"

# Validate GitOps
log_info "=== Validating GitOps ==="
validate_yaml "${HOMELAB_DIR}/gitops/argocd.yaml"

# Validate Service Mesh
log_info "=== Validating Service Mesh ==="
validate_yaml "${HOMELAB_DIR}/service-mesh/linkerd.yaml"

# Validate Observability
log_info "=== Validating Observability ==="
validate_yaml "${HOMELAB_DIR}/monitoring/prometheus.yaml"
validate_yaml "${HOMELAB_DIR}/monitoring/grafana.yaml"
validate_yaml "${HOMELAB_DIR}/monitoring/grafana-homeassistant.yaml"

# Validate Storage
log_info "=== Validating Storage ==="
validate_yaml "${HOMELAB_DIR}/storage/network-storage.yaml"

# Validate Media Stack
log_info "=== Validating Media Stack ==="
validate_yaml "${HOMELAB_DIR}/media/media-stack.yaml"
validate_yaml "${HOMELAB_DIR}/media/sabnzbd.yaml"

# Validate Smart Home
log_info "=== Validating Smart Home ==="
validate_yaml "${HOMELAB_DIR}/smart-home/home-assistant.yaml"
validate_yaml "${HOMELAB_DIR}/smart-home/esphome-devices.yaml"

# Validate Homelab Services
log_info "=== Validating Homelab Services ==="
validate_yaml "${HOMELAB_DIR}/services/homelab-services.yaml"

# Validate Dashboard
log_info "=== Validating Dashboard ==="
validate_yaml "${HOMELAB_DIR}/apps/dashboard/api/deployment.yaml"
validate_yaml "${HOMELAB_DIR}/apps/dashboard/ui/deployment.yaml"

# Additional configurations
log_info "=== Validating Additional Configurations ==="
validate_yaml "${HOMELAB_DIR}/edge/edge-computing.yaml"
validate_yaml "${HOMELAB_DIR}/ml-serving/ml-platform.yaml"
validate_yaml "${HOMELAB_DIR}/security/security-hardening.yaml"
validate_yaml "${HOMELAB_DIR}/monitoring/advanced-monitoring.yaml"
validate_yaml "${HOMELAB_DIR}/performance/auto-tuning.yaml"
validate_yaml "${HOMELAB_DIR}/federation/multi-cluster.yaml"
validate_yaml "${HOMELAB_DIR}/event-driven/event-system.yaml"
validate_yaml "${HOMELAB_DIR}/ml-serving/kserve.yaml"
validate_yaml "${HOMELAB_DIR}/docs/documentation-system.yaml"
validate_yaml "${HOMELAB_DIR}/data-pipeline/data-orchestration.yaml"

echo
echo "════════════════════════════════════════════════════════════════"
echo "                    VALIDATION SUMMARY"
echo "════════════════════════════════════════════════════════════════"
echo
echo "Total files checked:   $total_files"
echo -e "${GREEN}Valid files:          $valid_files${NC}"
if [[ $invalid_files -gt 0 ]]; then
    echo -e "${RED}Invalid files:        $invalid_files${NC}"
else
    echo "Invalid files:        $invalid_files"
fi
if [[ $missing_files -gt 0 ]]; then
    echo -e "${YELLOW}Missing files:        $missing_files${NC}"
else
    echo "Missing files:        $missing_files"
fi
echo

if [[ $invalid_files -eq 0 && $missing_files -eq 0 ]]; then
    log_success "✅ All YAML files are valid!"
    echo
    echo "You can now deploy the homelab stack using:"
    echo "  kubectl apply -f <manifest>"
    echo
    echo "Or use the individual deployment scripts in ./setup/"
    exit 0
elif [[ $invalid_files -gt 0 ]]; then
    log_error "❌ Validation failed! Please fix the invalid YAML files."
    exit 1
else
    log_warning "⚠️  Some files are missing but all present files are valid."
    exit 0
fi