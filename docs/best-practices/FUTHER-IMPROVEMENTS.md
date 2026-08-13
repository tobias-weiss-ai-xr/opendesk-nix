# Further Improvements Aligned with nix-best-practices

**Status:** 📋 Analysis Complete  
**Date:** 2026-08-12  
**Reference:** ~/git/nix-best-practices/  
**Related:** DevGuard PR #2843 Integration

---

## 🎯 Executive Summary

Based on the comprehensive analysis of the nix-best-practices repository, there are **significant opportunities** to further improve openDesk-Nix by adopting additional patterns from both nix-best-practices and DevGuard. The improvements fall into several categories:

1. **P0 - Immediate (Already Done ✅)**
2. **P1 - Foundation (High Priority)**
3. **P2 - Advanced (Medium Priority)**
4. **P3 - Long-term (Future Consideration)**

This document outlines all potential improvements with detailed implementation guidance.

---

## ✅ P0 - Immediate (Already Implemented)

These improvements have already been incorporated from DevGuard PR #2843:

### ✅ 1. treefmt Integration
- **Status:** ✅ Done
- **File:** `treefmt.nix`
- **Details:** Using nixfmt, statix, deadnix for automated formatting
- **Formatting:** Applied to 268 files across the codebase

### ✅ 2. CI/CD Workflow
- **Status:** ✅ Done
- **File:** `.github/workflows/nix-flake-check.yaml`
- **Details:** Runs `nix flake check` on push/PR

### ✅ 3. Documentation
- **Status:** ✅ Done
- **Files:** README.md, docs/security/DEVGUARD-PR2843-INTEGRATION.md
- **Details:** Development workflow documented

---

## 🔥 P1 - Foundation (High Priority)

These are recommended as the next immediate improvements based on nix-best-practices:

### P1.1: Use `lib.mapAttrs` for Per-System Outputs

**Current Issue:** The flake.nix uses manual `eachDefaultSystem` but doesn't use `lib.mapAttrs` for consistency.

**Reference:** nix-best-practices/docs/12-flake-architecture.md

**Implementation:**

```nix
# Instead of:
formatter = treefmtEval.config.build.wrapper;

# Use:
formatter = lib.mapAttrs (_: pkgs: treefmtEval.config.build.wrapper) inputs.nixpkgs.legacyPackages;
```

**Benefits:**
- More consistent with nix-best-practices patterns
- Better error handling
- Clearer intent

**Files to Update:**
- `flake.nix`

**Priority:** High
**Effort:** Low (1-2 hours)

---

### P1.2: Add Eval-Only Checks

**Current Issue:** Missing eval-only checks for catching option drift early.

**Reference:** nix-best-practices/docs/10-integration-testing.md

**Implementation:**

```nix
checks = {
  # Eval-only checks (fast)
  eval-sogo5 = (import ./platform/docker/services/sogo5/nixos/configuration.nix { inherit pkgs lib; }).config;
  eval-sogo6 = (import ./platform/docker/services/sogo6/nixos/configuration.nix { inherit pkgs lib; }).config;
  eval-keycloak = (import ./platform/docker/services/keycloak/nixos/configuration.nix { inherit pkgs lib; }).config;
  
  # Integration tests (slower)
  integration = pkgs.testers.runNixOSTest ./tests/integration.nix;
  
  # Formatting check
  formatting = treefmtEval.config.build.check self;
};
```

**Benefits:**
- Catches evaluation errors without building VMs
- Fast CI feedback (seconds vs minutes)
- Validates configuration structure

**Files to Update:**
- `flake.nix`

**Priority:** High
**Effort:** Medium (2-4 hours)

---

### P1.3: Improve flake.nix Structure with flake-parts

**Current Issue:** Large flake.nix file with all logic in one place.

**Reference:** nix-best-practices/docs/12-flake-architecture.md

**Implementation:**

Option A: **Minimal flake-parts adoption**
```nix
# Add to inputs
flake-parts.url = "github:hercules-ci/flake-parts";

# Use for perSystem outputs
outputs = inputs@{ self, nixpkgs, flake-parts, ... }:
  flake-parts.lib.mkFlake { inherit inputs; } {
    systems = [ "x86_64-linux" "aarch64-linux" ];
    perSystem = { pkgs, system, ... }: {
      formatter = ...
      checks = ...
      packages = ...
    };
  };
```

Option B: **Full modularization**
- Split into `flake.nix` + `modules/*.nix`
- Each module handles a specific concern

**Benefits:**
- Cleaner separation of concerns
- Better maintainability
- Aligns with applicative-systems patterns

**Files to Update:**
- `flake.nix`
- Create `modules/` directory

**Priority:** High
**Effort:** Medium-High (4-8 hours)

---

### P1.4: Add `follows` for Sub-Inputs

**Current Issue:** Some inputs may reference nixpkgs redundantly.

**Reference:** nix-best-practices/docs/12-flake-architecture.md

**Implementation:**

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  
  # Sub-inputs that depend on nixpkgs
  treefmt-nix.url = "github:numtide/treefmt-nix";
  treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  
  # If we add other inputs
  agenix.url = "github:ryantm/agenix";
  agenix.inputs.nixpkgs.follows = "nixpkgs";
};
```

**Benefits:**
- Ensures consistent nixpkgs version across inputs
- Avoids seeing "following input 'nixpkgs'" warnings
- Cleaner dependency management

**Files to Update:**
- `flake.nix`

**Priority:** Medium
**Effort:** Low (1 hour)

---

### P1.5: Use nixpkgs-unstable for Builder Tools

**Current Issue:** Some build tools (like `buildGoModule`) may need newer versions.

**Reference:** nix-best-practices/examples/flake.nix

**Implementation:**

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
};

# In outputs, use unstable for build tools
outputs = { self, nixpkgs, nixpkgs-unstable, ... } @inputs:
  eachDefaultSystem (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      unstablePkgs = nixpkgs-unstable.legacyPackages.${system};
      
      # Use unstable for build tools
      hostPkgs = pkgs // {
        buildGoModule = unstablePkgs.buildGoModule;
        # Other build tools as needed
      };
    in { ... }
  );
```

**Benefits:**
- Access to latest build tool fixes
- Still use stable nixpkgs for runtime packages
- Solves version conflicts

**Files to Update:**
- `flake.nix`
- Possibly other build files

**Priority:** Medium
**Effort:** Medium (2-4 hours)

---

## 📊 P2 - Advanced (Medium Priority)

### P2.1: Add Integration Tests for Key Services

**Current Issue:** Limited integration test coverage.

**Reference:** nix-best-practices/docs/10-integration-testing.md

**Implementation:**

Create `tests/integration/services/` with tests for each major service:

```nix
# tests/integration/mariadb.nix
{
  name = "MariaDB service test";
  nodes.mariadb = { config, pkgs, ... }: {
    services.mariadb = {
      enable = true;
      ensureDatabases = [ "testdb" ];
      ensureUsers = [ {
        name = "testuser";
        ensurePermissions = {
          "testdb.*" = "ALL PRIVILEGES";
        };
      }];
    };
    networking.firewall.allowedTCPPorts = [ 3306 ];
  };
  
  testScript = { nodes, ... }: ''
    start_all()
    mariadb.wait_for_unit("mariadb.service")
    mariadb.wait_for_open_port(3306)
    mariadb.succeed("mysql -u testuser -e 'CREATE TABLE test (id INT);'")
  '';
}
```

**Benefits:**
- Validates service configurations
- Catches integration issues early
- Prevents regressions

**Files to Create:**
- `tests/integration/mariadb.nix`
- `tests/integration/postgresql.nix`
- `tests/integration/redis.nix`
- `tests/integration/keycloak.nix`

**Priority:** Medium
**Effort:** High (8-16 hours for initial tests)

---

### P2.2: Container Image Building with dockerTools

**Current Issue:** Container images built via Dockerfiles instead of Nix.

**Reference:** nix-best-practices/docs/13-container-images.md

**Implementation:**

Convert Dockerfile-based builds to Nix-based:

```nix
# platform/nix/docker/sogo6/default.nix
{ pkgs, ... }:

pkgs.dockerTools.buildLayeredImage {
  name = "opendesk-sogo6";
  tag = "6.0.0";
  
  contents = [
    pkgs.sogo6
    pkgs.memcached
    # Other dependencies
  ];
  
  config = {
    Cmd = [ "/usr/bin/sogo" "-C" "/etc/sogo/sogo.conf" ];
    ExposedPorts = { "20000/tcp" = {}; };
    Volumes = {
      "/sogo-data" = {};
      "/etc/sogo" = {};
    };
    Labels = {
      maintainer = "openDesk Edu Team <team@opendesk-edu.org>";
      version = "6.0.0";
    };
  };
}
```

**Benefits:**
- Reproducible builds
- Benefit from Nix caching
- Easier dependency management
- Integration with cosign SBOM

**Files to Update:**
- All Dockerfile-based builds
- Much of the `platform/docker/` directory

**Priority:** Medium
**Effort:** High (16-40 hours for full conversion)

**Note:** This is a significant change and should be done incrementally.

---

### P2.3: Binary Cache with Attic

**Current Issue:** No self-hosted binary cache for the air-gapped SCS environment.

**Reference:** nix-best-practices/docs/05-binary-cache.md, docs/25-recommendations.md

**Implementation:**

```nix
# modules/attic-server.nix (already exists!)
# modules/binary-cache-client.nix (already exists!)
# modules/post-build-hook.nix (already exists!)

# Add to flake outputs
outputs = { ... }:
  eachDefaultSystem (system:
    let
      pkgs = ...;
      
      # Enable binary cache client
      binaryCacheClient = import ./modules/binary-cache-client.nix {
        inherit pkgs;
        cacheUrl = "http://cache.scs.uni-marburg.de:5000";
        cachePublicKey = "opendesk-nix-cache:...";
      };
    in {
      # Export cache configuration
      nixosModulesattic = import ./modules/attic-server.nix;
      
      # For NixOS systems
      nixosConfigurations = {
        cache-server = nixpkgs.lib.nixosSystem {
          modules = [
            binaryCacheClient.nixosModule
            (import ./modules/attic-server.nix)
          ];
        };
      };
    }
  );
```

**Benefits:**
- Reduced build times (share artifacts)
- Critical for air-gapped environment
- Already partially implemented!

**Files to Update:**
- `flake.nix` (nixosConfigurations)
- Deploy attic-server to SCS

**Priority:** High (but requires infrastructure)
**Effort:** Medium (4-8 hours for config + deployment)

---

### P2.4: Secrets Management with agenix

**Current Issue:** Secrets may be handled inconsistently.

**Reference:** nix-best-practices/docs/06-secrets-management.md

**Implementation:**

```nix
# Add to inputs
inputs = {
  agenix.url = "github:ryantm/agenix";
  agenix.inputs.nixpkgs.follows = "nixpkgs";
};

# Add secrets module
nixosModules.age = import ./modules/age-secrets.nix {
  inherit inputs;
};

# Use LoadCredential= pattern
nixosConfigurations.node = nixpkgs.lib.nixosSystem {
  modules = [
    inputs.agenix.nixosModules.default
    {
      age.secrets.keycloak-admin-password = {
        file = ./secrets/keycloak-admin Password.age;
        mode = "0400";
      };
    }
    {
      services.keycloak.adminPasswordFile = 
        config.age.secrets.keycloak-admin-password.path;
    }
  ];
};
```

**Benefits:**
- Secrets never in Nix store (world-readable)
- Encrypted at rest
- Access controlled via file permissions
- Loaded via systemd LoadCredential=

**Files to Create:**
- `modules/age-secrets.nix`
- Secrets in `.age` files

**Priority:** Medium
**Effort:** Medium (4-8 hours)

---

### P2.5: Disk Provisioning with disko

**Current Issue:** Manual disk partitioning for SCS nodes.

**Reference:** nix-best-practices/docs/07-disk-provisioning.md

**Implementation:**

```nix
# Add to inputs
inputs = {
  disko.url = "github:nix-community/disko";
  disko.inputs.nixpkgs.follows = "nixpkgs";
};

# Create disk configuration for SCS nodes
# platform/nix/disko/configurations/scs-node.nix
{ pkgs, ... }:

{
  disko.devices = [
    {
      name = "/dev/nvme0n1";
      label = "gpt";
      type = "disk";
      content = [
        {
          type = "part";
          size = "1G";
          fsType = "fat32";
          label = "boot";
          flags = [ "boot" "esp" ];
        }
        {
          type = "part";
          size = "100%";
          label = "nixos";
          content = {
            type = "lvm";
            vgName = "vg";
            pvName = "pv";
            lvm.content = [
              {
                type = "lv";
                name = "root";
                size = "50G";
                fsType = "btrfs";
                mountpoint = "/";
              }
              {
                type = "lv";
                name = "var";
                size = "20G";
                fsType = "btrfs";
                mountpoint = "/var";
              }
            ];
          };
        }
      ];
    }
  ];
}
```

**Benefits:**
- Declarative disk layouts
- Reproducible across nodes
- Supports LUKS encryption
- TPM integration possible

**Files to Create:**
- `platform/nix/disko/configurations/`
- Update `flake.nix`

**Priority:** Medium
**Effort:** High (8-16 hours)

---

## 🚀 P3 - Long-term (Future Consideration)

### P3.1: NixOS Appliance Images with systemd-repart

**Current Issue:** SCS nodes provisioned with Ansible.

**Reference:** nix-best-practices/docs/19-appliance-images.md

**Implementation:**

```nix
# Create appliance images for SCS nodes
outputs = { ... }:
  eachDefaultSystem (system:
    let
      pkgs = ...;
    in {
      packages = {
        scs-appliance-image = pkgs.callPackage ./platform/nix/appliance-image.nix {
          inherit pkgs;
          diskoConfig = import ./platform/nix/disko/configurations/scs-node.nix { inherit pkgs; };
        };
      };
    }
  );
```

**Benefits:**
- Immutable base OS
- A/B OTA update capable
- Reproducible across all nodes
- Squashfs for nix-store (read-only)

**Priority:** Low (requires NixOS adoption)
**Effort:** Very High (16-40 hours)

---

### P3.2: A/B OTA Updates with systemd-sysupdate

**Current Issue:** Manual node updates.

**Reference:** nix-best-practices/docs/19-appliance-images.md

**Implementation:**

```nix
# Enable A/B OTA on appliance images
{
  boot.loader.systemd-boot = {
    enable = true;
    firmware = config.boot.efiFirmware;
  };
  
  boot.sysupdate = {
    enable = true;
    atomic = true;
    bootLoader = "systemd-boot";
  };
  
  systemd.sysupdate.image = {
    enable = true;
    type = "raw";
    fsType = "btrfs";
    laptop.btrfs.baseVolume = "/dev/mapper/vg-root";
  };
  
  boot.kernelPackages = pkgs.linuxPackages_testing;
}
```

**Benefits:**
- Atomic updates
- Automatic rollback on boot failure
- Zero-downtime deployments
- Boot assessment

**Priority:** Low (depends on P3.1)
**Effort:** Very High

---

### P3.3: Impermanence for Ephemeral Root

**Current Issue:** Manual state management.

**Reference:** nix-best-practices/docs/08-immutable-systems.md

**Implementation:**

```nix
# Username/password should be configuration
users.users.k3s = {
  isNormalUser = true;
  home = "/var/lib/rancher/k3s";
  uid = 1000;
};

{ config, ... }:

{
  impermanence.enable = true;
  
  systemd.tmpfiles.rules = [
    "e /var/log/keycloak - - - 0755 -",
    "e /var/lib/rancher/k3s - - - 0755 k3s",
    # Any other directories that need persistent state
  ];
  
  # Use systemd-tmpfiles-setup to create these at boot
  systemd.tmpfiles-setup.rules = [
    {
      matchPath = "/var/log/keycloak";
      type = "d";
      mode = 0755;
      uid = 0;
      gid = 0;
    }
  ];
}
```

**Benefits:**
- Forces explicit state declaration
- Prevents configuration drift
- Better security (no accidental state)

**Priority:** Low
**Effort:** Medium (4-8 hours to identify persistent state)

---

### P3.4: Colmena for Multi-Node Deployment

**Current Issue:** Ansible used for orchestration.

**Reference:** nix-best-practices/docs/11-deployment.md

**Implementation:**

```nix
# Add colmena to devShells
outputs = { ... }:
  eachDefaultSystem (system:
    let
      pkgs = ...;
    in {
      devShells.default = pkgs.mkShell {
        packages = with pkgs; [
          (import inputs.colmena { inherit system; }).packages.default
        ];
      };
      
      # Or use colmena directly for deployment
      apps.default = {
        type = "app";
        program = "${inputs.colmena.packages.${system}.colmena}/bin/colmena";
      };
    }
  );

# Use colmena for deployment
colmena apply --on clrz14-06 --on clrz14-07 ./flake.nix#scs-node
```

**Benefits:**
- Parallel deployment
- Stateless (no server)
- SSH-based
- Builds on remote machines

**Priority:** Low (requires NixOS adoption)
**Effort:** Medium (4-8 hours)

---

### P3.5: declarative-runtime for Runtime State

**Current Issue:** Runtime state (Keycloak realms, Grafana dashboards) managed manually.

**Reference:** nix-best-practices/docs/20-runtime-state.md, docs/25-recommendations.md

**Implementation:**

```nix
# services/keycloak/runtime.nix
{ lib, pkgs, ... }:

let
  # Define Keycloak resources as Nix options
  keycloakResources = lib.types.submodule {
    options = {
      realms = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule { ... });
        default = [];
      };
      clients = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule { ... });
        default = [];
      };
    };
  };
  
  # Generate Terraform/JSON from Nix options
  generateKeycloakConfig = resources: ''
    ${builtins.concatStringsSep "\n" (map (realm: ''
      resource "keycloak_realm" "${realm.name}" {
        realm_id = "${realm.name}"
        enabled = ${toString realm.enabled}
        # ... other realm attributes
      }
    '') resources.realms)}
  '';
  
  # Systemd service to apply runtime state
  runtimeScript = resources: ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    
    # Write config to temp file
    TF_CONFIG=$(mktemp)
    echo '${generateKeycloakConfig resources}' > "$TF_CONFIG"
    
    # Apply with OpenTofu
    ${pkgs.opentofu}/bin/tofu apply -auto-approve "$TF_CONFIG"
    
    # Cleanup
    rm "$TF_CONFIG"
  '';

in {
  options.services.keycloak.runtime = lib.mkOption {
    type = keycloakResources;
    default = {};
    description = "Keycloak runtime resources";
  };
  
  config = lib.mkIf (config.services.keycloak.enable) {
    systemd.services.keycloak-runtime = {
      description = "Apply Keycloak runtime configuration";
      wantedBy = [ "multi-user.target" ];
      after = [ "keycloak.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = runtimeScript config.services.keycloak.runtime;
      };
    };
  };
}
```

**Benefits:**
- Runtime state declared in Nix
- Automatic application on service start
- Version controlled
- Air-gap friendly

**Priority:** Low (but high value)
**Effort:** Very High (16-40 hours for full implementation)

---

### P3.6: Cross-Compilation Support

**Current Issue:** Limited to x86_64-linux.

**Reference:** nix-best-practices/docs/14-cross-compilation.md

**Implementation:**

```nix
outputs = { ... } @inputs:
  flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import inputs.nixpkgs {
        inherit system;
        config = { allowUnfree = true; };
      };
      
      # For cross-compilation
      pkgsCross = import inputs.nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          buildPlatform = "x86_64-linux";
          hostPlatform = "aarch64-linux";
        };
      };
    in {
      packages = {
        sogo6-x86_64 = pkgs.callPackage ./platform/nix/docker/sogo6/default.nix { };
        sogo6-aarch64 = pkgsCross.callPackage ./platform/nix/docker/sogo6/default.nix { };
      };
    }
  )
  // flake-utils.lib.eachSystem [ "aarch64-linux" ] (system:
    let
      pkgs = import inputs.nixpkgs {
        inherit system;
        localSystem = {
          system = "x86_64-linux";
          config = { allowUnfree = true; };
        };
        crossConfig = { config = { allowUnfree = true; }; };
      };
    in {
      packages = {
        sogo6-cross = pkgs.callPackage ./platform/nix/docker/sogo6/default.nix { };
      };
    }
  );
```

**Benefits:**
- Build for multiple architectures
- Support ARM nodes if added to SCS
- Better portability

**Priority:** Low (unless ARM nodes added)
**Effort:** Medium (4-8 hours)

---

## 📋 Implementation Roadmap

### Phase 1: Immediate (Weeks 1-2)
- [ ] P1.1: Use `lib.mapAttrs` for per-system outputs
- [ ] P1.2: Add eval-only checks
- [ ] P1.3: Add `follows` for sub-inputs
- [ ] P1.4: Use nixpkgs-unstable for builder tools
- **Total Effort:** 8-16 hours

### Phase 2: Foundation (Weeks 3-4)
- [ ] P2.1: Add integration tests for key services
- [ ] P2.2: Convert container builds to dockerTools (start with 2-3 services)
- [ ] P2.3: Deploy Attic binary cache to SCS
- [ ] P2.4: Add agenix for secrets management
- [ ] P2.5: Add disko for disk provisioning
- **Total Effort:** 32-64 hours

### Phase 3: Advanced (Weeks 5-8)
- [ ] P2.2: Convert all container builds to dockerTools
- [ ] P2.1: Add integration tests for all services
- [ ] P3.1: Create NixOS appliance images
- [ ] P3.2: Add A/B OTA updates
- [ ] P3.3: Add impermanence
- **Total Effort:** 64-128 hours

### Phase 4: Long-term (Ongoing)
- [ ] P3.4: Adopt Colmena for deployment
- [ ] P3.5: Add declarative-runtime for runtime state
- [ ] P3.6: Add cross-compilation support
- **Total Effort:** 40-80 hours

---

## 🎯 Priority Matrix

| Priority | Category | Effort | Impact | When to Do |
|----------|----------|--------|--------|------------|
| P0 | Already Done | ✅ | High | Now |
| P1 | Foundation | Low-Medium | High | Weeks 1-2 |
| P2 | Advanced | Medium-High | High | Weeks 3-4 |
| P3 | Long-term | High-Very High | Medium | Weeks 5+ |

---

## ⚡ Quick Wins (Can Do Today)

These improvements can be implemented immediately with high impact:

1. **P1.1 + P1.3 + P1.4** (4-8 hours)
   - Use `lib.mapAttrs` for consistency
   - Add `follows` for sub-inputs
   - Use nixpkgs-unstable for build tools

2. **P1.2** (2-4 hours)
   - Add eval-only checks to flake

3. **P2.3 Deployment** (4-8 hours)
   - Deploy existing Attic modules to SCS
   - Configure post-build-hook

---

## 📊 Cost-Benefit Analysis

### High ROI (Do First)
- **P1.1-P1.4**: Low effort, high impact on code quality
- **P1.2**: Low effort, catches errors early in CI
- **P2.3**: Medium effort, critical for air-gapped environment

### Medium ROI (Do Next)
- **P2.1**: Medium effort, improves reliability
- **P2.2**: High effort, but significant long-term benefits
- **P2.4**: Medium effort, improves security

### Long-term Investment
- **P3.1-P3.6**: High effort, transformational changes

---

## 🔗Relationship to DevGuard

Many of these improvements align with or extend the DevGuard patterns:

| Improvement | DevGuard Alignment | Notes |
|-------------|-------------------|-------|
| P0 (Done) | ✅ Direct | DevGuard PR #2843 patterns |
| P1.1-P1.4 | ✅ Pattern | Formatting, CI, structure |
| P1.2 | ✅ Pattern | DevGuard has checks |
| P2.1 | ✅ Pattern | DevGuard tests services |
| P2.2 | ✅ Pattern | DevGuard builds images |
| P2.3 | ✅ Pattern | DevGuard supports caches |
| P2.4 | ✅ Pattern | DevGuard handles secrets |
| P3.1-P3.6 | ⚠️ Extended | Beyond DevGuard scope |

---

## 📚 Additional Resources

- **nix-best-practices:** ~/git/nix-best-practices/
- **DevGuard:** https://github.com/l3montree-dev/devguard
- **flake-parts:** https://github.com/hercules-ci/flake-parts
- **Attic:** https://github.com/zhaofengli/attic
- **agenix:** https://github.com/ryantm/agenix
- **disko:** https://github.com/nix-community/disko
- **Colmena:** https://github.com/zhaofengli/colmena
- **declarative-runtime:** https://github.com/frontrow-ops/declarative-runtime

---

## 🏆 Conclusion

The openDesk-Nix project has already made excellent progress with DevGuard PR #2843 integration. The next steps should focus on **P1 (Foundation)** improvements, which provide high value with relatively low effort. These improvements will:

1. ✅ Improve code quality and maintainability
2. ✅ Catch errors earlier in development and CI
3. ✅ Enhance security (secrets, immutability)
4. ✅ Better support the air-gapped SCS environment
5. ✅ Align with nix-best-practices and DevGuard patterns

**Recommended Next Action:** Start with P1.1-P1.4 (1-2 days of work) to build momentum, then tackle P2.3 (Attic deployment) as it's critical for the air-gapped environment.

---

**Author:** openDesk Edu Team  
**Last Updated:** 2026-08-12  
**Version:** 1.0.0
