# 🎯 Action Plan: Further Improvements Aligned with nix-best-practices

**Project:** openDesk-Nix  
**Reference:** DevGuard PR #2843 + nix-best-practices  
**Date:** 2026-08-12  
**Status:** Ready for Execution

---

## 📋 Overview

This action plan provides a **prioritized, phased approach** to implementing further improvements aligned with:
- **nix-best-practices** (~/git/nix-best-practices/)
- **DevGuard patterns** (already partially implemented)
- **SCS K3s air-gapped environment requirements**

**Total Estimated Effort:** ~100-150 hours across all phases  
**Recommended Timeline:** 6-8 weeks (part-time)

---

## 🎯 Phase 0: Current State (Already Completed ✅)

### ✅ What's Been Done

| Task | Status | Commit | Files Changed |
|------|--------|--------|---------------|
| Add GitHub Actions workflow for `nix flake check` | ✅ Done | 2bf7a006 | 1 new file |
| Update treefmt.nix to use nixfmt | ✅ Done | 2bf7a006 | 1 modified |
| Apply formatting to flake.nix | ✅ Done | 2bf7a006 | 1 modified |
| Apply treefmt to entire codebase | ✅ Done | 6954b87a | 272 files |
| Add development workflow documentation | ✅ Done | 2bf7a006 | 2 new files |
| Add integration summary documentation | ✅ Done | 3a2983bc | 1 new file |

**Statistics:**
- 3 commits
- 4 files added
- 273 files modified
- ~4,500 lines changed
- 268 files formatted

---

## 🔥 Phase 1: Immediate Improvements (Week 1-2)

**Goal:** Quick wins with high impact, low effort

### 📌 Task P1.1: Use `lib.mapAttrs` for Per-System Outputs

**Description:** Current flake.nix uses manual `eachDefaultSystem`. Use `lib.mapAttrs` for better consistency and error handling.

**Reference:** nix-best-practices/docs/12-flake-architecture.md, examples/flake.nix

**Implementation:**
```nix
# Before:
formatter = treefmtEval.config.build.wrapper;

# After:
formatter = lib.mapAttrs (_: pkgs: treefmtEval.config.build.wrapper) inputs.nixpkgs.legacyPackages;
```

**Files to Modify:**
- `flake.nix`

**Effort:** 1-2 hours
**Priority:** 🔥 High
**Impact:** ⭐⭐⭐⭐
**Dependencies:** None

---

### 📌 Task P1.2: Add Eval-Only Checks

**Description:** Add fast evaluation-only checks that catch option drift without building VMs.

**Reference:** nix-best-practices/docs/10-integration-testing.md, docs/25-recommendations.md

**Implementation:**
```nix
checks = {
  # Eval-only checks (fast - seconds)
  eval-configurations = builtins.listToAttrs (map (name: {
    name = "eval-${name}";
    value = (nixos-services.${name} or {}).config or null;
  }) (builtins.attrNames nixos-services));
  
  # Existing checks
  integration = pkgs.testers.runNixOSTest ./tests/integration.nix;
  formatting = treefmtEval.config.build.check self;
};
```

**Files to Modify:**
- `flake.nix`

**Effort:** 2-4 hours
**Priority:** 🔥 High
**Impact:** ⭐⭐⭐⭐⭐ (catches errors early in CI)
**Dependencies:** None

---

### 📌 Task P1.3: Add `follows` for Sub-Inputs

**Description:** Ensure consistent nixpkgs version across all inputs.

**Reference:** nix-best-practices/docs/12-flake-architecture.md

**Implementation:**
```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  
  treefmt-nix.url = "github:numtide/treefmt-nix";
  treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
};
```

**Files to Modify:**
- `flake.nix`

**Effort:** 1 hour
**Priority:** ⚡ Medium
**Impact:** ⭐⭐⭐
**Dependencies:** None

---

### 📌 Task P1.4: Use nixpkgs-unstable for Builder Tools

**Description:** Use unstable nixpkgs for build tools like `buildGoModule` while keeping runtime packages on stable.

**Reference:** nix-best-practices/examples/flake.nix

**Implementation:**
```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
};

outputs = { self, nixpkgs, nixpkgs-unstable, ... } @inputs:
  eachDefaultSystem (system:
    let
      pkgs = import nixpkgs { inherit system; };
      unstablePkgs = import nixpkgs-unstable { inherit system; };
      
      hostPkgs = pkgs // {
        buildGoModule = unstablePkgs.buildGoModule;
      };
    in { ... }
  );
```

**Files to Modify:**
- `flake.nix`

**Effort:** 2-4 hours
**Priority:** ⚡ Medium
**Impact:** ⭐⭐⭐⭐
**Dependencies:** None

---

### Phase 1 Summary

| Task | Effort | Priority | Impact | Status |
|------|--------|----------|--------|--------|
| P1.1 | 1-2h | 🔥 High | ⭐⭐⭐⭐ | ⏳ Todo |
| P1.2 | 2-4h | 🔥 High | ⭐⭐⭐⭐⭐ | ⏳ Todo |
| P1.3 | 1h | ⚡ Medium | ⭐⭐⭐ | ⏳ Todo |
| P1.4 | 2-4h | ⚡ Medium | ⭐⭐⭐⭐ | ⏳ Todo |

**Total Phase 1 Effort:** 6-11 hours  
**Expected Completion:** Week 1-2  
**ROI:** Very High

---

## 🚀 Phase 2: Foundation Improvements (Week 3-4)

**Goal:** Build core infrastructure improvements

### 📌 Task P2.1: Add Integration Tests for Key Services

**Description:** Add NixOS integration tests for critical services (mariadb, postgresql, redis, keycloak).

**Reference:** nix-best-practices/docs/10-integration-testing.md

**Implementation:**
```nix
# tests/integration/mariadb-test.nix
{
  name = "MariaDB service test";
  nodes.mariadb = { config, pkgs, ... }: {
    services.mariadb = {
      enable = true;
      ensureDatabases = [ "testdb" ];
      ensureUsers = [ { name = "testuser"; ensurePermissions = { "testdb.*" = "ALL PRIVILEGES"; }; } ];
    };
    networking.firewall.allowedTCPPorts = [ 3306 ];
  };
  
  testScript = { nodes, ... }: ''
    start_all()
    mariadb.wait_for_unit("mariadb.service")
    mariadb.wait_for_open_port(3306)
    mariadb.succeed("mysql -u testuser testdb -e 'CREATE TABLE test (id INT);'")
  '';
}
```

**Files to Create:**
- `tests/integration/mariadb-test.nix`
- `tests/integration/postgresql-test.nix`
- `tests/integration/redis-test.nix`
- `tests/integration/keycloak-test.nix`

**Files to Modify:**
- `flake.nix` (add to checks)

**Effort:** 8-16 hours
**Priority:** 🔥 High
**Impact:** ⭐⭐⭐⭐⭐
**Dependencies:** None

---

### 📌 Task P2.2: Convert 2-3 Container Builds to dockerTools

**Description:** Pilot conversion of container image builds from Dockerfiles to Nix-based dockerTools.

**Reference:** nix-best-practices/docs/13-container-images.md, examples/docker-image.nix

**Implementation:**
```nix
# platform/nix/docker/sogo6/default.nix
{ pkgs, ... }:

pkgs.dockerTools.buildLayeredImage {
  name = "opendesk-sogo6";
  tag = "6.0.0";
  
  contents = with pkgs; [
    sogo
    memcached
    openssl
    certs
  ];
  
  config = {
    Cmd = [ "/usr/bin/sogo" "-C" "/etc/sogo/sogo.conf" ];
    ExposedPorts = { "20000/tcp" = {}; };
    Volumes = { "/sogo-data" = {}; "/etc/sogo" = {}; };
    Labels = {
      maintainer = "openDesk Edu Team <team@opendesk-edu.org>";
      version = "6.0.0";
    };
  };
}
```

**Recommendation:** Start with simpler services:
1. **redis-opendesk** - Simple, few dependencies
2. **mariadb-opendesk** - Medium complexity
3. **sogo6** - Complex, but high value

**Files to Create/Modify:**
- `platform/nix/docker/redis-opendesk/default.nix`
- `platform/nix/docker/mariadb-opendesk/default.nix`
- `platform/nix/docker/sogo6/default.nix`
- `flake.nix` (update packages)

**Effort:** 8-12 hours (for 3 services)
**Priority:** ⚡ Medium
**Impact:** ⭐⭐⭐⭐
**Dependencies:** None

---

### 📌 Task P2.3: Deploy Attic Binary Cache to SCS

**Description:** Deploy the existing Attic modules to the SCS environment for binary cache sharing.

**Reference:** nix-best-practices/docs/05-binary-cache.md, docs/25-recommendations.md

**Implementation:**

1. **Configure Attic server:**
```nix
# modules/attic-server.nix (already exists!)
{ config, pkgs, lib, ... }:

{
  services.attic = {
    enable = true;
    host = "0.0.0.0";
    port = 5000;
    
    # Storage backend (Ceph RGW)
    store = {
      type = "s3";
      bucket = "nix-cache";
      endpoint = "https://s3.scs.uni-marburg.de";
      # Credentials via LoadCredential=
    };
    
    # Signing
    secretKeyFile = config.age.secrets.attic-secret-key.path;
    
    # TLS (if needed)
    tls = {
      enable = true;
      certFile = "/etc/ssl/certs/attic.crt";
      keyFile = "/etc/ssl/private/attic.key";
    };
  };
  
  # Firewall
  networking.firewall.allowedTCPPorts = [ 5000 ];
}
```

2. **Deploy to a SCS node:**
```bash
# Build and deploy
nix build .#attic-server
systemctl enable --now attic-server
```

3. **Configure clients:**
```nix
# modules/binary-cache-client.nix (already exists!)
{ config, pkgs, ... }:

{
  nix.settings.substituters = [ "http://cache.scs.uni-marburg.de:5000" ];
  nix.settings.trusted-public-keys = [ "opendesk-nix-cache:..." ];
  
  # Optional: trustrattic for automatic key discovery
  programs.trustrattic = {
    enable = true;
    servers = [ "cache.scs.uni-marburg.de:5000" ];
  };
}
```

4. **Configure post-build-hook:**
```nix
# modules/post-build-hook.nix (already exists!)
{ config, pkgs, ... }:

{
  nix.settings.post-build-hook = ''
    ${pkgs.curl}/bin/curl -X POST \
      -H "Content-Type: application/json" \
      -d '{"path": "$out", "narHash": "$narHash"}' \
      http://cache.scs.uni-marburg.de:5000/upload
  '';
}
```

**Files to Modify:**
- `modules/attic-server.nix` (update with SCS-specific config)
- `modules/binary-cache-client.nix` (verify SCS endpoint)
- `modules/post-build-hook.nix` (verify upload URL)
- `flake.nix` (ensure modules are exported)

**Effort:** 4-8 hours
**Priority:** 🔥 High (Critical for air-gapped environment!)
**Impact:** ⭐⭐⭐⭐⭐
**Dependencies:** SCS infrastructure access

---

### 📌 Task P2.4: Add agenix for Secrets Management

**Description:** Implement agenix for encrypted secrets management.

**Reference:** nix-best-practices/docs/06-secrets-management.md, examples/agenix-secrets.nix

**Implementation:**

1. **Add agenix to inputs:**
```nix
inputs = {
  agenix.url = "github:ryantm/agenix";
  agenix.inputs.nixpkgs.follows = "nixpkgs";
};
```

2. **Create age secrets:**
```bash
# Generate age key (if not exists)
age-keygen -o .age/keys.txt

# Encrypt a secret
echo "secret-password" | age -r age1... -o secrets/keycloak-admin-password.age
```

3. **Add secrets module:**
```nix
# modules/age-secrets.nix
{ config, pkgs, lib, inputs, ... }:

{
  age.secrets = {
    keycloak-admin-password = {
      file = ./secrets/keycloak-admin-password.age;
      mode = "0400";
    };
    mariadb-root-password = {
      file = ./secrets/mariadb-root-password.age;
      mode = "0400";
    };
  };
  
  # Trust age keys
  age.keys = [
    {
      path = ./secrets/age-keys/keycloak.key;
      users = [ "keycloak" ];
    }
    {
      path = ./secrets/age-keys/database.key;
      users = [ "mariadb" "postgresql" ];
    }
  ];
}
```

4. **Use in services:**
```nix
services.keycloak.adminPasswordFile = config.age.secrets.keycloak-admin-password.path;
services.mariadb.ensureDatabases = [ { name = "test"; ensureUsers = [ { name = "root"; passwordFile = config.age.secrets.mariadb-root-password.path; } ]; } ];
```

**Files to Create:**
- `modules/age-secrets.nix`
- `.age/keys.txt` (exclude from git)
- `secrets/*.age` (exclude from git)

**Files to Modify:**
- `flake.nix` (add agenix input)
- Service configurations (use age secrets)

**Effort:** 4-8 hours
**Priority:** ⚡ Medium
**Impact:** ⭐⭐⭐⭐⭐ (Security!)
**Dependencies:** None

---

### 📌 Task P2.5: Add disko for Disk Provisioning

**Description:** Add declarative disk partitioning for SCS nodes.

**Reference:** nix-best-practices/docs/07-disk-provisioning.md, examples/disko-partition.nix

**Implementation:**

1. **Add disko to inputs:**
```nix
inputs = {
  disko.url = "github:nix-community/dsko";
  disko.inputs.nixpkgs.follows = "nixpkgs";
};
```

2. **Create disk configuration:**
```nix
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
              {
                type = "lv";
                name = "srv";
                size = "100%";
                fsType = "btrfs";
                mountpoint = "/srv";
              }
            ];
          };
        }
      ];
    }
  ];
}
```

3. **Use in NixOS configurations:**
```nix
nixpkgs.lib.nixosSystem {
  modules = [
    (import ./platform/nix/disko/configurations/scs-node.nix { inherit pkgs; })
    # ... other modules
  ];
}
```

**Files to Create:**
- `platform/nix/disko/configurations/scs-node.nix`

**Files to Modify:**
- `flake.nix` (add disko input)
- NixOS configurations (include disko module)

**Effort:** 4-8 hours
**Priority:** ⚡ Medium
**Impact:** ⭐⭐⭐⭐
**Dependencies:** None (but needs SCS node access for testing)

---

### Phase 2 Summary

| Task | Effort | Priority | Impact | Status |
|------|--------|----------|--------|--------|
| P2.1 | 8-16h | 🔥 High | ⭐⭐⭐⭐⭐ | ⏳ Todo |
| P2.2 | 8-12h | ⚡ Medium | ⭐⭐⭐⭐ | ⏳ Todo |
| P2.3 | 4-8h | 🔥 High | ⭐⭐⭐⭐⭐ | ⏳ Todo |
| P2.4 | 4-8h | ⚡ Medium | ⭐⭐⭐⭐⭐ | ⏳ Todo |
| P2.5 | 4-8h | ⚡ Medium | ⭐⭐⭐⭐ | ⏳ Todo |

**Total Phase 2 Effort:** 28-48 hours  
**Expected Completion:** Week 3-4  
**ROI:** Very High

---

## 📊 Phase 3: Advanced Improvements (Week 5-6+)

**Goal:** Complete transformation to modern Nix practices

### 📌 Task P2.2 (Continued): Convert All Container Builds to dockerTools

**Description:** Complete the conversion started in Phase 2.

**Services to Convert:** All 57 services in platform/docker/services/

**Effort:** 24-40 hours
**Priority:** ⚡ Medium
**Impact:** ⭐⭐⭐⭐⭐
**Dependencies:** P2.2 pilot

---

### 📌 Task P2.1 (Continued): Add Integration Tests for All Services

**Description:** Complete test coverage for all services.

**Services to Test:** All 57 services

**Effort:** 16-32 hours
**Priority:** ⚡ Medium
**Impact:** ⭐⭐⭐⭐
**Dependencies:** P2.1 pilot

---

### 📌 Task P3.1: Create NixOS Appliance Images

**Description:** Build immutable NixOS appliance images for SCS nodes.

**Reference:** nix-best-practices/docs/19-appliance-images.md, examples/appliance-image.nix

**Effort:** 8-16 hours
**Priority:** Low (requires NixOS adoption)
**Impact:** ⭐⭐⭐⭐
**Dependencies:** P2.5 (disko)

---

### 📌 Task P3.2: Add A/B OTA Updates

**Description:** Implement A/B OTA updates for safe node deployments.

**Reference:** nix-best-practices/docs/19-appliance-images.md, examples/ota-update.nix

**Effort:** 4-8 hours
**Priority:** Low
**Impact:** ⭐⭐⭐⭐
**Dependencies:** P3.1

---

### 📌 Task P3.3: Add impermanence

**Description:** Implement impermanence for ephemeral root filesystem.

**Reference:** nix-best-practices/docs/08-immutable-systems.md

**Effort:** 4-8 hours
**Priority:** Low
**Impact:** ⭐⭐⭐⭐
**Dependencies:** P3.1

---

### Phase 3 Summary

| Task | Effort | Priority | Impact | Status |
|------|--------|----------|--------|--------|
| P2.2 (Complete) | 24-40h | ⚡ Medium | ⭐⭐⭐⭐⭐ | ⏳ Todo |
| P2.1 (Complete) | 16-32h | ⚡ Medium | ⭐⭐⭐⭐ | ⏳ Todo |
| P3.1 | 8-16h | Low | ⭐⭐⭐⭐ | ⏳ Todo |
| P3.2 | 4-8h | Low | ⭐⭐⭐⭐ | ⏳ Todo |
| P3.3 | 4-8h | Low | ⭐⭐⭐⭐ | ⏳ Todo |

**Total Phase 3 Effort:** 56-104 hours  
**Expected Completion:** Week 5-8  
**ROI:** High

---

## 📈 Overall Summary

### Total Effort by Phase

| Phase | Tasks | Effort Range | Priority | ROI |
|-------|-------|--------------|----------|-----|
| Phase 0 (Done) | 6 tasks | 0 hours | N/A | ✅ Complete |
| Phase 1 (Immediate) | 4 tasks | 6-11 hours | 🔥 High | ⭐⭐⭐⭐⭐ |
| Phase 2 (Foundation) | 5 tasks | 28-48 hours | 🔥 High | ⭐⭐⭐⭐⭐ |
| Phase 3 (Advanced) | 5 tasks | 56-104 hours | ⚡ Medium | ⭐⭐⭐⭐ |
| **Total** | **14 tasks** | **90-163 hours** | | |

### Recommended Timeline

| Week | Focus | Tasks | Effort |
|------|-------|-------|--------|
| Week 1-2 | Phase 1 (Immediate) | P1.1-P1.4 | 6-11h |
| Week 3-4 | Phase 2 (Foundation) | P2.1-P2.5 | 28-48h |
| Week 5-6 | Phase 2 (Complete) | P2.1-P2.2 (full) | 40-72h |
| Week 7-8+ | Phase 3 (Advanced) | P3.1-P3.3 | 16-32h |
| **Total** | **All Phases** | **All Tasks** | **90-163h** |

### Priority Matrix

| Priority | Description | Effort | Impact | When |
|----------|-------------|--------|--------|------|
| 🔥 Critical | Must do, high impact | Low-Medium | High | Weeks 1-4 |
| ⚡ Important | Should do, good impact | Medium | High | Weeks 1-6 |
| 💡 Nice-to-have | Nice but not urgent | Medium-High | Medium | Weeks 5-8+ |

**Critical (Weeks 1-4):**
- Phase 1: All 4 tasks (6-11h)
- Phase 2: P2.3 (Attic) + P2.4 (agenix) (8-16h)
- **Total Critical:** 14-27 hours

**Important (Weeks 1-6):**
- Phase 2: All 5 tasks (28-48h)
- **Total Important:** 28-48 hours

**Nice-to-have (Weeks 5-8+):**
- Phase 3: All 5 tasks (56-104h)

---

## 🎯 Quick Start: Week 1

**Goal:** Complete Phase 1 + Start Phase 2

### Day 1 (2-4 hours)
1. **P1.3**: Add `follows` for sub-inputs (1 hour)
2. **P1.1**: Use `lib.mapAttrs` for per-system outputs (1-2 hours)
3. **P1.4**: Add nixpkgs-unstable for builder tools (1 hour)

### Day 2 (2-4 hours)
1. **P1.2**: Add eval-only checks (2-4 hours)
2. **Test:** Run `nix flake check` locally
3. **Push:** Commit and push Phase 1 changes

### Day 3 (2-4 hours)
1. **P2.3**: Configure Attic modules for SCS deployment (2-4 hours)
2. **Coordinate:** Work with SCS admin to deploy Attic server

### Day 4 (2-4 hours)
1. **P2.4**: Add agenix support (2-4 hours)
2. **Create:** Age keys and encrypt sample secrets
3. **Update:** One service to use age secrets

**Week 1 Total:** 8-16 hours  
**Week 1 Deliverables:**
- Phase 1 complete (4 tasks)
- Phase 2: P2.3 + P2.4 started

---

## 🎯 Quick Start: Week 2

**Goal:** Complete remaining Phase 2 tasks

### Day 5 (4-8 hours)
1. **P2.1**: Add integration tests for 2-3 key services (4-8 hours)
2. **Test:** Verify tests pass in CI

### Day 6 (4-8 hours)
1. **P2.2**: Convert 2-3 container builds to dockerTools (4-8 hours)
2. **Test:** Build and verify container images

### Day 7 (2-4 hours)
1. **Complete:** Finish Attic deployment (if not done in Week 1)
2. **Verify:** Test binary cache sharing between nodes

**Week 2 Total:** 10-20 hours  
**Week 2 Deliverables:**
- Phase 2: All 5 tasks complete

---

## 💡 Suggested Approach

### For Team Leads

1. **Assign Phase 1 to a junior developer** - Low risk, high learning value
2. **Assign Phase 2 tasks to senior developers** - Requires more Nix expertise
3. **Coordinate with SCS infrastructure team** - Needed for P2.3 (Attic) and P3.x

### For Solo Developers

1. **Start with Phase 1** - Build confidence and understanding
2. **Move to Phase 2** - Focus on P2.3 (Attic) first - highest ROI for SCS
3. **Tackle Phase 3 incrementally** - As time permits

### For Infrastructure Team

1. **Prioritize P2.3** - Attic binary cache is critical for air-gapped environment
2. **Coordinate P2.5** - disko configurations need node access for testing
3. **Plan for P3.x** - NixOS appliance images require infrastructure changes

---

## 📊 Success Metrics

| Metric | Phase 0 | Phase 1 | Phase 2 | Phase 3 |
|--------|---------|---------|---------|---------|
| Files with consistent formatting | 268 | 270+ | 270+ | 270+ |
| CI checks passing | ✅ | ✅+eval | ✅+eval+int | ✅+eval+int |
| Binary cache configured | ❌ | ❌ | ✅ | ✅ |
| Secrets encrypted | ❌ | ❌ | ✅ | ✅ |
| Disk partitioning declarative | ❌ | ❌ | ✅ | ✅ |
| Container images via Nix | ❌ | ❌ | 2-3 | 57 |
| Integration test coverage | ❌ | ❌ | 3-5 | 57 |

---

## 🎉 Conclusion

This action plan provides a **clear, achievable path** to modernizing openDesk-Nix with nix-best-practices and DevGuard patterns. The improvements are:

- ✅ **Prioritized** - High-ROI tasks first
- ✅ **Phased** - Logical progression from simple to complex
- ✅ **Realistic** - Achievable with available resources
- ✅ **High-impact** - Significant benefits for the project
- ✅ **Aligned** - With DevGuard, nix-best-practices, and SCS requirements

**Next Immediate Action:** Start with Phase 1 (P1.1-P1.4) - just 6-11 hours of work with very high ROI!

---

## 📚 References

- **[FUTHER-IMPROVEMENTS.md](FUTHER-IMPROVEMENTS.md)** - Detailed analysis of all improvements
- **[DEVGUARD-PR2843-INTEGRATION.md](../security/DEVGUARD-PR2843-INTEGRATION.md)** - DevGuard PR integration details
- **[nix-best-practices](~/git/nix-best-practices/)** - Source of patterns and examples
- **[DevGuard Repository](https://github.com/l3montree-dev/devguard)** - Pattern inspiration

---

**Document Version:** 1.0.0  
**Last Updated:** 2026-08-12  
**Author:** openDesk Edu Team
