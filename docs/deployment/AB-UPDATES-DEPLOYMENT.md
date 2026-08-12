# A/B OTA Updates Deployment Guide

Based on `platform/nix/modules/ab-updates.nix` and `scripts/update-manager/ab-update-manager.sh`

## Overview

A/B (seamless) updates provide atomic, rollback-capable system updates using `systemd-sysupdate`. This is critical for production K3s clusters where uptime is essential.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    A/B Update Flow                       │
├─────────────────────────────────────────────────────────┤
│                                                          │
│   1. Download Update → Slot B (inactive)                 │
│   2. Verify Signatures → GPG/Ed25519                     │
│   3. Switch Boot Entry → systemd-boot                      │
│   4. Reboot → Boot from Slot B                           │
│   5. Assess Boot → 5min timer                            │
│   6. Success → Slot B becomes active                     │
│   6. Failure → Auto-rollback to Slot A                   │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

## Prerequisites

- NixOS 24.11+
- systemd-sysupdate package
- UEFI with systemd-boot
- Two root partitions (A and B slots)

## Deployment Steps

### 1. Configure A/B Updates

Add to your NixOS configuration:

```nix
{
  imports = [ ./platform/nix/modules/ab-updates.nix ];
  
  services.abUpdates = {
    enable = true;
    slots = "a";  # Start with slot A
    updateSource = "https://updates.opendesk-edu.org/24.11";
    rollbackTimeout = 300;  # 5 minutes
    verifySignatures = true;
    signingKey = /etc/ab-updates/signing-key.pub;
  };
}
```

### 2. Partition Setup

Ensure your disk has two root partitions:

```bash
# Check current partitions
lsblk -f

# Expected output:
# /dev/sda1  EF00  ESP
# /dev/sda2       root-a
# /dev/sda3       root-b
```

### 3. Generate Signing Keys

```bash
# Generate Ed25519 key pair
systemd-sysupdate genkey /etc/ab-updates/signing-key

# Export public key for verification
systemd-sysupdate pubkey /etc/ab-updates/signing-key /etc/ab-updates/signing-key.pub

# Secure private key
chmod 600 /etc/ab-updates/signing-key
```

### 4. Configure Update Server

For self-hosted updates, set up a simple HTTP server:

```bash
# Serve Nix store as update source
python3 -m http.server 8080 --directory /nix/store
```

For production, use:
- Ceph RGW with static website hosting
- Attic server (see `ATTIC-BINARY-CACHE-DEPLOYMENT.md`)
- CDN with signed URLs

### 5. Deploy to Cluster

```bash
# Apply configuration to all nodes
for node in k3s-server-1 k3s-server-2 k3s-agent-1; do
    ssh root@${node} "nixos-rebuild switch --flake /etc/nixos#node"
done
```

## Usage

### Check Status

```bash
ab-update-manager status

# Output:
# === A/B Update Status ===
# Active Slot:     a
# Inactive Slot:   b
# Partition Status:
#   /dev/sda2  root-a  (active)
#   /dev/sda3  root-b  (inactive)
# Update State:
#   Status: Up to date
```

### Download Update

```bash
ab-update-manager update https://updates.opendesk-edu.org/24.11

# Output:
# [INFO] Downloading update from https://updates.opendesk-edu.org/24.11...
# [INFO] Target slot: b
# [INFO] ✓ Update downloaded successfully
```

### Verify Signatures

```bash
ab-update-manager verify /etc/ab-updates/signing-key.pub

# Output:
# [INFO] Verifying update signatures...
# [INFO] ✓ Update verified
```

### Switch to New Slot

```bash
ab-update-manager switch

# Output:
# [INFO] Switching to slot b...
# [INFO] ✓ Slot switched. Reboot required.

# Reboot
reboot
```

### Manual Rollback

```bash
ab-update-manager rollback

# Output:
# [INFO] Rolling back to slot a...
# [INFO] ✓ Rollback initiated. Reboot required.
```

## Automatic Rollback

The `ab-rollback-assessment.timer` runs every hour to check boot health:

```bash
# Check timer status
systemctl status ab-rollback-assessment.timer

# Check last assessment
systemctl status ab-rollback-assessment.service
```

If boot fails within `rollbackTimeout` (default 5 minutes), the system automatically reverts to the previous slot.

## Monitoring

### Logs

```bash
# View A/B update logs
journalctl -u ab-rollback-assessment -f
cat /var/log/ab-update.log
```

### Metrics

Export Prometheus metrics:

```bash
# Active slot
cat /var/lib/ab-updates/active_slot

# Pending update
cat /var/lib/ab-updates/pending_update 2>/dev/null || echo "none"
```

## Troubleshooting

### Update Failed to Download

```bash
# Check network connectivity
ping -c 3 updates.opendesk-edu.org

# Check disk space
df -h /var/lib/ab-updates

# Retry download
ab-update-manager update <URL>
```

### Boot Failed After Update

```bash
# System should auto-rollback within 5 minutes
# Check rollback status
systemctl status ab-rollback-assessment.service

# Manual rollback if needed
ab-update-manager rollback
reboot
```

### Partition Not Found

```bash
# Check partition layout
lsblk -f

# If missing, recreate with disko:
nix run nixpkgs#disko -- --disk main /dev/sda
```

## Security Considerations

1. **Signature Verification**: Always enable `verifySignatures = true`
2. **Key Management**: Protect private signing keys (HSM recommended)
3. **Update Source**: Use HTTPS with certificate pinning
4. **Rollback Timeout**: Set appropriate timeout for your workload (300s default)

## Production Checklist

- [ ] Generate and secure signing keys
- [ ] Configure update server (Ceph RGW/Attic)
- [ ] Test on staging cluster first
- [ ] Set up monitoring alerts
- [ ] Document rollback procedures
- [ ] Train operations team
- [ ] Run disaster recovery drill

## Related Documentation

- [Binary Cache Deployment](./ATTIC-BINARY-CACHE-DEPLOYMENT.md)
- [Appliance Image Specification](../../specs/technical/APPLIANCE-IMAGE-SPEC.md)
- [Nix Best Practices Implementation Plan](../governance/NIX-BEST-PRACTICES-IMPLEMENTATION-PLAN.md)
