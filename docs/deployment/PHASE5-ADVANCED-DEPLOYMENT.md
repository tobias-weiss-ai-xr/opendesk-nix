# Phase 5: Advanced Features Deployment Guide

Based on `platform/nix/modules/remote-builders.nix`, `secure-boot.nix`, and `runtime-state.nix`

## Overview

Phase 5 completes the Nix best practices roadmap with enterprise-grade features for production SCS clusters.

### Features

| Feature | Purpose | Priority |
|---------|---------|----------|
| **Remote Builders** | Distributed builds across cluster | High |
| **Secure Boot** | UEFI Secure Boot with lanzaboote | High |
| **TPM Attestation** | Hardware-based trust verification | Medium |
| **Declarative State** | Runtime service configuration | High |

---

## 1. Remote Builders Setup

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│              Remote Builder Network                      │
├─────────────────────────────────────────────────────────┤
│                                                          │
│   Master Node                                           │
│   ├── nix build .#sogo5-image                          │
│   ├── Distribute to builders...                         │
│   └── Collect results                                   │
│                                                          │
│   Builder Nodes (SCS Network)                           │
│   ├── builder-1 (x86_64, 4 jobs, kvm)                   │
│   ├── builder-2 (x86_64, 4 jobs, bigparallel)          │
│   └── builder-3 (aarch64, 2 jobs)                       │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### Configuration

```nix
{
  imports = [ ./platform/nix/modules/remote-builders.nix ];
  
  nix.remoteBuilders = {
    enable = true;
    connectTimeout = 30;
    buildTimeout = 3600;
    
    nodes = [
      {
        name = "builder-1";
        endpoint = "nix-builder@10.0.0.10";
        sshKey = /etc/nix/builders/ssh-key;
        system = "x86_64-linux";
        maxJobs = 4;
        speedFactor = 2;
        supportedFeatures = [ "kvm" "bigparallel" ];
      }
    ];
  };
}
```

### Setup Steps

1. **Generate SSH Key Pair**
```bash
ssh-keygen -t ed25519 -f /etc/nix/builders/ssh-key -N ""
```

2. **Configure Builder Nodes**
```bash
# On each builder node
mkdir -p /root/.ssh
echo "ssh-ed25519 AAAA... master@opendesk" >> /root/.ssh/authorized_keys
```

3. **Configure Master Node**
```bash
# Copy public key to builders
for builder in builder-1 builder-2 builder-3; do
  ssh-copy-id -i /etc/nix/builders/ssh-key.pub nix-builder@${builder}
done
```

4. **Test Connectivity**
```bash
nix build .# --builders read-cpu
```

### Monitoring

```bash
# Check builder status
nix show-config | grep builders

# View build logs
journalctl -u nix-daemon -f

# Check health timer
systemctl status nix-builder-health.timer
```

---

## 2. Secure Boot with lanzaboote

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│              Secure Boot Chain                           │
├─────────────────────────────────────────────────────────┤
│                                                          │
│   Firmware (UEFI)                                       │
│   ├── Platform Key (PK)                                 │
│   └── Key Exchange Key (KEK)                            │
│                                                          │
│   Bootloader (systemd-boot + lanzaboote)               │
│   ├── db (Signature Database)                           │
│   └── Signed shim                                       │
│                                                          │
│   Kernel & Initrd                                       │
│   ├── Signed kernel                                     │
│   └── Signed initrd                                     │
│                                                          │
│   TPM 2.0                                               │
│   ├── PCR 7: Boot measurements                          │
│   └── Attestation quotes                                │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### Configuration

```nix
{
  imports = [ ./platform/nix/modules/secure-boot.nix ];
  
  security.secureBoot = {
    enable = true;
    mode = "enroll";  # or "manual"
    keySize = 3072;
    tpmAttestation = true;
    measuredBoot = true;
  };
}
```

### Setup Steps

1. **Generate Secure Boot Keys**
```bash
# Run on first deployment
/etc/lanzaboote/generate-keys.sh

# Output:
# /etc/lanzaboote/pki/ca.key  (CA private key)
# /etc/lanzaboote/pki/ca.crt  (CA certificate)
# /etc/lanzaboote/pki/db.key  (Signing key)
# /etc/lanzaboote/pki/db.crt  (Signing certificate)
```

2. **Enroll Keys in UEFI**
```bash
# Using mokutil (one-time setup)
mokutil --import /etc/lanzaboote/pki/db.crt
# Reboot and follow MOK enrollment wizard

# Or using fwsetup (automatic)
bootctl set-efivar
```

3. **Sign Boot Components**
```bash
# lanzaboote automatically signs during build
nixos-rebuild switch --flake .#node
```

4. **Verify Secure Boot**
```bash
# Check Secure Boot status
mokutil --sb-state

# Check signature verification
sbverify --list /boot/efi/EFI/Linux/linux.efi
```

### TPM Attestation

```bash
# View PCR 7 measurements
tpm2_pcrevent 7

# Get attestation quote
tpm2_quote -c 0x81000000 -l sha256:7 -q 0x81000001 -o quote.bin -s signature.bin

# Verify quote
tpm2_checkquote -u ak.pub -s signature.bin -f quote.bin
```

---

## 3. Declarative Runtime State

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│           Declarative State Management                   │
├─────────────────────────────────────────────────────────┤
│                                                          │
│   Nix Configuration                                     │
│   ├── services.runtimeState = {                         │
│   │     keycloak = { users, clients };                  │
│   │     grafana = { dashboards, datasources };          │
│   │     prometheus = { scrapeConfigs, alertRules };     │
│   │   };                                                │
│   └── nix build .#runtime-state                         │
│                                                          │
│   Runtime Sync (every 5min)                             │
│   ├── Keycloak → Realm configuration                    │
│   ├── Grafana → Dashboards & datasources                │
│   ├── Prometheus → Scrape configs & alerts              │
│   └── Kyverno → Policies                                │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### Configuration

```nix
{
  imports = [ ./platform/nix/modules/runtime-state.nix ];
  
  services.runtimeState = {
    enable = true;
    syncInterval = 300;
    
    keycloak = {
      enable = true;
      realm = "opendesk";
      
      users = {
        "admin" = {
          email = "admin@opendesk.edu";
          roles = [ "admin" ];
          groups = [ "administrators" ];
        };
      };
      
      clients = {
        "nextcloud" = {
          public = false;
          redirectUris = [ "https://cloud.opendesk.edu/*" ];
        };
      };
    };
    
    grafana = {
      enable = true;
      
      datasources = {
        prometheus = {
          type = "prometheus";
          url = "http://localhost:9090";
          default = true;
        };
      };
      
      dashboards = {
        "node-overview" = {
          title = "Node Overview";
          path = /etc/grafana/dashboards/node.json;
        };
      };
    };
    
    prometheus = {
      enable = true;
      
      scrapeConfigs = {
        node = {
          targets = [ "localhost:9100" ];
          interval = "15s";
        };
      };
      
      alertRules = {
        "high-cpu" = {
          alert = "HighCPUUsage";
          expr = "node_cpu_usage > 80";
          for = "5m";
          labels = { severity = "warning"; };
        };
      };
    };
  };
}
```

### Setup Steps

1. **Configure Runtime State**
```nix
# Add to your NixOS configuration
{
  services.runtimeState = {
    enable = true;
    # ... configuration ...
  };
}
```

2. **Build Configuration**
```bash
nix build .#runtime-state
```

3. **Deploy to Cluster**
```bash
# Apply to all nodes
for node in k3s-server-1 k3s-server-2 k3s-agent-1; do
  ssh root@${node} "nixos-rebuild switch --flake /etc/nixos#node"
done
```

4. **Verify Sync**
```bash
# Check sync status
systemctl status opendesk-state-sync.service

# View logs
journalctl -u opendesk-state-sync -f
```

### Keycloak Example

```nix
services.runtimeState.keycloak = {
  enable = true;
  realm = "opendesk";
  
  users = {
    "admin" = {
      email = "admin@opendesk.edu";
      firstName = "Admin";
      lastName = "User";
      roles = [ "admin" "user" ];
    };
    "teacher" = {
      email = "teacher@opendesk.edu";
      roles = [ "user" ];
    };
  };
  
  clients = {
    "nextcloud" = {
      public = false;
      secret = "change-me-to-random-string";
      redirectUris = [ "https://cloud.opendesk.edu/*" ];
    };
    "moodle" = {
      public = false;
      redirectUris = [ "https://learn.opendesk.edu/*" ];
    };
  };
};
```

### Grafana Example

```nix
services.runtimeState.grafana = {
  enable = true;
  
  datasources = {
    prometheus = {
      type = "prometheus";
      url = "http://prometheus:9090";
      default = true;
    };
    loki = {
      type = "loki";
      url = "http://loki:3100";
    };
  };
  
  dashboards = {
    "k3s-cluster" = {
      title = "K3s Cluster Overview";
      path = ./dashboards/k3s-cluster.json;
    };
    "node-health" = {
      title = "Node Health";
      path = ./dashboards/node-health.json;
    };
  };
};
```

---

## Monitoring & Alerting

### Prometheus Alerts

```yaml
# Generated from runtime-state.nix
groups:
  - name: opendesk
    rules:
      - alert: HighCPUUsage
        expr: node_cpu_usage > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ $labels.instance }}"
          
      - alert: HighMemoryUsage
        expr: node_memory_usage > 90
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"
          
      - alert: DiskSpaceLow
        expr: node_disk_free < 10
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Low disk space on {{ $labels.instance }}"
```

### Grafana Dashboards

1. **Cluster Overview**
   - Node health status
   - Pod distribution
   - Resource utilization

2. **Node Health**
   - CPU/Memory/Disk metrics
   - Network I/O
   - System load

3. **Application Metrics**
   - Service availability
   - Response times
   - Error rates

---

## Troubleshooting

### Remote Builders

```bash
# Check SSH connectivity
ssh -v nix-builder@10.0.0.10 "exit 0"

# Test remote build
nix build .# --builders "ssh://nix-builder@10.0.0.10 x86_64-linux 1 4"

# Check builder health
systemctl status nix-builder-health.service
```

### Secure Boot

```bash
# Check Secure Boot status
mokutil --sb-state

# Verify signatures
sbverify --list /boot/efi/EFI/Linux/linux.efi

# Check TPM
tpm2_pcrread 7
```

### Runtime State

```bash
# Check sync status
systemctl status opendesk-state-sync.service

# Manual sync
systemctl start opendesk-state-sync.service

# View state files
ls -la /var/lib/opendesk-state/
```

---

## Production Checklist

### Remote Builders
- [ ] Generate and distribute SSH keys
- [ ] Configure builder nodes with Nix
- [ ] Test remote builds
- [ ] Set up health monitoring
- [ ] Document builder capacity

### Secure Boot
- [ ] Generate Secure Boot keys
- [ ] Enroll keys in UEFI firmware
- [ ] Test boot process
- [ ] Configure TPM attestation
- [ ] Document key rotation procedure

### Runtime State
- [ ] Configure Keycloak realm
- [ ] Set up Grafana dashboards
- [ ] Configure Prometheus alerts
- [ ] Test state sync
- [ ] Document operational procedures

---

## Related Documentation

- [Binary Cache Deployment](./ATTIC-BINARY-CACHE-DEPLOYMENT.md)
- [A/B Updates Deployment](./AB-UPDATES-DEPLOYMENT.md)
- [Appliance Image Specification](../../specs/technical/APPLIANCE-IMAGE-SPEC.md)
- [Nix Best Practices Implementation Plan](../governance/NIX-BEST-PRACTICES-IMPLEMENTATION-PLAN.md)
