# Nix Best Practices Implementation Plan

**Version:** 1.0  
**Date:** 2026-08-10  
**Based on:** `~/git/nix-best-practices` (26 docs, 15 examples)  
**Target:** opendesk-nix on SCS K3s air-gapped cluster

---

## 🎯 Vision

Transform opendesk-nix from a **K8s manifest generator** into a **complete declarative infrastructure platform** with:

- ✅ Reproducible builds via binary cache
- ✅ Immutable NixOS base OS with A/B OTA
- ✅ Comprehensive integration testing
- ✅ Automated code quality enforcement
- ✅ Air-gap-friendly deployment patterns
- ✅ Security-first design (TPM, Secure Boot, signed images)

---

## 📊 Current State vs Target State

| Capability | Current | Target | Gap |
|------------|---------|--------|-----|
| **Code Quality** | Manual | treefmt + CI checks | ✅ Phase 1 Complete |
| **Binary Cache** | None | Attic on Ceph RGW | 🔴 Critical |
| **Integration Tests** | None | Full service catalog | 🔴 High |
| **NixOS Base** | Traditional Linux | NixOS appliance images | 🔴 High |
| **Disk Provisioning** | Manual | disko + LUKS+TPM | 🔴 High |
| **A/B OTA** | None | systemd-sysupdate | 🟡 Medium |
| **Remote Builders** | None | Dedicated build machine | 🟡 Medium |
| **Secure Boot** | None | lanzaboote + TPM | 🟡 Medium |
| **Secrets** | agenix partial | agenix + LoadCredential= | 🟡 Medium |
| **Runtime State** | Helmfile/ArgoCD | declarative-runtime (OpenTofu) | 🟡 Medium |

---

## 🗓️ Implementation Phases

### Phase 1: Code Quality Foundation (Week 1) ✅ COMPLETE

**Goal:** Automated formatting, linting, and basic tests

**Deliverables:**
- [x] `treefmt.nix` - Formatter configuration
- [x] `flake.nix` - Added `formatter` and `checks` outputs
- [x] `tests/integration.nix` - MariaDB connectivity test
- [x] Documentation roadmap

**Specs:**
```nix
# treefmt.nix contract
{ pkgs, ... }: {
  settings = {
    tree-root-file = "flake.nix";
    formatter = {
      nixfmt = { command, includes };
      statix = { command, options, includes };
      deadnix = { command, options, includes };
      prettier = { command, options, includes };
      shfmt = { command, includes };
      shellcheck = { command, includes, excludes };
    };
  };
}

# checks contract
{
  checks.formatting = treefmt check;
  checks.integration = nixosTest;
}
```

**Tests:**
```bash
# Format check
nix fmt

# Integration test
nix flake check .#integration

# Full CI gate
nix flake check
```

---

### Phase 2: Binary Cache (Week 2) 🔴 PRIORITY

**Goal:** Self-hosted Attic binary cache for air-gapped SCS environment

#### 2.1 Spec: Attic Server

```nix
# modules/attic-server.nix contract
{ config, pkgs, ... }: {
  options = {
    services.attic-server = {
      enable = mkEnableOption "Attic binary cache server";
      listenAddress = mkOption { type = types.str; default = "0.0.0.0"; };
      listenPort = mkOption { type = types.port; default = 8080; };
      cacheDir = mkOption { type = types.path; default = "/var/lib/attic"; };
      signingKey = mkOption { type = types.path; description = "Ed25519 signing key"; };
      storageBackend = mkOption { 
        type = types.enum ["local" "s3" "ceph"]; 
        default = "ceph"; 
      };
    };
  };

  config = {
    # systemd service
    # nginx reverse proxy
    # Ceph RGW integration
    # post-build-hook configuration
  };
}
```

#### 2.2 Spec: Client Configuration

```nix
# modules/binary-cache-client.nix contract
{ config, pkgs, ... }: {
  options = {
    nix.settings = {
      substituters = mkOption {
        type = types.listOf types.str;
        description = "Binary cache URLs (including Attic)";
      };
      trusted-public-keys = mkOption {
        type = types.listOf types.str;
        description = "Attic signing public keys";
      };
    };
  };
}
```

#### 2.3 Spec: Post-Build Hook

```nix
# modules/post-build-hook.nix contract
{ config, pkgs, ... }: {
  options = {
    nix.settings = {
      post-build-hook = mkOption {
        type = types.str;
        description = "Command to upload built paths to Attic";
      };
      post-build-hook-max-jobs = mkOption {
        type = types.int;
        default = 4;
      };
    };
  };
}
```

#### 2.4 Tests

```nix
# tests/attic-server.nix
{ pkgs, ... }: {
  name = "attic-server";

  nodes = {
    attic = { ... }: {
      services.attic-server.enable = true;
      # Ceph RGW backend
    };

    client = { ... }: {
      # Configure as Attic client
      nix.settings.substituters = [ "http://attic:8080" ];
    };
  };

  testScript = ''
    # Start Attic server
    attic.wait_for_unit("attic-server.service")
    
    # Build something on client
    client.succeed("nix build --substituters http://attic:8080 ...")
    
    # Verify path exists in cache
    attic.succeed("attic list cache | grep <hash>")
    
    # Verify client can substitute
    client.succeed("nix-store -q --requisites <path> | wc -l")
  '';
}
```

#### 2.5 Deployment Guide

```bash
# Step 1: Deploy Attic server on SCS network
nix run .#deploy-attic -- --environment scs

# Step 2: Generate signing keys
nix-store --generate-binary-cache-key cache.key cache.pub

# Step 3: Configure all nodes
nixos-rebuild switch --option substituters "http://attic.sc
```

### Phase 3: NixOS Appliance Images (Weeks 3-4) 🔴 HIGH

#### 3.1 Spec: Appliance Image Module

```nix
# modules/appliance-image.nix contract
{ config, pkgs, ... }: {
  options = {
    image = {
      enable = mkEnableOption "Build appliance image";
      format = mkOption { type = types.enum ["ext4" "squashfs" "repart"]; };
      size = mkOption { type = types.size; default = 1024^3; }; # 1GB
      partitions = mkOption {
        type = types.attrs;
        description = "Partition layout (root, boot, nix-store)";
      };
      verityHash = mkOption {
        type = types.str;
        description = "dm-verity hash for read-only verification";
      };
    };
  };

  config = {
    # systemd-repart configuration
    # squashfs for nix-store
    # K3s as NixOS service
    # Ceph CSI configuration
    # HAProxy ingress
  };
}
```

#### 3.2 Spec: disko Configuration

```nix
# disko/configurations/scs-node.nix contract
{ ... }: {
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02"; # GRUB
            };
            esp = {
              size = "512M";
              type = "EF00"; # EFI
              content = { type = "filesystem"; format = "vfat"; };
            };
            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes = {
                  "/root" = { mountPoint = "/"; };
                  "/nix" = { mountPoint = "/nix"; };
                  "/var" = { mountPoint = "/var"; };
                };
              };
            };
          };
        };
      };
    };
  };
}
```

#### 3.3 Spec: NixOS K3s Node Configuration

```nix
# configurations/k3s-node.nix contract
{ config, pkgs, ... }: {
  imports = [
    ./modules/appliance-image.nix
    ./modules/binary-cache.nix
    ./disko/configurations/scs-node.nix
  ];

  options = {
    services.k3s = {
      enable = mkEnableOption "K3s Kubernetes";
      role = mkOption { type = types.enum ["server" "agent"]; };
      clusterToken = mkOption { type = types.str; };
    };
    
    services.ceph = {
      enable = mkEnableOption "Ceph CSI";
      monEndpoints = mkOption { type = types.listOf types.str; };
    };
    
    services.haproxy = {
      enable = mkEnableOption "HAProxy ingress";
      listeners = mkOption { type = types.attrs; };
    };
  };
}
```

#### 3.4 Tests

```nix
# tests/appliance-image.nix
{ pkgs, ... }: {
  name = "k3s-appliance-image";

  nodes = {
    builder = { ... }: {};
    target = { ... }: {
      imports = [ ./configurations/k3s-node.nix ];
    };
  };

  testScript = ''
    # Build image
    builder.succeed("nix build .#image-k3s-node")
    
    # Verify image structure
    builder.succeed("file result/ | grep squashfs")
    
    # Verify partitions
    builder.succeed("partx -l result/ | grep -E 'boot|root|nix'")
    
    # Verify K3s service defined
    builder.succeed("grep -r 'k3s' result/etc/systemd/system/")
  '';
}

# tests/provisioning.nix
{ pkgs, ... }: {
  name = "disko-provisioning";

  nodes = {
    builder = { ... }: {};
    target = { ... }: {};
  };

  testScript = ''
    # Run disko on target
    builder.succeed("nix run nixpkgs#disko -- --disk main /dev/sda")
    
    # Verify partitions created
    target.succeed("lsblk | grep -E 'sda1|sda2|sda3'")
    
    # Verify filesystems mounted
    target.succeed("mount | grep -E '/|/nix'")
  '';
}
```

---

### Phase 4: A/B OTA Updates (Weeks 5-6) 🟡 MEDIUM

#### 4.1 Spec: OTA Update Module

```nix
# modules/ota-updates.nix contract
{ config, pkgs, ... }: {
  options = {
    system.ota = {
      enable = mkEnableOption "A/B OTA updates";
      updateSource = mkOption {
        type = types.str;
        description = "URL or path for update source";
      };
      assessmentTimeout = mkOption {
        type = types.int;
        default = 300; # 5 minutes
      };
      autoRollback = mkOption {
        type = types.bool;
        default = true;
      };
    };
  };

  config = {
    # systemd-sysupdate configuration
    # A/B partition scheme
    # Boot assessment timer
    # Rollback mechanism
  };
}
```

#### 4.2 Spec: systemd-sysupdate Configuration

```nix
# configurations/ota.nix
{ pkgs, ... }: {
  environment.etc."sysupdate.d/update.conf".text = ''
    # A/B partition update configuration
    Source=/var/ota
    Destination=/
    Partition=RootA
    PartitionFallback=RootB
    TimeoutSec=300
    Verify=yes
  '';

  systemd.services.sysupdate = {
    enable = true;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemd-sysupdate update";
    };
    timers = {
      enable = true;
      timerConfig = {
        OnCalendar = "daily";
        RandomizedDelaySec = "1h";
      };
    };
  };
}
```

#### 4.3 Tests

```nix
# tests/ota-updates.nix
{ pkgs, ... }: {
  name = "ab-ota-updates";

  nodes = {
    machine = { ... }: {
      imports = [ ./configurations/ota.nix ];
    };
  };

  testScript = ''
    # Create A/B partitions
    machine.succeed("partx -l /dev/vda | grep -E 'RootA|RootB'")
    
    # Create update source
    machine.succeed("mkdir -p /var/ota")
    
    # Run sysupdate
    machine.succeed("systemd-sysupdate update")
    
    # Verify boot partition switched
    machine.succeed("bootctl | grep 'Current Boot Partition'")
  '';
}
```

---

### Phase 5: Advanced Features (Weeks 7-8) 🟡 MEDIUM

#### 5.1 Remote Builders

```nix
# modules/remote-builder.nix contract
{ config, pkgs, ... }: {
  options = {
    nix.buildMachines = mkOption {
      type = types.listOf types.attrs;
      description = "Remote build machine configurations";
    };
    nix.distributedBuilds = mkOption {
      type = types.bool;
      default = true;
    };
    nix.buildersOptions = mkOption {
      type = types.attrs;
      description = "Per-builder options (maxJobs, speedLevel)";
    };
  };
}
```

#### 5.2 Secure Boot (lanzaboote)

```nix
# modules/secure-boot.nix contract
{ config, pkgs, ... }: {
  options = {
    boot.lanzaboote = {
      enable = mkEnableOption "UEFI Secure Boot with lanzaboote";
      certificateAuthority = mkOption {
        type = types.path;
        description = "CA certificate for signing kernels";
      };
    };
  };
}
```

#### 5.3 Declarative Runtime State

```nix
# modules/declarative-runtime.nix contract
{ config, pkgs, ... }: {
  options = {
    services.<name>.runtime = {
      enable = mkEnableOption "Declarative runtime state";
      resources = mkOption {
        type = types.attrs;
        description = "Resources to manage (Keycloak realms, Grafana dashboards)";
      };
      provider = mkOption {
        type = types.enum ["opentofu" "terraform"];
        default = "opentofu";
      };
    };
  };
}
```

---

## 📋 Contract Summary

### Module Contracts

| Module | Inputs | Outputs | Dependencies |
|--------|--------|---------|--------------|
| `attic-server` | `config`, `pkgs` | systemd service, nginx, Ceph backend | Ceph RGW |
| `binary-cache-client` | `config`, `pkgs` | nix.settings.substituters | Attic server |
| `appliance-image` | `config`, `pkgs` | image derivation, partition layout | disko, systemd-repart |
| `disko-config` | `config`, `pkgs` | disk layout derivation | disko |
| `k3s-node` | `config`, `pkgs` | NixOS configuration | appliance-image, Ceph CSI |
| `ota-updates` | `config`, `pkgs` | systemd-sysupdate config | A/B partitions |
| `remote-builder` | `config`, `pkgs` | nix.buildMachines | SSH builders |
| `secure-boot` | `config`, `pkgs` | lanzaboote configuration | UEFI, TPM |
| `declarative-runtime` | `config`, `pkgs` | OpenTofu state management | OpenTofu, LoadCredential= |

### Test Contracts

| Test | Scope | Duration | CI Gate |
|------|-------|----------|---------|
| `formatting` | Code style | < 10s | ✅ Yes |
| `integration` | MariaDB | ~ 60s | ✅ Yes |
| `attic-server` | Binary cache | ~ 120s | ⏳ Phase 2 |
| `appliance-image` | Image build | ~ 180s | ⏳ Phase 3 |
| `provisioning` | disko | ~ 60s | ⏳ Phase 3 |
| `ota-updates` | A/B switch | ~ 120s | ⏳ Phase 4 |
| `multi-service` | Service catalog | ~ 300s | ⏳ Phase 5 |

---

## 🎯 Success Criteria

### Phase 1 (Week 1) ✅ COMPLETE
- [x] `nix fmt` passes on all files
- [x] `nix flake check` passes
- [x] Integration test passes

### Phase 2 (Week 2)
- [ ] Attic server deployed on SCS network
- [ ] Binary cache serving 80%+ of builds
- [ ] post-build-hook uploading automatically
- [ ] All CI runners using cache

### Phase 3 (Weeks 3-4)
- [ ] NixOS appliance image builds successfully
- [ ] disko provisions test node
- [ ] K3s runs on NixOS appliance
- [ ] Ceph CSI configured
- [ ] HAProxy ingress working

### Phase 4 (Weeks 5-6)
- [ ] A/B partitions configured
- [ ] systemd-sysupdate tested
- [ ] Auto-rollback verified
- [ ] One production node updated via OTA

### Phase 5 (Weeks 7-8)
- [ ] Remote builder configured
- [ ] Secure Boot enabled on test node
- [ ] Keycloak runtime state managed declaratively
- [ ] Full integration test suite passing

---

## 📚 Reference Documents

| Document | Location | Priority |
|----------|----------|----------|
| Code Quality | `~/git/nix-best-practices/docs/15-code-quality.md` | ✅ Phase 1 |
| Binary Cache | `~/git/nix-best-practices/docs/05-binary-cache.md` | 🔴 Phase 2 |
| Integration Tests | `~/git/nix-best-practices/docs/10-integration-testing.md` | 🔴 Phase 2 |
| Disk Provisioning | `~/git/nix-best-practices/docs/07-disk-provisioning.md` | 🔴 Phase 3 |
| Appliance Images | `~/git/nix-best-practices/docs/19-appliance-images.md` | 🔴 Phase 3 |
| Deployment | `~/git/nix-best-practices/docs/11-deployment.md` | 🟡 Phase 4 |
| Secure Boot | `~/git/nix-best-practices/docs/09-secure-boot.md` | 🟡 Phase 5 |
| Secrets | `~/git/nix-best-practices/docs/06-secrets-management.md` | 🟡 Phase 5 |

---

## 🔄 Rollback Plan

If any phase fails:

1. **Phase 1:** Revert treefmt/checks, continue manually
2. **Phase 2:** Fall back to cache.nixos.org via proxy
3. **Phase 3:** Continue with traditional Linux base
4. **Phase 4:** Use manual updates until stable
5. **Phase 5:** Enable features incrementally

---

**Created:** 2026-08-10  
**Author:** opendesk-edu team  
**Review:** Pending team review
