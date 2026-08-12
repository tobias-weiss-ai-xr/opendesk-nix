#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# A/B Updates Deployment Script for SCS Cluster
#
# Deploys A/B update configuration to all cluster nodes

set -euo pipefail

# Configuration
CLUSTER_NODES="${CLUSTER_NODES:-k3s-server-1 k3s-server-2 k3s-agent-1 k3s-agent-2}"
UPDATE_SERVER="${UPDATE_SERVER:-https://attic.scs.opendesk-edu.org}"
SIGNING_KEY="${SIGNING_KEY:-/etc/ab-updates/signing-key.pub}"

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

# Generate signing keys
generate_keys() {
    log_step "Generating A/B update signing keys..."
    
    mkdir -p /etc/ab-updates
    
    if [ ! -f /etc/ab-updates/signing-key ]; then
        # Generate Ed25519 key pair
        openssl genpkey -algorithm Ed25519 -out /etc/ab-updates/signing-key
        openssl pkey -in /etc/ab-updates/signing-key -pubout -out /etc/ab-updates/signing-key.pub
        chmod 600 /etc/ab-updates/signing-key
        log_info "✓ Signing keys generated"
    else
        log_warn "Signing keys already exist"
    fi
}

# Deploy to single node
deploy_to_node() {
    local node="$1"
    
    log_info "Deploying to ${node}..."
    
    # Copy configuration
    ssh root@${node} "mkdir -p /etc/systemd/sysupdate.d"
    
    # Create sysupdate configuration
    cat << EOF | ssh root@${node} "cat > /etc/systemd/sysupdate.d/ab-update.conf"
[Update]
Destination=/
Source=${UPDATE_SERVER}
Verify=true
Mode=atomic
Slots=a

[Partition]
Type=root-a
Priority=100
EOF
    
    # Copy signing key
    scp /etc/ab-updates/signing-key.pub root@${node}:/etc/ab-updates/signing-key.pub
    
    # Enable and start services
    ssh root@${node} << 'INNEREOF'
    systemctl daemon-reload
    systemctl enable ab-rollback-assessment.timer
    systemctl start ab-rollback-assessment.timer
    
    # Verify service
    if systemctl is-active ab-rollback-assessment.timer &> /dev/null; then
        echo "A/B updates enabled on $(hostname)"
    else
        echo "WARNING: A/B updates failed to enable on $(hostname)"
        exit 1
    fi
INNEREOF
    
    log_info "✓ ${node} configured"
}

# Test A/B update on single node
test_ab_update() {
    local node="$1"
    
    log_step "Testing A/B update on ${node}..."
    
    # Check current slot
    local slot
    slot=$(ssh root@${node} "cat /var/lib/ab-updates/active_slot 2>/dev/null || echo 'a'")
    log_info "  Current slot: ${slot}"
    
    # Check update manager
    if ssh root@${node} "which ab-update-manager" &> /dev/null; then
        log_info "  ✓ Update manager installed"
    else
        log_warn "  ✗ Update manager not found"
    fi
    
    # Check timer
    if ssh root@${node} "systemctl is-active ab-rollback-assessment.timer" | grep -q active; then
        log_info "  ✓ Rollback timer active"
    else
        log_warn "  ✗ Rollback timer not active"
    fi
    
    log_info "✓ ${node} test complete"
}

# Main deployment
main() {
    log_info "=========================================="
    log_info "A/B Updates Deployment for SCS Cluster"
    log_info "=========================================="
    log_info ""
    
    # Generate keys
    generate_keys
    
    # Deploy to all nodes
    log_step "Deploying to cluster nodes..."
    
    for node in ${CLUSTER_NODES}; do
        if deploy_to_node "${node}"; then
            test_ab_update "${node}"
        else
            log_error "Failed to deploy to ${node}"
        fi
    done
    
    log_info ""
    log_info "=========================================="
    log_info "Deployment Complete!"
    log_info "=========================================="
    log_info ""
    log_info "Next steps:"
    log_info "1. Monitor rollback timers: systemctl status ab-rollback-assessment.timer"
    log_info "2. Test update: ab-update-manager update ${UPDATE_SERVER}"
    log_info "3. Switch slot: ab-update-manager switch"
    log_info "4. Check status: ab-update-manager status"
    log_info ""
}

main "$@"
