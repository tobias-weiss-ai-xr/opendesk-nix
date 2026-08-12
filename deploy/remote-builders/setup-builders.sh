#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Remote Builders Setup Script for SCS Cluster
#
# Configures distributed build nodes across the cluster

set -euo pipefail

# Configuration
BUILDER_NODES="${BUILDER_NODES:-builder-1 builder-2 builder-3}"
MASTER_NODE="${MASTER_NODE:-k3s-server-1}"
BUILDER_USER="${BUILDER_USER:-nix-builder}"

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

# Generate SSH key for builders
generate_ssh_key() {
    log_step "Generating SSH key for builders..."
    
    mkdir -p /etc/nix/builders
    
    if [ ! -f /etc/nix/builders/ssh-key ]; then
        ssh-keygen -t ed25519 -f /etc/nix/builders/ssh-key -N "" -C "nix-builders@opendesk"
        log_info "✓ SSH key generated"
    else
        log_warn "SSH key already exists"
    fi
}

# Configure builder node
configure_builder() {
    local node="$1"
    
    log_info "Configuring builder ${node}..."
    
    # Create builder user
    ssh root@${node} << 'INNEREOF'
    if ! id ${BUILDER_USER} &> /dev/null; then
        useradd -m -s /bin/bash ${BUILDER_USER}
        echo "${BUILDER_USER} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/${BUILDER_USER}
        chmod 440 /etc/sudoers.d/${BUILDER_USER}
    fi
    
    # Create .ssh directory
    mkdir -p /home/${BUILDER_USER}/.ssh
    chmod 700 /home/${BUILDER_USER}/.ssh
INNEREOF
    
    # Copy public key to builder
    scp /etc/nix/builders/ssh-key.pub root@${node}:/tmp/builder-key.pub
    
    # Append to authorized_keys
    ssh root@${node} "cat /tmp/builder-key.pub >> /home/${BUILDER_USER}/.ssh/authorized_keys"
    chmod 600 /home/${BUILDER_USER}/.ssh/authorized_keys
    
    # Install Nix on builder
    ssh root@${node} << 'INNEREOF'
    if ! command -v nix &> /dev/null; then
        sh <(curl -L https://nixos.org/nix/install) --daemon
        source /etc/profile
    fi
INNEREOF
    
    log_info "✓ ${node} configured"
}

# Configure master node with builders
configure_master() {
    log_step "Configuring master node with remote builders..."
    
    # Create builders configuration
    cat > /etc/nix/builders << EOF
# Remote builders for distributed builds
$(for node in ${BUILDER_NODES}; do
    echo "nix-builder@${node} x86_64-linux 2 4 kvm,bigparallel"
done)
EOF
    
    # Copy to Nix config
    cp /etc/nix/builders /etc/nix/machines
    
    # Restart Nix daemon
    systemctl restart nix-daemon
    
    log_info "✓ Master node configured"
}

# Test remote builders
test_builders() {
    log_step "Testing remote builders..."
    
    for node in ${BUILDER_NODES}; do
        log_info "Testing ${node}..."
        
        # Test SSH connectivity
        if ssh -o ConnectTimeout=10 -o BatchMode=yes ${BUILDER_USER}@${node} "exit" 2>/dev/null; then
            log_info "  ✓ SSH connectivity OK"
        else
            log_error "  ✗ SSH connectivity failed"
            continue
        fi
        
        # Test Nix installation
        if ssh ${BUILDER_USER}@${node} "nix --version" &> /dev/null; then
            log_info "  ✓ Nix installed: $(ssh ${BUILDER_USER}@${node} 'nix --version')"
        else
            log_warn "  ✗ Nix not found"
        fi
        
        # Test remote build
        if nix build --builders "ssh://${BUILDER_USER}@${node} x86_64-linux 2 4 kvm" hello &> /dev/null; then
            log_info "  ✓ Remote build successful"
        else
            log_warn "  ✗ Remote build failed"
        fi
    done
}

# Generate flake.nix snippet
generate_flake_snippet() {
    log_step "Generating flake.nix snippet..."
    
    cat > ./remote-builders-config.nix << EOF
# Remote builders configuration for flake.nix
# Add this to your NixOS configuration:

{
  nix.remoteBuilders = {
    enable = true;
    connectTimeout = 30;
    buildTimeout = 3600;
    
    nodes = [
$(for node in ${BUILDER_NODES}; do
    cat << EOFNODE
      {
        name = "${node}";
        endpoint = "${BUILDER_USER}@${node}";
        sshKey = /etc/nix/builders/ssh-key;
        system = "x86_64-linux";
        maxJobs = 4;
        speedFactor = 2;
        supportedFeatures = [ "kvm" "bigparallel" ];
      }
EOFNODE
done)
    ];
  };
}
EOF
    
    log_info "✓ Configuration generated: ./remote-builders-config.nix"
}

# Main
main() {
    log_info "=========================================="
    log_info "Remote Builders Setup for SCS Cluster"
    log_info "=========================================="
    log_info ""
    
    # Generate SSH key
    generate_ssh_key
    
    # Configure builder nodes
    log_step "Configuring builder nodes..."
    
    for node in ${BUILDER_NODES}; do
        configure_builder "${node}"
    done
    
    # Configure master
    configure_master
    
    # Test builders
    test_builders
    
    # Generate config snippet
    generate_flake_snippet
    
    log_info ""
    log_info "=========================================="
    log_info "Setup Complete!"
    log_info "=========================================="
    log_info ""
    log_info "Next steps:"
    log_info "1. Review configuration: ./remote-builders-config.nix"
    log_info "2. Test builds: nix build .# --builders read-cpu"
    log_info "3. Monitor builds: journalctl -u nix-daemon -f"
    log_info ""
}

main "$@"
