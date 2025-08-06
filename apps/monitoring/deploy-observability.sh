#!/bin/bash

echo "=== Deploying Complete Observability Stack ==="
echo

# Function to wait for deployment
wait_for_deployment() {
    echo -n "Waiting for $1 in namespace $2..."
    kubectl wait --for=condition=available --timeout=300s deployment/$1 -n $2
    if [ $? -eq 0 ]; then
        echo " ✓"
    else
        echo " ✗"
        exit 1
    fi
}

echo "Step 1: Deploy Loki Stack"
echo "========================"
kubectl apply -f loki-stack.yaml
sleep 5

echo -e "\nStep 2: Deploy Promtail"
echo "======================="
kubectl apply -f promtail-config.yaml

echo -e "\nStep 3: Update all deployments with Promtail annotations"
echo "======================================================="
# Add promtail scraping annotation to all deployments
for ns in media auth monitoring home-automation tools identity pihole; do
    kubectl get deployments -n $ns -o name | while read deploy; do
        kubectl patch $deploy -n $ns -p '{"spec":{"template":{"metadata":{"annotations":{"promtail.io/scrape":"true"}}}}}'
    done
done

echo -e "\nStep 4: Deploy ServiceMonitors"
echo "=============================="
kubectl apply -f service-monitors.yaml

echo -e "\nStep 5: Configure Grafana"
echo "========================"
# Add Loki datasource to Grafana
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasource-loki
  namespace: monitoring
data:
  loki-datasource.yaml: |
    apiVersion: 1
    datasources:
    - name: Loki
      type: loki
      access: proxy
      url: http://loki.logging:3100
      isDefault: false
      jsonData:
        timeout: 60
        maxLines: 1000
EOF

# Apply dashboards
kubectl apply -f grafana-dashboards-complete.yaml

# Restart Grafana to pick up new configs
kubectl rollout restart deployment/kube-prometheus-stack-grafana -n monitoring

echo -e "\nStep 6: Apply Alerting Rules"
echo "============================"
kubectl apply -f alerting-rules-complete.yaml

echo -e "\nStep 7: Configure AlertManager"
echo "=============================="
# Update AlertManager config for SMTP
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: alertmanager-main
  namespace: monitoring
stringData:
  alertmanager.yaml: |
    global:
      resolve_timeout: 5m
      smtp_smarthost: 'smtp-relay:25'
      smtp_from: 'alertmanager@mackie.house'
      smtp_require_tls: false
    route:
      group_by: ['alertname', 'cluster', 'service']
      group_wait: 10s
      group_interval: 10s
      repeat_interval: 12h
      receiver: 'default'
      routes:
      - match:
          severity: critical
        receiver: 'critical'
        continue: true
      - match:
          severity: warning
        receiver: 'warning'
      - match:
          severity: info
        receiver: 'info'
    receivers:
    - name: 'default'
      slack_configs:
      - api_url: 'YOUR_SLACK_WEBHOOK_URL'
        channel: '#alerts'
        title: 'Homelab Alert'
        text: '{{ range .Alerts }}{{ .Annotations.summary }}\n{{ end }}'
    - name: 'critical'
      email_configs:
      - to: 'alerts@mackie.house'
        headers:
          Subject: 'CRITICAL: {{ .GroupLabels.alertname }}'
    - name: 'warning'
      email_configs:
      - to: 'alerts@mackie.house'
        headers:
          Subject: 'Warning: {{ .GroupLabels.alertname }}'
        send_resolved: true
    - name: 'info'
      # Info alerts only go to Slack
      slack_configs:
      - api_url: 'YOUR_SLACK_WEBHOOK_URL'
        channel: '#alerts-info'
EOF

# Restart AlertManager
kubectl rollout restart statefulset/alertmanager-main -n monitoring

echo -e "\nStep 8: Verify Deployments"
echo "========================="
wait_for_deployment "loki" "logging"
wait_for_deployment "kube-prometheus-stack-grafana" "monitoring"

echo -e "\nStep 9: Test Metrics Collection"
echo "==============================="
# Test Prometheus targets
echo "Checking Prometheus targets..."
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &
PF_PID=$!
sleep 5
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'
kill $PF_PID

echo -e "\nStep 10: Create Test Dashboards Access"
echo "====================================="
# Get Grafana admin password
GRAFANA_PASS=$(kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d)

echo
echo "=== Observability Stack Deployed ==="
echo
echo "Access Points:"
echo "  - Grafana: https://grafana.mackie.house"
echo "    Username: admin"
echo "    Password: $GRAFANA_PASS"
echo "  - Prometheus: https://prometheus.mackie.house"
echo "  - AlertManager: https://alertmanager.mackie.house"
echo
echo "Dashboards Available:"
echo "  - Homelab Overview"
echo "  - Authentication & Security"
echo "  - Media Stack"
echo "  - Storage & Volumes"
echo "  - Network & DNS"
echo "  - Home Automation"
echo
echo "Log Queries:"
echo "  - All errors: {level=~\"error|critical\"}"
echo "  - Auth logs: {app=\"authelia\"}"
echo "  - Media logs: {app=~\"sonarr|radarr|jellyfin\"}"
echo
echo "Next Steps:"
echo "1. Configure Slack webhook in AlertManager"
echo "2. Set up alert notification channels"
echo "3. Import additional dashboards from grafana.com"
echo "4. Configure log retention policies"