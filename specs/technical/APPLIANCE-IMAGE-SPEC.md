# NixOS Appliance Image Specification

**Version:** 1.0  
**Date:** 2026-08-10  
**Status:** Draft - Phase 3 Implementation  
**Based on:** `~/git/nix-best-practices/docs/19-appliance-images.md`

---

## 1. Overview

### 1.1 Purpose

Create immutable, reproducible NixOS appliance images for SCS K3s nodes that:

- Provide a read-only, verifiable base OS
- Support A/B OTA updates with automatic rollback
- Include K3s, Ceph CSI, and HAProxy as NixOS services
- Enable declarative disk provisioning with disko

### 1.2 Scope

- systemd-repart partition layout
- Squashfs root filesystem with dm-verity
- A/B slot configuration
- K3s integration
- disko provisioning templates

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    NixOS Appliance Image                        │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Partition Layout (disko)                               │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐  │   │
│  │  │   Boot   │ │   ESP    │ │  Root A  │ │  Root B  │  │   │
│  │  │   1M     │ │  512M    │ │  50%     │ │  50%     │  │   │
│  │  │  (BIOS)  │ │  (UEFI)  │ │ (squash) │ │ (squash) │  │   │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘  │   │
│  │                         │                              │   │
│  │                         ▼                              │   │
│  │  ┌─────────────────────────────────────────────────┐  │   │
│  │  │  dm-verity verification                          │  │   │
│  │  │  Hash: <sha256>                                  │  │   │
│  │  └─────────────────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  NixOS Configuration                                    │   │
│  │  ├── services.k3s (Kubernetes)                          │   │
│  │  ├── services.ceph-csi (Storage)                        │   │
│  │  ├── services.haproxy (Ingress)                         │   │
│  │  ├── services.attic-client (Binary cache)               │   │
│  │  └── system.ota (A/B updates)                           │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Specifications

### 3.1 Appliance Image Module

**File:** `modules/appliance-image.nix`

**Interface:**
```nix
{
  config,
  pkgs,
  lib,
  ...
}: {
  options = {
    image = {
      enable = lib.mkEnableOption "Build appliance image";
      
      format = lib.mkOption {
        type = lib.types.enum ["ext4" "squashfs" "repart"];
        default = "repart";
        description = "Image format type";
      };
      
      size = lib.mkOption {
        type = lib.types.size;
        default = 10737418240; # 10GB
        description = "Total image size in bytes";
      };
      
      partitions = lib.mkOption {
        type = lib.types.attrs;
        description = "Partition definitions";
        default = {
          boot = { size = "1M"; type = "EF02"; };
          esp = { size = "512M"; type = "EF00"; };
          rootA = { size = "50%"; type = "0FC63DAF-8483-4772-8E79-3D69D8477DE4"; };
          rootB = { size = "50%"; type = "0FC63DAF-8483-4772-8E79-3D69D8477DE4"; };
        };
      };
      
      verityHash = lib.mkOption {
        type = lib.types.str;
        description = "dm-verity hash for verification";
      };
      
      outputDir = lib.mkOption {
        type = lib.types.path;
        default = ./result;
        description = "Output directory for image files";
      };
    };
  };

  config = {
    # systemd-repart definitions
    # squashfs build configuration
    # dm-verity setup
    # A/B boot configuration
  };
}
```

### 3.2 disko Configuration

**File:** `disko/configurations/k3s-node.nix`

**Interface:**
```nix
{
  config,
  pkgs,
  lib,
  ...
}: {
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = lib.mkOption {
          type = lib.types.str;
          description = "Device path (e.g., /dev/sda)";
        };
        
        content = {
          type = "gpt";
          
          partitions = {
            boot = {
              size = "1M";
              type = "EF02";
              priority = 1;
            };
            
            esp = {
              size = "512M";
              type = "EF00";
              priority = 2;
              content = {
                type = "filesystem";
                format = "vfat";
                mountPoint = "/boot/efi";
              };
            };
            
            root = {
              size = "100%";
              priority = 3;
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ]; # Override existing partition
                
                subvolumes = {
                  "/root" = {
                    mountPoint = "/";
                    mountOptions = [ "subvol=root" "defaults" ];
                  };
                  
                  "/nix" = {
                    mountPoint = "/nix";
                    mountOptions = [ "subvol=nix" "noatime" "compress=zstd" ];
                  };
                  
                  "/var" = {
                    mountPoint = "/var";
                    mountOptions = [ "subvol=var" "defaults" ];
                  };
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

### 3.3 K3s Node Configuration

**File:** `configurations/k3s-node.nix`

**Interface:**
```nix
{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./modules/appliance-image.nix
    ./modules/binary-cache.nix
    ./disko/configurations/k3s-node.nix
  ];

  options = {
    services.k3s = {
      enable = lib.mkEnableOption "K3s Kubernetes";
      
      role = lib.mkOption {
        type = lib.types.enum ["server" "agent"];
        default = "server";
        description = "K3s node role";
      };
      
      clusterToken = lib.mkOption {
        type = lib.types.str;
        description = "Cluster join token";
      };
      
      extraOptions = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = "Additional K3s command-line options";
      };
    };
    
    services.ceph = {
      enable = lib.mkEnableOption "Ceph CSI";
      
      monEndpoints = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "Ceph monitor endpoints";
      };
      
      cephUser = lib.mkOption {
        type = lib.types.str;
        default = "client.admin";
      };
    };
    
    services.haproxy = {
      enable = lib.mkEnableOption "HAProxy ingress";
      
      listeners = lib.mkOption {
        type = lib.types.attrs;
        description = "HAProxy listener configurations";
      };
    };
  };

  config = {
    # K3s service configuration
    # Ceph CSI setup
    # HAProxy configuration
    # Network configuration
    # Security hardening
  };
}
```

### 3.4 A/B OTA Module

**File:** `modules/ota-updates.nix`

**Interface:**
```nix
{
  config,
  pkgs,
  lib,
  ...
}: {
  options = {
    system.ota = {
      enable = lib.mkEnableOption "A/B OTA updates";
      
      updateSource = lib.mkOption {
        type = lib.types.str;
        description = "URL or path for update source";
      };
      
      assessmentTimeout = lib.mkOption {
        type = lib.types.int;
        default = 300; # 5 minutes
        description = "Time to wait before auto-boot after update";
      };
      
      autoRollback = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable automatic rollback on boot failure";
      };
      
      rollbackTimeout = lib.mkOption {
        type = lib.types.int;
        default = 60; # 60 seconds
        description = "Time to wait before triggering rollback";
      };
    };
  };

  config = {
    # systemd-sysupdate configuration
    # A/B partition setup
    # Boot assessment timer
    # Rollback mechanism
  };
}
```

---

## 4. Build Specifications

### 4.1 Image Build Process

**File:** `flake.nix` packages

```nix
packages.image-k3s-node = pkgs.callPackage ./build/image.nix {
  configuration = ./configurations/k3s-node.nix;
  format = "repart";
  size = 10737418240; # 10GB
};
```

**Build Steps:**
1. Build NixOS configuration
2. Create squashfs root filesystem
3. Generate dm-verity hash
4. Create systemd-repart definitions
5. Assemble final image with partitions

### 4.2 Build Output

**Files Generated:**
```
result/
├── disk-image.img           # Raw disk image
├── disk-image.img.sha256    # Image checksum
├── verity-hash.txt          # dm-verity hash
├── partition-table.txt      # Partition layout
└── manifest.json            # Build metadata
```

**manifest.json:**
```json
{
  "version": "1.0.0",
  "buildTime": "2026-08-10T12:00:00Z",
  "nixosVersion": "24.11",
  "kernelVersion": "6.6.0",
  "k3sVersion": "1.28.0+k3s1",
  "partitionLayout": {
    "boot": "1M",
    "esp": "512M",
    "rootA": "5GB",
    "rootB": "5GB"
  },
  "verityHash": "sha256-abc123...",
  "closureSize": "1.2GB"
}
```

---

## 5. Testing Specifications

### 5.1 Unit Tests

**File:** `tests/appliance-module.nix`

```nix
{ pkgs, ... }: {
  name = "appliance-module";

  nodes.builder = { ... }: {
    imports = [ ./modules/appliance-image.nix ];
    image.enable = true;
  };

  testScript = ''
    builder.wait_for_unit("multi-user.target")
    builder.succeed("test -f /nix/store/.image-built")
  '';
}
```

### 5.2 Integration Tests

**File:** `tests/appliance-image.nix`

```nix
{ pkgs, ... }: {
  name = "k3s-appliance-image";

  nodes = {
    builder = { ... }: {};
    vm = pkgs.nixosTest {
      name = "k3s-vm";
      config = ./configurations/k3s-node.nix;
    };
  };

  testScript = ''
    # Build image
    builder.succeed("nix build .#image-k3s-node")
    
    # Verify image structure
    builder.succeed("file result/ | grep -E 'ext4|squashfs'")
    
    # Verify partitions
    builder.succeed("partx -l result/ | grep -E 'boot|esp|root'")
    
    # Verify dm-verity
    builder.succeed("test -f result/verity-hash.txt")
    
    # Start VM with image
    vm.start()
    
    # Verify K3s running
    vm.succeed("systemctl is-active k3s")
    
    # Verify Kubernetes ready
    vm.succeed("kubectl get nodes | grep Ready")
  '';
}
```

### 5.3 Provisioning Tests

**File:** `tests/disko-provisioning.nix`

```nix
{ pkgs, ... }: {
  name = "disko-provisioning";

  nodes = {
    builder = { ... }: {};
    target = { ... }: {};
  };

  testScript = ''
    # Run disko on target
    builder.succeed(
      "nix run nixpkgs#disko -- --disk main /dev/vda --apply"
    )
    
    # Verify partitions created
    target.succeed("lsblk | grep -E 'vda1|vda2|vda3'")
    
    # Verify filesystems mounted
    target.succeed("mount | grep -E '/|/nix'")
    
    # Verify NixOS installed
    target.succeed("test -f /etc/NIXOS")
  '';
}
```

### 5.4 A/B Update Tests

**File:** `tests/ota-updates.nix`

```nix
{ pkgs, ... }: {
  name = "ab-ota-updates";

  nodes = {
    machine = pkgs.nixosTest {
      name = "ota-machine";
      config = ./configurations/k3s-node.nix;
    };
  };

  testScript = ''
    # Verify A/B partitions
    machine.succeed("partx -l /dev/vda | grep -E 'RootA|RootB'")
    
    # Create update source
    machine.succeed("mkdir -p /var/ota")
    
    # Run sysupdate
    machine.succeed("systemd-sysupdate update")
    
    # Verify boot partition switched
    machine.succeed("bootctl | grep 'Current Boot Partition'")
    
    # Verify rollback mechanism
    machine.succeed("test -f /etc/systemd/system/systemd-sysupdate-assessment.timer")
  '';
}
```

### 5.5 Acceptance Criteria

- [ ] Image builds successfully (< 30 minutes)
- [ ] Image size < 10GB
- [ ] dm-verity verification passes
- [ ] disko provisions on test hardware
- [ ] K3s starts and creates cluster
- [ ] A/B update switches partitions
- [ ] Rollback triggers on boot failure
- [ ] All services start correctly

---

## 6. Deployment Specifications

### 6.1 Hardware Requirements

**Minimum:**
- 2 CPU cores
- 4GB RAM
- 20GB storage
- UEFI firmware (for Secure Boot)

**Recommended:**
- 4 CPU cores
- 8GB RAM
- 50GB NVMe storage
- TPM 2.0 module

### 6.2 Provisioning Process

**Step 1: Prepare Boot Media**
```bash
# Build image
nix build .#image-k3s-node

# Write to USB
dd if=result/disk-image.img of=/dev/sdX bs=4M status=progress
```

**Step 2: Boot and Provision**
```bash
# Boot from USB
# Run disko provisioning
nix run nixpkgs#disko -- --disk main /dev/sda

# Reboot
systemctl reboot
```

**Step 3: Join Cluster**
```bash
# On first server
sudo k3s token create

# On agents
sudo k3s agent --server https://<server>:6443 --token <token>
```

### 6.3 Update Process

**Manual Update:**
```bash
# Download update
curl -O https://updates.sc
```

**Automatic Update:**
```bash
# systemd-sysupdate runs daily via timer
systemctl status systemd-sysupdate.timer
```

---

## 7. Security Specifications

### 7.1 dm-verity

**Purpose:** Verify root filesystem integrity

**Configuration:**
```nix
boot.initrd.verify = true;
boot.kernelParams = [ "ro" "verityhash=<hash>" ];
```

### 7.2 Secure Boot (lanzaboote)

**Purpose:** UEFI Secure Boot with measured boot

**Configuration:**
```nix
boot.lanzaboote = {
  enable = true;
  certificateAuthority = /etc/lanzaboote/ca.pem;
};
```

### 7.3 TPM Integration

**Purpose:** Store keys in TPM, measured boot

**Configuration:**
```nix
services.tpm = {
  enable = true;
  tpm2TSS.enable = true;
};

boot.initrd.systemd.tpm2 = {
  enable = true;
  authorizeFirmware = true;
};
```

---

## 8. Monitoring Specifications

### 8.1 Metrics

**Endpoint:** `http://node:9090/metrics` (via node-exporter)

**Key Metrics:**
- `node_filesystem_avail_bytes` - Disk space
- `node_boot_time_seconds` - Boot time
- `systemd_ota_update_status` - Update status
- `k3s_cluster_ready` - Cluster health

### 8.2 Alerts

| Alert | Condition | Severity |
|-------|-----------|----------|
| DiskFull | Disk usage > 85% | 🟠 Warning |
| K3sDown | K3s service down | 🔴 Critical |
| UpdateFailed | OTA update failed | 🟠 Warning |
| VerityFail | dm-verity check failed | 🔴 Critical |

---

## 9. Rollback Plan

If appliance image fails:

1. **Boot fallback partition:** Hold `Shift` during boot
2. **Reprovision:** Run disko again
3. **Revert changes:** Use previous NixOS generation
   ```bash
   nixos-rebuild switch --generation <N>
   ```
4. **Manual recovery:** Boot from USB, chroot, fix

---

**Status:** Draft  
**Reviewers:** Team lead, SCS infrastructure team  
**Approval:** Pending
