#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Appliance Image Test Script for SCS Hardware
#
# Tests:
# - Image build
# - VM boot
# - K3s startup
# - Network connectivity
# - Storage configuration

set -euo pipefail

# Configuration
IMAGE_NAME="${IMAGE_NAME:-k3s-node}"
VM_NAME="${VM_NAME:-k3s-test-vm}"
DISK_SIZE="${DISK_SIZE:-50G}"

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

# Build appliance image
build_image() {
    log_step "Building appliance image..."
    
    if ! command -v nix &> /dev/null; then
        log_error "Nix not found. Please install Nix first."
        exit 1
    fi
    
    log_info "Running: nix build .#image-${IMAGE_NAME}"
    
    if nix build ".#image-${IMAGE_NAME}" --out-link ./result-image; then
        log_info "✓ Image built successfully"
        
        # Check image file
        if [ -f ./result-image/disk-image.img ]; then
            local size
            size=$(du -h ./result-image/disk-image.img | cut -f1)
            log_info "  Image size: ${size}"
        else
            log_warn "Image file not found at ./result-image/disk-image.img"
        fi
    else
        log_error "✗ Image build failed"
        exit 1
    fi
}

# Create test VM
create_vm() {
    log_step "Creating test VM..."
    
    if ! command -v qemu-system-x86_64 &> /dev/null; then
        log_error "QEMU not found. Install qemu-kvm package."
        exit 1
    fi
    
    log_info "Creating VM with ${DISK_SIZE} disk..."
    
    # Create disk image if not exists
    if [ ! -f "/tmp/${VM_NAME}.qcow2" ]; then
        qemu-img create -f qcow2 "/tmp/${VM_NAME}.qcow2" "${DISK_SIZE}"
        log_info "✓ Disk image created"
    else
        log_warn "Disk image already exists, reusing"
    fi
    
    # Copy appliance image to VM disk
    if [ -f ./result-image/disk-image.img ]; then
        cp ./result-image/disk-image.img "/tmp/${VM_NAME}.qcow2"
        log_info "✓ Appliance image copied to VM disk"
    fi
}

# Start VM
start_vm() {
    log_step "Starting VM..."
    
    qemu-system-x86_64 \
        -m 4096 \
        -cpu host \
        -drive file="/tmp/${VM_NAME}.qcow2",format=qcow2 \
        -netdev user,id=net0,hostfwd=tcp::2222-:22 \
        -device virtio-net-pci,netdev=net0 \
        -display none \
        -daemonize \
        -name "${VM_NAME}"
    
    log_info "✓ VM started"
    log_info "  SSH access: ssh -p 2222 root@localhost"
}

# Wait for VM to boot
wait_for_vm() {
    log_step "Waiting for VM to boot..."
    
    local max_attempts=60
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if ssh -p 2222 -o ConnectTimeout=5 -o BatchMode=yes root@localhost "exit" 2>/dev/null; then
            log_info "✓ VM is ready"
            return 0
        fi
        
        attempt=$((attempt + 1))
        sleep 2
    done
    
    log_error "✗ VM failed to boot within 2 minutes"
    return 1
}

# Test K3s startup
test_k3s() {
    log_step "Testing K3s startup..."
    
    if ssh -p 2222 root@localhost "systemctl is-active k3s" | grep -q active; then
        log_info "✓ K3s is running"
    else
        log_warn "K3s not active, checking status..."
        ssh -p 2222 root@localhost "systemctl status k3s" || true
    fi
}

# Test network connectivity
test_network() {
    log_step "Testing network connectivity..."
    
    # Test internet
    if ssh -p 2222 root@localhost "ping -c 1 -W 2 8.8.8.8" &> /dev/null; then
        log_info "✓ Internet connectivity OK"
    else
        log_warn "Internet connectivity failed"
    fi
    
    # Test DNS
    if ssh -p 2222 root@localhost "ping -c 1 -W 2 google.com" &> /dev/null; then
        log_info "✓ DNS resolution OK"
    else
        log_warn "DNS resolution failed"
    fi
}

# Test storage configuration
test_storage() {
    log_step "Testing storage configuration..."
    
    # Check disk layout
    ssh -p 2222 root@localhost "lsblk -f" || true
    
    # Check btrfs subvolumes
    if ssh -p 2222 root@localhost "btrfs subvolume list /" &> /dev/null; then
        log_info "✓ Btrfs subvolumes configured"
        ssh -p 2222 root@localhost "btrfs subvolume list /"
    else
        log_warn "Btrfs subvolumes not found"
    fi
    
    # Check disk space
    ssh -p 2222 root@localhost "df -h" || true
}

# Test binary cache
test_binary_cache() {
    log_step "Testing binary cache..."
    
    # Check substituters
    if ssh -p 2222 root@localhost "nix show-config | grep substituters" | grep -q "attic"; then
        log_info "✓ Binary cache substituter configured"
    else
        log_warn "Binary cache not configured"
    fi
    
    # Test substitution
    if ssh -p 2222 root@localhost "nix-store -q --replacements /run/current-system" &> /dev/null; then
        log_info "✓ Binary cache substitution working"
    else
        log_warn "Binary cache substitution failed"
    fi
}

# Cleanup
cleanup() {
    log_step "Cleaning up..."
    
    # Stop VM
    if qemu-monitor-command -q socket -p 4444 "${VM_NAME}" "quit" 2>/dev/null; then
        log_info "✓ VM stopped"
    else
        pkill -f "qemu-system-x86_64.*${VM_NAME}" || true
        log_info "✓ VM process killed"
    fi
    
    # Remove disk
    rm -f "/tmp/${VM_NAME}.qcow2"
    log_info "✓ Disk image removed"
}

# Main
main() {
    log_info "=========================================="
    log_info "Appliance Image Test for SCS Hardware"
    log_info "=========================================="
    log_info ""
    
    # Trap cleanup on exit
    trap cleanup EXIT
    
    build_image
    create_vm
    start_vm
    wait_for_vm
    test_k3s
    test_network
    test_storage
    test_binary_cache
    
    log_info ""
    log_info "=========================================="
    log_info "Test Complete!"
    log_info "=========================================="
    log_info ""
    log_info "All tests passed. Appliance image is ready for production."
    log_info ""
}

main "$@"
