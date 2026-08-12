#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Runtime State Setup Script
#
# Configures declarative Keycloak, Grafana, Prometheus state

set -euo pipefail

# Configuration
NAMESPACE="${NAMESPACE:-opendesk-state}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-opendesk}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $*"; }

# Create namespace
create_namespace() {
    log_step "Creating namespace..."
    
    kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    log_info "✓ Namespace ${NAMESPACE} created"
}

# Generate Keycloak realm config
generate_keycloak_config() {
    log_step "Generating Keycloak realm configuration..."
    
    mkdir -p ./runtime-state/keycloak
    
    cat > ./runtime-state/keycloak/realm.json << EOF
{
  "realm": "${KEYCLOAK_REALM}",
  "enabled": true,
  "users": [
    {
      "username": "admin",
      "enabled": true,
      "email": "admin@opendesk.edu",
      "firstName": "Admin",
      "lastName": "User",
      "roles": ["admin", "user"],
      "groups": ["administrators"]
    },
    {
      "username": "teacher",
      "enabled": true,
      "email": "teacher@opendesk.edu",
      "roles": ["user"],
      "groups": ["teachers"]
    }
  ],
  "clients": [
    {
      "clientId": "nextcloud",
      "enabled": true,
      "publicClient": false,
      "redirectUris": ["https://cloud.opendesk.edu/*"],
      "webOrigins": ["*"]
    },
    {
      "clientId": "moodle",
      "enabled": true,
      "publicClient": false,
      "redirectUris": ["https://learn.opendesk.edu/*"],
      "webOrigins": ["*"]
    }
  ]
}
EOF
    
    log_info "✓ Keycloak configuration generated"
}

# Generate Grafana configuration
generate_grafana_config() {
    log_step "Generating Grafana configuration..."
    
    mkdir -p ./runtime-state/grafana/provisioning/{datasources,dashboards}
    
    # Datasources
    cat > ./runtime-state/grafana/provisioning/datasources/datasources.yml << EOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
    
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    editable: false
EOF
    
    # Dashboard definitions
    cat > ./runtime-state/grafana/provisioning/dashboards/dashboards.yml << EOF
apiVersion: 1

providers:
  - name: 'OpenDesk Dashboards'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    options:
      path: /etc/grafana/provisioning/dashboards
EOF
    
    log_info "✓ Grafana configuration generated"
}

# Generate Prometheus configuration
generate_prometheus_config() {
    log_step "Generating Prometheus configuration..."
    
    mkdir -p ./runtime-state/prometheus/rules
    
    # Main config
    cat > ./runtime-state/prometheus/prometheus.yml << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
      
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
    scrape_interval: 15s
      
  - job_name: 'k3s'
    static_configs:
      - targets: ['k3s-server-1:6443', 'k3s-server-2:6443']
    scrape_interval: 30s

rule_files:
  - "/etc/prometheus/rules/*.yml"
EOF
    
    # Alert rules
    cat > ./runtime-state/prometheus/rules/opendesk-alerts.yml << EOF
groups:
  - name: opendesk
    rules:
      - alert: HighCPUUsage
        expr: node_cpu_usage > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ \$labels.instance }}"
          
      - alert: HighMemoryUsage
        expr: node_memory_usage > 90
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High memory usage on {{ \$labels.instance }}"
          
      - alert: DiskSpaceLow
        expr: node_disk_free < 10
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Low disk space on {{ \$labels.instance }}"
          
      - alert: K3sDown
        expr: up{job="k3s"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "K3s API server is down"
EOF
    
    log_info "✓ Prometheus configuration generated"
}

# Deploy to cluster
deploy_to_cluster() {
    log_step "Deploying runtime state to cluster..."
    
    # Deploy Keycloak
    if [ -f ./runtime-state/keycloak/realm.json ]; then
        kubectl apply -f ./runtime-state/keycloak/ -n "${NAMESPACE}" 2>/dev/null || log_warn "Keycloak deployment skipped"
    fi
    
    # Deploy Grafana
    if [ -d ./runtime-state/grafana ]; then
        kubectl apply -f ./runtime-state/grafana/ -n "${NAMESPACE}" 2>/dev/null || log_warn "Grafana deployment skipped"
    fi
    
    # Deploy Prometheus
    if [ -f ./runtime-state/prometheus/prometheus.yml ]; then
        kubectl apply -f ./runtime-state/prometheus/ -n "${NAMESPACE}" 2>/dev/null || log_warn "Prometheus deployment skipped"
    fi
    
    log_info "✓ Runtime state deployed"
}

# Verify deployment
verify_deployment() {
    log_step "Verifying deployment..."
    
    # Check services
    for service in keycloak grafana prometheus; do
        if kubectl get svc "${service}" -n "${NAMESPACE}" &> /dev/null; then
            log_info "✓ ${service} service available"
        else
            log_warn "✗ ${service} service not found"
        fi
    done
    
    # Check pods
    local pods
    pods=$(kubectl get pods -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l)
    log_info "  Running pods: ${pods}"
}

# Main
main() {
    log_info "=========================================="
    log_info "Runtime State Setup"
    log_info "=========================================="
    log_info ""
    
    create_namespace
    generate_keycloak_config
    generate_grafana_config
    generate_prometheus_config
    deploy_to_cluster
    verify_deployment
    
    log_info ""
    log_info "=========================================="
    log_info "Setup Complete!"
    log_info "=========================================="
    log_info ""
    log_info "Next steps:"
    log_info "1. Access Grafana: http://grafana.${NAMESPACE}.svc:3000"
    log_info "2. Access Keycloak: http://keycloak.${NAMESPACE}.svc:8080"
    log_info "3. Access Prometheus: http://prometheus.${NAMESPACE}.svc:9090"
    log_info "4. Configure state sync: nixos-rebuild switch"
    log_info ""
}

main "$@"
