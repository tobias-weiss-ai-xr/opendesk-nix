# Nix Best Practices Improvements for opendesk-nix

Based on analysis of `~/git/nix-best-practices`, here are the recommended improvements.

## 📊 Current State Assessment

| Area | Status | Best Practice Gap |
|------|--------|-------------------|
| **Formatter** | ❌ Missing | No treefmt (nixfmt + statix + deadnix) |
| **Checks** | ❌ Missing | No `checks` output for CI gates |
| **Binary Cache** | ❌ Missing | No Attic/nix-serve for air-gap |
| **Integration Tests** | ❌ Missing | No `testers.runNixOSTest` |
| **Remote Builders** | ❌ Missing | No distributed build configuration |
| **NixOS Base** | ⚠️ Partial | Services defined, but no appliance images |
| **Secrets** | ⚠️ Partial | agenix patterns exist, not fully integrated |
| **Disk Provisioning** | ❌ Missing | No disko configurations |
| **A/B OTA** | ❌ Missing | No systemd-sysupdate configuration |

## 🎯 Priority Actions

### P0 — Immediate (Week 1)

#### 1. Add treefmt Formatter

**Why:** Automated formatting + linting prevents anti-patterns

**Action:**
```nix
# flake.nix inputs
treefmt-nix.url = "github:numtide/treefmt-nix";

# perSystem
formatter = inputs.treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
checks.formatting = treefmtEval.config.build.check self;
```

**Files to create:**
- `treefmt.nix` - Formatter configuration
- Update `flake.nix` to add `formatter` and `checks.formatting`

#### 2. Add `checks` Output

**Why:** CI gates ensure quality before deployment

**Action:**
```nix
# flake.nix
checks = {
  eval = self.nixosConfigurations.<name>.config.system.build.toplevel;
  formatting = treefmtEval.config.build.check self;
  integration = pkgs.testers.runNixOSTest ./tests/integration.nix;
};
```

#### 3. Add Integration Tests

**Why:** Catch breaking changes early

**Files to create:**
- `tests/integration.nix` - Basic service test (MariaDB)
- `tests/multi-service.nix` - Service-to-service connectivity

### P1 — Foundation (Weeks 2-3)

#### 4. Set Up Attic Binary Cache

**Why:** Essential for air-gapped SCS environment

**Action:**
```nix
# modules/binary-cache.nix
{
  services.attic-server = {
    enable = true;
    listenAddress = "0.0.0.0";
    cacheDir = "/var/lib/attic";
  };
}
```

**Files to create:**
- `modules/binary-cache.nix`
- `modules/post-build-hook.nix`

#### 5. Add disko Disk Partitioning

**Why:** Declarative disk setup with LUKS+TPM

**Files to create:**
- `disko/configurations/scs-node.nix`
- `disko/configurations/k3s-worker.nix`

#### 6. Add NixOS Appliance Images

**Why:** Immutable, reproducible base OS

**Files to create:**
- `modules/appliance-image.nix`
- `configurations/k3s-node.nix`

### P2 — Advanced (Weeks 4-6)

#### 7. A/B OTA Updates

**Why:** Safe, atomic node updates with auto-rollback

**Files to create:**
- `modules/ota-updates.nix`
- `configurations/k3s-node-ota.nix`

#### 8. Remote Builders

**Why:** Faster builds, offload large closures

**Files to create:**
- `modules/remote-builder.nix`
- `deployments/build-machine.nix`

#### 9. Expand Integration Tests

**Why:** Full service catalog validation

**Files to create:**
- `tests/mariadb-connector.nix`
- `tests/postgresql-connector.nix`
- `tests/keycloak-integration.nix`

## 📁 Proposed File Structure

```
opendesk-nix/
├── treefmt.nix                          # NEW: Formatter config
├── tests/                               # NEW: Integration tests
│   ├── integration.nix
│   ├── multi-service.nix
│   └── mariadb-connector.nix
├── modules/                             # NEW: Reusable NixOS modules
│   ├── binary-cache.nix
│   ├── appliance-image.nix
│   ├── ota-updates.nix
│   ├── remote-builder.nix
│   └── secrets.nix
├── disko/                               # NEW: Disk partitioning
│   └── configurations/
│       ├── scs-node.nix
│       └── k3s-worker.nix
├── configurations/                      # NEW: NixOS system configs
│   ├── k3s-node.nix
│   └── k3s-node-ota.nix
├── deployments/                         # NEW: Deployment configs
│   └── build-machine.nix
└── flake.nix                            # UPDATED: Add inputs, checks, formatter
```

## 🔄 Migration Path

### Phase 1: Code Quality (Week 1)
1. Add treefmt to flake
2. Run `nix fmt` to format all Nix files
3. Run `statix fix` and `deadnix --edit` to fix issues
4. Add basic `checks` output
5. Add one integration test

### Phase 2: Binary Cache (Week 2)
1. Deploy Attic server on SCS network
2. Configure all nodes to use cache
3. Add post-build-hook for auto-upload
4. Test cache hits in CI

### Phase 3: NixOS Base (Weeks 3-4)
1. Create appliance image module
2. Define k3s-node configuration
3. Create disko partition configs
4. Test on one SCS node with nixos-anywhere

### Phase 4: Advanced (Weeks 5-6)
1. Add A/B OTA configuration
2. Set up remote builder
3. Expand integration tests
4. Add GPU test support (if needed)

## 📚 Reference Documents

| Document | Location |
|----------|----------|
| Code Quality | `~/git/nix-best-practices/docs/15-code-quality.md` |
| Integration Tests | `~/git/nix-best-practices/docs/10-integration-testing.md` |
| Binary Cache | `~/git/nix-best-practices/docs/05-binary-cache.md` |
| Disk Provisioning | `~/git/nix-best-practices/docs/07-disk-provisioning.md` |
| Appliance Images | `~/git/nix-best-practices/docs/19-appliance-images.md` |
| Deployment | `~/git/nix-best-practices/docs/11-deployment.md` |

## ✅ Success Criteria

- [ ] `nix fmt` passes on all files
- [ ] `nix flake check` passes on CI
- [ ] At least 3 integration tests passing
- [ ] Binary cache serving 80%+ of builds
- [ ] One SCS node running NixOS appliance image
- [ ] A/B OTA tested on non-production node
- [ ] Remote builder configured and tested

---

**Created:** 2026-08-10  
**Based on:** `~/git/nix-best-practices` analysis
