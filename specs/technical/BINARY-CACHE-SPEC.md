# Binary Cache Specification

**Version:** 1.0  
**Date:** 2026-08-10  
**Status:** Draft - Phase 2 Implementation  
**Based on:** `~/git/nix-best-practices/docs/05-binary-cache.md`

---

## 1. Overview

### 1.1 Purpose

Provide a self-hosted binary cache for the air-gapped SCS K3s cluster to:

- Eliminate dependency on external `cache.nixos.org`
- Speed up builds via cached derivations
- Ensure reproducible builds across all nodes
- Support offline development and deployment

### 1.2 Scope

- Attic server deployment on Ceph RGW backend
- Client configuration for all build machines
- post-build-hook for automatic uploads
- CI/CD integration

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    SCS Air-Gapped Network                       │
│                                                                 │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐        │
│  │  CI Runner  │    │  Dev Machine│    │ Build Node  │        │
│  │  (GitLab)   │    │  (Workstation)│   │  (Dedicated)│       │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘        │
│         │                  │                  │                │
│         └──────────────────┼──────────────────┘                │
│                            │                                    │
│                     ┌──────▼──────┐                            │
│                     │   Attic     │  ← S3-compatible            │
│                     │   Server    │     (Ceph RGW)              │
│                     │  :8080      │                            │
│                     └──────┬──────┘                            │
│                            │                                    │
│                     ┌──────▼──────┐                            │
│                     │   Ceph      │  ← Object Storage           │
│                     │   RGW       │     (scs-cluster)           │
│                     └─────────────┘                            │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Specifications

### 3.1 Attic Server Module

**File:** `modules/attic-server.nix`

**Interface:**
```nix
{
  config,
  pkgs,
  lib,
  ...
}: {
  # Options
  options.services.attic-server = {
    enable = lib.mkEnableOption "Attic binary cache server";
    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Address to listen on";
    };
    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port to listen on";
    };
    cacheDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/attic";
      description = "Local cache directory";
    };
    signingKey = lib.mkOption {
      type = lib.types.path;
      description = "Ed25519 signing key path";
    };
    storageBackend = lib.mkOption {
      type = lib.types.enum ["local" "s3" "ceph"];
      default = "ceph";
      description = "Storage backend type";
    };
    s3Endpoint = lib.mkOption {
      type = lib.types.str;
      description = "S3/CEPH RGW endpoint URL";
    };
    s3Bucket = lib.mkOption {
      type = lib.types.str;
      description = "S3 bucket name";
    };
    s3AccessKeyId = lib.mkOption {
      type = lib.types.str;
      description = "S3 access key ID";
    };
    s3SecretKey = lib.mkOption {
      type = lib.types.str;
      description = "S3 secret access key";
    };
  };

  # Implementation
  config = {
    # systemd service definition
    # nginx reverse proxy
    # Ceph RGW integration
    # post-build-hook configuration
  };
}
```

**Constraints:**
- Must support Ceph RGW as S3-compatible backend
- Must use Ed25519 signing keys
- Must run as systemd service with automatic restart
- Must expose metrics endpoint for monitoring

### 3.2 Client Configuration Module

**File:** `modules/binary-cache-client.nix`

**Interface:**
```nix
{
  config,
  pkgs,
  lib,
  ...
}: {
  options.nix.binaryCache = {
    enable = lib.mkEnableOption "Use binary cache";
    url = lib.mkOption {
      type = lib.types.str;
      default = "http://attic.sc
```

### 3.3 Post-Build Hook

**File:** `modules/post-build-hook.nix`

**Interface:**
```nix
{
  config,
  pkgs,
  lib,
  ...
}: {
  options.nix.postBuildHook = {
    enable = lib.mkEnableOption "Automatic upload to binary cache";
    command = lib.mkOption {
      type = lib.types.str;
      description = "Command to run after build";
    };
    maxJobs = lib.mkOption {
      type = lib.types.int;
      default = 4;
      description = "Maximum concurrent upload jobs";
    };
  };
}
```

---

## 4. Deployment Specifications

### 4.1 Server Deployment

**Target:** Dedicated machine on SCS network

**Requirements:**
- 8GB RAM minimum
- 100GB disk for local cache
- Network access to Ceph RGW
- Public IP or internal DNS name

**Deployment Command:**
```bash
nix run .#deploy-attic-server -- --environment scs
```

**Configuration:**
```nix
# configurations/attic-server.nix
{
  imports = [ ./modules/attic-server.nix ];

  services.attic-server = {
    enable = true;
    listenAddress = "0.0.0.0";
    listenPort = 8080;
    storageBackend = "ceph";
    s3Endpoint = "http://ceph.rgw.sc
```

### 4.2 Client Configuration

**Targets:** All build machines, CI runners, NixOS nodes

**Configuration:**
```nix
# configurations/binary-cache-client.nix
{
  imports = [ ./modules/binary-cache-client.nix ];

  nix.binaryCache = {
    enable = true;
    url = "http://attic.sc
```

---

## 5. Testing Specifications

### 5.1 Unit Tests

**File:** `tests/attic-module.nix`

```nix
{ pkgs, ... }: {
  name = "attic-module";

  nodes.server = { ... }: {
    imports = [ ./modules/attic-server.nix ];
    services.attic-server.enable = true;
  };

  testScript = ''
    server.wait_for_unit("attic-server.service")
    server.succeed("curl -s http://localhost:8080/health")
  '';
}
```

### 5.2 Integration Tests

**File:** `tests/attic-integration.nix`

```nix
{ pkgs, ... }: {
  name = "attic-integration";

  nodes = {
    attic = { ... }: {
      imports = [ ./modules/attic-server.nix ];
      services.attic-server.enable = true;
    };

    client = { ... }: {
      imports = [ ./modules/binary-cache-client.nix ];
      nix.binaryCache.enable = true;
    };
  };

  testScript = ''
    # Start Attic server
    attic.wait_for_unit("attic-server.service")
    
    # Build on client with cache
    client.succeed("nix build --substituters http://attic:8080 .#hello")
    
    # Verify path in cache
    attic.succeed("attic list main | grep <hash>")
    
    # Verify client substituted
    client.succeed("nix-store -q --requisites result/ | wc -l > 0")
  '';
}
```

### 5.3 Acceptance Criteria

- [ ] Attic server starts successfully
- [ ] Health endpoint returns 200 OK
- [ ] Client can substitute from cache
- [ ] post-build-hook uploads automatically
- [ ] Ceph RGW stores objects
- [ ] Signing keys verify signatures

---

## 6. Security Specifications

### 6.1 Signing Keys

**Generation:**
```bash
nix-store --generate-binary-cache-key cache.private cache.public
```

**Storage:**
- Private key: `/etc/attic/cache.private` (root only, mode 0600)
- Public key: Distributed to all clients via NixOS configuration

**Rotation:**
- Generate new key pair
- Add new public key to all clients
- Re-sign existing cache entries
- Deprecate old key after 30 days

### 6.2 Access Control

**Authentication:**
- Attic API key for write access
- No authentication for read access (internal network)

**Authorization:**
- Write: CI runners, build machines
- Read: All internal clients

**Network:**
- Attic server: Internal SCS network only
- Ceph RGW: Attic server only

---

## 7. Monitoring Specifications

### 7.1 Metrics

**Endpoint:** `http://attic:8080/metrics`

**Metrics:**
- `attic_cache_size_bytes` - Total cache size
- `attic_cache_objects` - Number of objects
- `attic_cache_hits_total` - Cache hit count
- `attic_cache_misses_total` - Cache miss count
- `attic_upload_duration_seconds` - Upload latency

### 7.2 Alerts

| Alert | Condition | Severity |
|-------|-----------|----------|
| AtticDown | HTTP 500 on health check | 🔴 Critical |
| CacheFull | Disk usage > 90% | 🟠 Warning |
| HighMissRate | Cache miss rate > 50% | 🟡 Info |
| UploadFail | post-build-hook failures > 5/min | 🟠 Warning |

---

## 8. Migration Plan

### 8.1 Phase 1: Setup (Week 1)

1. Deploy Attic server on SCS network
2. Generate signing keys
3. Configure Ceph RGW backend
4. Test basic functionality

### 8.2 Phase 2: Client Migration (Week 2)

1. Configure CI runners to use cache
2. Configure dev machines to use cache
3. Enable post-build-hook on all builders
4. Monitor cache hit rates

### 8.3 Phase 3: Optimization (Week 3)

1. Tune cache retention policies
2. Optimize Ceph RGW performance
3. Set up monitoring and alerts
4. Document operational procedures

---

## 9. Rollback Plan

If Attic cache fails:

1. Disable cache in client configurations
2. Fall back to `cache.nixos.org` via proxy
3. Investigate and fix server issues
4. Re-enable cache when stable

**Rollback Command:**
```bash
# On client
nix.conf = {
  substituters = "https://cache.nixos.org";
  trusted-public-keys = "cache.nixos.org-1:...";
};
```

---

**Status:** Draft  
**Reviewers:** Team lead, SCS infrastructure team  
**Approval:** Pending
