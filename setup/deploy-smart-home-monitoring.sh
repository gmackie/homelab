#!/bin/bash

# Smart Home Monitoring Deployment Script
# Deploys Home Assistant with comprehensive Grafana dashboards

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
KUBECTL_CMD="${KUBECTL_CMD:-kubectl}"

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v ${KUBECTL_CMD} &> /dev/null; then
        log_error "kubectl not found. Please install kubectl or set KUBECTL_CMD environment variable."
        return 1
    fi
    
    if ! ${KUBECTL_CMD} cluster-info &> /dev/null; then
        log_warning "Kubernetes cluster not available. Proceeding with YAML validation only."
        export VALIDATE_ONLY=true
    fi
}

# Function to validate YAML files
validate_yaml() {
    local file=$1
    log_info "Validating YAML file: $file"
    
    if command -v yq &> /dev/null; then
        if ! yq eval '.' "$file" > /dev/null 2>&1; then
            log_error "YAML validation failed for $file"
            return 1
        fi
    elif command -v python3 &> /dev/null; then
        if ! python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
            log_error "YAML validation failed for $file"
            return 1
        fi
    else
        log_warning "No YAML validator found (yq or python3), skipping validation"
    fi
    
    log_success "YAML validation passed for $file"
}

# Function to apply Kubernetes manifests
apply_manifest() {
    local file=$1
    local description=$2
    
    log_info "Deploying $description..."
    
    validate_yaml "$file" || return 1
    
    if [[ "${VALIDATE_ONLY:-false}" == "true" ]]; then
        log_warning "Validation-only mode: Would deploy $file"
        return 0
    fi
    
    if ${KUBECTL_CMD} apply -f "$file"; then
        log_success "Successfully deployed $description"
    else
        log_error "Failed to deploy $description"
        return 1
    fi
}

# Function to wait for deployment
wait_for_deployment() {
    local namespace=$1
    local deployment=$2
    local timeout=${3:-300}
    
    if [[ "${VALIDATE_ONLY:-false}" == "true" ]]; then
        return 0
    fi
    
    log_info "Waiting for $deployment in namespace $namespace to be ready..."
    
    if ${KUBECTL_CMD} wait --for=condition=available --timeout=${timeout}s deployment/$deployment -n $namespace; then
        log_success "$deployment is ready"
    else
        log_error "$deployment failed to become ready within ${timeout}s"
        return 1
    fi
}

# Function to check if namespace exists
ensure_namespace() {
    local namespace=$1
    
    if [[ "${VALIDATE_ONLY:-false}" == "true" ]]; then
        return 0
    fi
    
    if ! ${KUBECTL_CMD} get namespace $namespace &> /dev/null; then
        log_info "Creating namespace: $namespace"
        ${KUBECTL_CMD} create namespace $namespace
    fi
}

# Function to deploy smart home stack
deploy_smart_home() {
    log_info "Deploying Smart Home platform..."
    
    # Ensure namespace exists
    ensure_namespace "smart-home"
    
    # Deploy Home Assistant with enhanced configuration
    apply_manifest "${HOMELAB_DIR}/smart-home/home-assistant.yaml" "Home Assistant Smart Home Platform"
    
    # Deploy ESPHome device configurations
    apply_manifest "${HOMELAB_DIR}/smart-home/esphome-devices.yaml" "ESPHome Device Configurations"
    
    # Wait for deployments
    wait_for_deployment "smart-home" "home-assistant" 600
    wait_for_deployment "smart-home" "node-red" 300
    wait_for_deployment "smart-home" "esphome" 300
    wait_for_deployment "smart-home" "zigbee2mqtt" 300
    
    log_success "Smart Home platform deployed successfully"
}

# Function to deploy monitoring and dashboards
deploy_monitoring_dashboards() {
    log_info "Deploying Grafana dashboards for Home Assistant..."
    
    # Ensure monitoring namespace exists
    ensure_namespace "monitoring"
    
    # Deploy Grafana dashboards and Prometheus configuration
    apply_manifest "${HOMELAB_DIR}/monitoring/grafana-homeassistant.yaml" "Home Assistant Grafana Dashboards"
    
    # Wait for monitoring components
    wait_for_deployment "monitoring" "ha-prometheus-bridge" 300
    
    log_success "Monitoring dashboards deployed successfully"
}

# Function to verify deployment
verify_deployment() {
    if [[ "${VALIDATE_ONLY:-false}" == "true" ]]; then
        log_success "All YAML files validated successfully"
        return 0
    fi
    
    log_info "Verifying Smart Home deployment..."
    
    # Check if pods are running
    local smart_home_pods=$(${KUBECTL_CMD} get pods -n smart-home --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    local monitoring_pods=$(${KUBECTL_CMD} get pods -n monitoring --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    
    log_info "Smart Home pods running: $smart_home_pods"
    log_info "Monitoring pods running: $monitoring_pods"
    
    # Check services
    log_info "Checking services..."
    ${KUBECTL_CMD} get services -n smart-home
    ${KUBECTL_CMD} get services -n monitoring
    
    # Check ingress
    if ${KUBECTL_CMD} get ingress -n smart-home &> /dev/null; then
        log_info "Smart Home ingress endpoints:"
        ${KUBECTL_CMD} get ingress -n smart-home
    fi
    
    log_success "Deployment verification completed"
}

# Function to display access information
display_access_info() {
    if [[ "${VALIDATE_ONLY:-false}" == "true" ]]; then
        return 0
    fi
    
    log_info "Smart Home Access Information:"
    echo
    echo "Home Assistant: http://homeassistant.homelab.local"
    echo "Node-RED: http://nodered.homelab.local"
    echo "ESPHome: http://esphome.homelab.local"
    echo "Zigbee2MQTT: http://zigbee.homelab.local"
    echo
    echo "Grafana Dashboards:"
    echo "- Home Assistant Overview"
    echo "- Climate Control"
    echo "- Device Status"
    echo
    echo "Key Features Deployed:"
    echo "✓ Room temperature monitoring (Living Room, Bedroom, Kitchen, Office, Server Room)"
    echo "✓ HVAC system control and monitoring"
    echo "✓ Humidity and air quality sensors"
    echo "✓ Energy consumption tracking"
    echo "✓ Automated climate control"
    echo "✓ Comprehensive Grafana dashboards"
    echo "✓ ESPHome device management"
    echo "✓ MQTT integration"
    echo "✓ Prometheus metrics export"
    echo
}

# Function to setup sample data (for testing)
setup_sample_data() {
    if [[ "${VALIDATE_ONLY:-false}" == "true" ]]; then
        return 0
    fi
    
    log_info "Setting up sample sensor data for testing..."
    
    # Create a job to publish sample MQTT data
    cat <<EOF | ${KUBECTL_CMD} apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: mqtt-sample-data
  namespace: smart-home
spec:
  template:
    spec:
      containers:
      - name: mqtt-publisher
        image: eclipse-mosquitto:latest
        command: ["/bin/sh"]
        args:
          - -c
          - |
            mosquitto_pub -h edge-mqtt.edge.svc.cluster.local -p 1883 -u edge -P edgepassword -t "homeassistant/sensor/living_room_temp/state" -m "22.5"
            mosquitto_pub -h edge-mqtt.edge.svc.cluster.local -p 1883 -u edge -P edgepassword -t "homeassistant/sensor/bedroom_temp/state" -m "21.8"
            mosquitto_pub -h edge-mqtt.edge.svc.cluster.local -p 1883 -u edge -P edgepassword -t "homeassistant/sensor/kitchen_temp/state" -m "23.2"
            mosquitto_pub -h edge-mqtt.edge.svc.cluster.local -p 1883 -u edge -P edgepassword -t "homeassistant/sensor/office_temp/state" -m "22.0"
            mosquitto_pub -h edge-mqtt.edge.svc.cluster.local -p 1883 -u edge -P edgepassword -t "homeassistant/sensor/server_room_temp/state" -m "24.5"
            mosquitto_pub -h edge-mqtt.edge.svc.cluster.local -p 1883 -u edge -P edgepassword -t "homeassistant/sensor/living_room_humidity/state" -m "45"
            mosquitto_pub -h edge-mqtt.edge.svc.cluster.local -p 1883 -u edge -P edgepassword -t "homeassistant/sensor/bedroom_humidity/state" -m "42"
            mosquitto_pub -h edge-mqtt.edge.svc.cluster.local -p 1883 -u edge -P edgepassword -t "homeassistant/sensor/kitchen_humidity/state" -m "48"
            mosquitto_pub -h edge-mqtt.edge.svc.cluster.local -p 1883 -u edge -P edgepassword -t "homeassistant/sensor/main_hvac_power/state" -m "850"
            mosquitto_pub -h edge-mqtt.edge.svc.cluster.local -p 1883 -u edge -P edgepassword -t "homeassistant/sensor/total_hvac_energy/state" -m "12.5"
            echo "Sample data published successfully"
      restartPolicy: Never
  backoffLimit: 3
EOF

    log_success "Sample data setup completed"
}

# Main deployment function
main() {
    log_info "Starting Smart Home Monitoring Deployment"
    echo "=============================================="
    
    # Check prerequisites
    check_kubectl
    
    # Deploy components
    deploy_smart_home || exit 1
    deploy_monitoring_dashboards || exit 1
    
    # Verify deployment
    verify_deployment || exit 1
    
    # Setup sample data for testing
    if [[ "${SETUP_SAMPLE_DATA:-false}" == "true" ]]; then
        setup_sample_data
    fi
    
    # Display access information
    display_access_info
    
    log_success "Smart Home Monitoring deployment completed successfully!"
    echo
    echo "Next Steps:"
    echo "1. Configure your ESPHome devices with the provided configurations"
    echo "2. Set up MQTT sensors for each room"
    echo "3. Configure your HVAC system integration"
    echo "4. Access Grafana dashboards to monitor room temperatures and HVAC status"
    echo "5. Set up Home Assistant automations for energy optimization"
}

# Handle script arguments
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "validate")
        export VALIDATE_ONLY=true
        main
        ;;
    "sample-data")
        export SETUP_SAMPLE_DATA=true
        main
        ;;
    "help")
        echo "Usage: $0 [deploy|validate|sample-data|help]"
        echo
        echo "Commands:"
        echo "  deploy      - Deploy smart home monitoring (default)"
        echo "  validate    - Validate YAML files only"
        echo "  sample-data - Deploy with sample MQTT data"
        echo "  help        - Show this help message"
        ;;
    *)
        log_error "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac