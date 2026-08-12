# Test Strategy for opendesk-nix

**Version:** 1.0  
**Date:** 2026-08-10  
**Based on:** `~/git/nix-best-practices/docs/10-integration-testing.md`

---

## 🎯 Vision

Comprehensive testing strategy that ensures:

1. **Reproducibility** - Same inputs → same outputs
2. **Reliability** - Services work together correctly
3. **Security** - No regressions in security posture
4. **Performance** - Acceptable build and runtime performance

---

## 📊 Test Pyramid

```
                    ┌─────────────────┐
                    │   E2E Tests     │  (5% - Manual/CI)
                    │   Production    │
                    └────────┬────────┘
                             │
              ┌──────────────┴──────────────┐
              │   Integration Tests         │  (25% - CI)
              │   Multi-Service Scenarios   │
              └──────────────┬──────────────┘
                             │
          ┌──────────────────┴──────────────────┐
          │   Unit Tests                        │  (50% - CI)
          │   Module Tests, Formatter, Linter   │
          └──────────────────┬──────────────────┘
                             │
┌────────────────────────────┴────────────────────────────┐
│   Eval Tests                                            │  (20% - CI)
│   Flake Evaluation, Syntax Checks                       │
└─────────────────────────────────────────────────────────┘
```

---

## 🧪 Test Categories

### 1. Eval Tests (Fastest - < 10s)

**Purpose:** Catch syntax errors and evaluation failures early

**Location:** `flake.nix` checks

```nix
checks = {
  # Basic evaluation
  eval = self.nixosConfigurations.k3s-node.config.system.build.toplevel;
  
  # Formatting
  formatting = treefmtEval.config.build.check self;
  
  # Schema validation
  schema-check = pkgs.runCommand "schema-check" {} ''
    nix eval .#schema > $out
  '';
};
```

**Test Cases:**
- [ ] `nix flake check` passes
- [ ] All Nix files parse correctly
- [ ] All imports resolve
- [ ] No circular dependencies
- [ ] Schema validation passes

**CI Integration:**
```yaml
# .gitlab-ci.yml
eval-check:
  script:
    - nix flake check --eval-only
  rules:
    - changes:
        - "*.nix"
```

---

### 2. Unit Tests (Fast - < 60s)

**Purpose:** Test individual modules and functions

**Location:** `tests/unit/`

#### 2.1 Module Tests

**File:** `tests/unit/mariadb-module.nix`

```nix
{ pkgs, ... }: {
  name = "mariadb-module";

  nodes = {
    machine = { ... }: {
      imports = [ ./platform/nix/nixos/services.nix ];
      services.mariadb.enable = true;
    };
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("mariadb.service")
    machine.succeed("mysqladmin ping")
  '';
}
```

**Test Cases:**
- [ ] Service starts successfully
- [ ] Service listens on correct port
- [ ] Default configuration applied
- [ ] Custom options override defaults
- [ ] Service stops cleanly

#### 2.2 Function Tests

**File:** `tests/unit/k8s-functions.nix`

```nix
{ pkgs, ... }:
let
  k8s = import ./platform/nix/k8s.nix { inherit pkgs; };
in {
  name = "k8s-functions";

  testScript = ''
    # Test deployment generation
    deployment = k8s.mkDeployment {
      name = "test";
      image = "nginx:latest";
      replicas = 3;
    };
    
    assert deployment.metadata.name == "test";
    assert deployment.spec.replicas == 3;
    assert len(deployment.spec.template.spec.containers) == 1;
  '';
}
```

**Test Cases:**
- [ ] `mkDeployment` generates correct YAML
- [ ] `mkService` generates correct YAML
- [ ] `mkConfigMap` handles special characters
- [ ] `mkSecret` base64 encodes properly
- [ ] `mkIngress` creates valid routes

---

### 3. Integration Tests (Medium - 60-300s)

**Purpose:** Test service-to-service interactions

**Location:** `tests/integration/`

#### 3.1 Single Service Tests

**File:** `tests/integration/mariadb.nix`

```nix
{ pkgs, ... }: {
  name = "mariadb-integration";

  nodes = {
    server = { ... }: {
      services.mysql = {
        enable = true;
        package = pkgs.mariadb;
        initialDatabases = [{ name = "opendesk"; }];
      };
      networking.firewall.allowedTCPPorts = [ 3306 ];
    };

    client = { ... }: {
      environment.systemPackages = [ pkgs.mariadb ];
    };
  };

  testScript = ''
    start_all()
    server.wait_for_unit("mysql.service")
    server.wait_for_open_port(3306)
    client.wait_for_unit("network-online.target")
    
    # Test connectivity
    client.succeed(
      "mysql -h server -P 3306 -u root -e 'SHOW DATABASES;' | grep opendesk"
    )
    
    # Test data operations
    client.succeed(
      "mysql -h server -P 3306 -u root opendesk -e 'CREATE TABLE test (id INT);'"
    )
    client.succeed(
      "mysql -h server -P 3306 -u root opendesk -e 'INSERT INTO test VALUES (1);'"
    )
    result = client.succeed(
      "mysql -h server -P 3306 -u root opendesk -e 'SELECT * FROM test;'"
    )
    assert "1" in result
  '';
}
```

**Test Cases:**
- [ ] Service starts and is ready
- [ ] Network connectivity works
- [ ] Default database created
- [ ] CRUD operations succeed
- [ ] Firewall rules correct

#### 3.2 Multi-Service Tests

**File:** `tests/integration/ilias-mariadb.nix`

```nix
{ pkgs, ... }: {
  name = "ilias-mariadb-integration";

  nodes = {
    mariadb = { ... }: {
      services.mysql = {
        enable = true;
        package = pkgs.mariadb;
        initialDatabases = [{ name = "ilias"; }];
      };
      networking.firewall.allowedTCPPorts = [ 3306 ];
    };

    ilias = { ... }: {
      imports = [ ./platform/nix/nixos/services.nix ];
      services.ilias = {
        enable = true;
        database.host = "mariadb";
        database.name = "ilias";
      };
    };
  };

  testScript = ''
    start_all()
    
    # Wait for MariaDB
    mariadb.wait_for_unit("mysql.service")
    mariadb.wait_for_open_port(3306)
    
    # Wait for ILIAS
    ilias.wait_for_unit("ilias.service")
    ilias.wait_for_open_port(80)
    
    # Test ILIAS can connect to database
    ilias.succeed("curl -s http://localhost/login | grep -i 'login'")
    
    # Test database has ILIAS tables
    mariadb.succeed(
      "mysql -u root ilias -e 'SHOW TABLES;' | grep ilias_"
    )
  '';
}
```

**Test Cases:**
- [ ] Database service ready first
- [ ] Application service starts
- [ ] Application connects to database
- [ ] Application responds to HTTP
- [ ] Database has expected schema

#### 3.3 Full Stack Tests

**File:** `tests/integration/full-stack.nix`

```nix
{ pkgs, ... }: {
  name = "full-stack-integration";

  nodes = {
    database = { ... }: {
      services.mysql.enable = true;
    };
    
    cache = { ... }: {
      services.redis.enable = true;
    };
    
    app = { ... }: {
      services.ilias.enable = true;
      services.redis.client = "cache";
    };
    
    ingress = { ... }: {
      services.nginx.enable = true;
      services.nginx.virtualHosts."app.local" = {
        locations."/" = "http://app:80";
      };
    };
  };

  testScript = ''
    start_all()
    
    # Wait for all services
    database.wait_for_unit("mysql.service")
    cache.wait_for_unit("redis.service")
    app.wait_for_unit("ilias.service")
    ingress.wait_for_unit("nginx.service")
    
    # Test full stack
    ingress.succeed("curl -s http://app.local | grep -i 'login'")
    
    # Test database connectivity from app
    app.succeed("mysql -h database -u root -e 'SHOW DATABASES;'")
    
    # Test cache connectivity from app
    app.succeed("redis-cli -h cache ping | grep PONG")
  '';
}
```

**Test Cases:**
- [ ] All services start in correct order
- [ ] Network connectivity between all services
- [ ] Application responds through ingress
- [ ] Database operations work
- [ ] Cache operations work
- [ ] Health checks pass

---

### 4. E2E Tests (Slowest - 5-30 min)

**Purpose:** Test complete deployment scenarios

**Location:** `tests/e2e/`

#### 4.1 Kubernetes Deployment Test

**File:** `tests/e2e/k8s-deployment.nix`

```nix
{ pkgs, ... }: {
  name = "k8s-deployment";

  nodes = {
    k3s = pkgs.nixosTest {
      name = "k3s-cluster";
      config = ./configurations/k3s-node.nix;
    };
  };

  testScript = ''
    k3s.start()
    k3s.wait_for_unit("k3s.service")
    
    # Wait for Kubernetes ready
    k3s.wait_for_success("kubectl get nodes | grep Ready")
    
    # Deploy test workload
    k3s.succeed("kubectl apply -f ./examples/basic/mariadb.yaml")
    k3s.wait_for_success("kubectl wait --for=condition=available deployment/mariadb --timeout=300s")
    
    # Test service accessibility
    k3s.succeed("kubectl exec -it pod/test-client -- mysql -h mariadb -e 'SELECT 1'")
    
    # Verify persistent storage
    k3s.succeed("kubectl exec -it pod/mariadb-0 -- mysql -e 'CREATE TABLE test (id INT)'")
    k3s.succeed("kubectl exec -it pod/mariadb-0 -- mysql -e 'INSERT INTO test VALUES (1)'")
    k3s.succeed("kubectl exec -it pod/mariadb-0 -- mysql -e 'SELECT * FROM test' | grep 1")
  '';
}
```

**Test Cases:**
- [ ] K3s cluster created
- [ ] All nodes Ready
- [ ] Deployments succeed
- [ ] Services accessible
- [ ] Persistent storage works
- [ ] Health checks pass

#### 4.2 Appliance Image Test

**File:** `tests/e2e/appliance-image.nix`

```nix
{ pkgs, ... }: {
  name = "appliance-image-e2e";

  nodes = {
    builder = { ... }: {};
    vm = pkgs.nixosTest {
      name = "appliance-vm";
      config = ./configurations/k3s-node.nix;
    };
  };

  testScript = ''
    # Build image
    builder.succeed("nix build .#image-k3s-node")
    
    # Verify image
    builder.succeed("file result/ | grep -E 'ext4|squashfs'")
    builder.succeed("test -f result/verity-hash.txt")
    
    # Start VM with image
    vm.start()
    
    # Verify boot
    vm.wait_for_unit("multi-user.target")
    
    # Verify K3s running
    vm.succeed("systemctl is-active k3s")
    vm.succeed("kubectl get nodes | grep Ready")
    
    # Verify dm-verity
    vm.succeed("test -e /dev/dm-0")
    
    # Verify A/B partitions
    vm.succeed("partx -l /dev/vda | grep -E 'RootA|RootB'")
  '';
}
```

**Test Cases:**
- [ ] Image builds successfully
- [ ] Image format correct
- [ ] dm-verity hash generated
- [ ] VM boots from image
- [ ] K3s starts in VM
- [ ] A/B partitions present

---

## 🔄 CI/CD Integration

### GitLab CI Configuration

```yaml
# .gitlab-ci.yml

stages:
  - eval
  - unit
  - integration
  - e2e
  - deploy

variables:
  NIX_CHANNEL: "nixos-24.11"

# Eval stage
eval-check:
  stage: eval
  script:
    - nix flake check --eval-only
  rules:
    - changes:
        - "*.nix"
        - "flake.*"

# Unit tests
unit-tests:
  stage: unit
  script:
    - nix flake check .#formatting
    - nix flake check .#unit
  rules:
    - changes:
        - "tests/unit/*"
        - "platform/nix/*"

# Integration tests
integration-tests:
  stage: integration
  script:
    - nix flake check .#integration
  rules:
    - changes:
        - "tests/integration/*"
        - "platform/nix/*"
        - "configurations/*"

# E2E tests
e2e-tests:
  stage: e2e
  script:
    - nix flake check .#e2e
  rules:
    - push:
        branches:
          - main
          - release/*
    - merge_request_event

# Deploy to staging
deploy-staging:
  stage: deploy
  script:
    - nix run .#deploy-kubernetes -- --environment staging
  rules:
    - push:
        branches:
          - main
  when: manual
```

---

## 📊 Test Coverage Goals

| Category | Current | Target | Timeline |
|----------|---------|--------|----------|
| **Eval Tests** | ✅ 100% | ✅ 100% | Phase 1 |
| **Unit Tests** | 0% | 80% | Phase 2 |
| **Integration Tests** | 5% | 100% (critical services) | Phase 3 |
| **E2E Tests** | 0% | 5 scenarios | Phase 4 |

**Critical Services for Integration Testing:**
1. MariaDB
2. PostgreSQL
3. Redis
4. Keycloak
5. ILIAS
6. Nextcloud
7. Moodle
8. SOGo

---

## 🎯 Success Criteria

### Phase 1 (Week 1) ✅
- [x] `nix flake check` passes
- [x] treefmt formatting enforced
- [x] Basic integration test passes

### Phase 2 (Week 2-3)
- [ ] 10+ unit tests passing
- [ ] All critical modules tested
- [ ] CI pipeline green

### Phase 3 (Week 4-5)
- [ ] 20+ integration tests passing
- [ ] All critical services tested
- [ ] Multi-service scenarios validated

### Phase 4 (Week 6-8)
- [ ] 5+ E2E tests passing
- [ ] Full stack scenarios validated
- [ ] Production deployment tested

---

## 🛠️ Tooling

| Tool | Purpose | Status |
|------|---------|--------|
| **nix flake check** | Eval + CI gates | ✅ |
| **treefmt** | Formatting | ✅ |
| **statix** | Linting | ✅ |
| **deadnix** | Dead code | ✅ |
| **testers.runNixOSTest** | Integration tests | ✅ |
| **QEMU** | VM testing | ⏳ |
| **Playwright** | E2E browser tests | ⏳ |
| **pytest** | Python integration tests | ⏳ |

---

## 📚 References

- `~/git/nix-best-practices/docs/10-integration-testing.md`
- `~/git/nix-best-practices/examples/integration-test.nix`
- NixOS manual: https://nixos.org/manual/nixos/stable/#sec-running-tests

---

**Status:** Draft  
**Reviewers:** Team lead  
**Approval:** Pending
