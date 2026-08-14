#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# A/B Update Manager
# Manages atomic A/B updates with automatic rollback
#
# Usage:
#   ab-update-manager status       # Show current slot and status
#   ab-update-manager update URL   # Download and prepare update
#   ab-update-manager switch       # Switch to inactive slot
#   ab-update-manager rollback     # Manually rollback to previous slot

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_DIR="/etc/systemd/sysupdate.d"
readonly STATE_DIR="/var/lib/ab-updates"
readonly LOG_FILE="/var/log/ab-update.log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "${YELLOW}$*${NC}"; }
log_error() { log "ERROR" "${RED}$*${NC}"; }

# Get current active slot
get_active_slot() {
    if [ -f "${STATE_DIR}/active_slot" ]; then
        cat "${STATE_DIR}/active_slot"
    else
        echo "a"
    fi
}

# Get inactive slot
get_inactive_slot() {
    local active
    active=$(get_active_slot)
    if [ "$active" = "a" ]; then
        echo "b"
    else
        echo "a"
    fi
}

# Check boot status
check_boot_status() {
    log_info "Checking boot status..."

    # Check if system booted successfully
    if systemctl is-active --quiet multi-user.target; then
        log_info "${GREEN}✓ System booted successfully${NC}"
        return 0
    else
        log_warn "${YELLOW}⚠ System may have failed to boot${NC}"
        return 1
    fi
}

# Show status
show_status() {
    echo "=== A/B Update Status ==="
    echo ""
    echo "Active Slot:     $(get_active_slot)"
    echo "Inactive Slot:   $(get_inactive_slot)"
    echo ""

    # Show partition information
    if command -v systemctl &>/dev/null; then
        echo "Partition Status:"
        systemctl list-partitions 2>/dev/null || echo "  (partition info unavailable)"
    fi

    echo ""
    echo "Update State:"
    if [ -f "${STATE_DIR}/pending_update" ]; then
        echo "  Status: ${YELLOW}Update pending${NC}"
        cat "${STATE_DIR}/pending_update"
    else
        echo "  Status: ${GREEN}Up to date${NC}"
    fi

    echo ""
}

# Download update
download_update() {
    local url="$1"
    local inactive
    inactive=$(get_inactive_slot)

    log_info "Downloading update from ${url}..."
    log_info "Target slot: ${inactive}"

    # Create state directory
    mkdir -p "${STATE_DIR}"

    # Download update using sysupdate
    if command -v systemd-sysupdate &>/dev/null; then
        systemd-sysupdate download "${url}"
        echo "${url}" >"${STATE_DIR}/pending_update"
        echo "${inactive}" >"${STATE_DIR}/pending_slot"
        log_info "${GREEN}✓ Update downloaded successfully${NC}"
    else
        log_error "systemd-sysupdate not found"
        return 1
    fi
}

# Switch to inactive slot
switch_slot() {
    local inactive
    inactive=$(get_inactive_slot)

    log_info "Switching to slot ${inactive}..."

    # Create boot entry for inactive slot
    if command -v systemd-sysupdate &>/dev/null; then
        systemd-sysupdate switch "${inactive}"
        echo "${inactive}" >"${STATE_DIR}/active_slot"
        log_info "${GREEN}✓ Slot switched. Reboot required.${NC}"
    else
        log_error "systemd-sysupdate not found"
        return 1
    fi
}

# Rollback to previous slot
rollback() {
    local previous
    previous=$(get_active_slot)

    log_info "Rolling back to slot ${previous}..."

    if command -v systemd-sysupdate &>/dev/null; then
        systemd-sysupdate switch "${previous}"
        log_info "${GREEN}✓ Rollback initiated. Reboot required.${NC}"
    else
        log_error "systemd-sysupdate not found"
        return 1
    fi
}

# Verify signatures
verify_update() {
    local signing_key="$1"

    log_info "Verifying update signatures..."

    if [ ! -f "$signing_key" ]; then
        log_error "Signing key not found: ${signing_key}"
        return 1
    fi

    # Verify using systemd-sysupdate verify
    if command -v systemd-sysupdate &>/dev/null; then
        systemd-sysupdate verify --key="$signing_key"
        log_info "${GREEN}✓ Update verified${NC}"
    else
        log_error "systemd-sysupdate not found"
        return 1
    fi
}

# Main command handler
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
    status)
        show_status
        ;;
    update)
        if [ -z "${1:-}" ]; then
            log_error "Usage: $0 update <URL>"
            exit 1
        fi
        download_update "$1"
        ;;
    switch)
        switch_slot
        ;;
    rollback)
        rollback
        ;;
    verify)
        if [ -z "${1:-}" ]; then
            log_error "Usage: $0 verify <SIGNING_KEY>"
            exit 1
        fi
        verify_update "$1"
        ;;
    help | *)
        echo "A/B Update Manager"
        echo ""
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  status              Show current slot and status"
        echo "  update <URL>        Download and prepare update"
        echo "  switch              Switch to inactive slot (reboot required)"
        echo "  rollback            Rollback to previous slot (reboot required)"
        echo "  verify <KEY>        Verify update signatures"
        echo "  help                Show this help message"
        ;;
    esac
}

main "$@"
