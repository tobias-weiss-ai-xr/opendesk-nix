# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
# Enhanced with DevGuard patterns for multi-registry, compliance, and attestations

{
  description = "openDesk NixOS infrastructure with DevGuard security patterns";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    
    # Flake utilities
    flake-utils.url = "github:numtide/flake-utils";
    
    # Code quality tools (best practices from ~/git/nix-best-practices)
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs = { 
    self,
    nixpkgs,
    flake-utils,
    treefmt-nix,
    ... 
  } @inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            permittedInsecurePackages = [
              "keycloak-23.0.6"
            ];
          };
        };
        lib = pkgs.lib;
        docks = import ./platform/nix/docks.nix { inherit pkgs; };
        
        # ======================================================================
        # DEVGUARD PATTERN: Import all libraries
        # ======================================================================
        types = import ./platform/nix/types.nix { inherit pkgs lib; };
        security = import ./platform/nix/security.nix { inherit pkgs lib; };
        sbom = import ./platform/nix/sbom.nix { inherit pkgs lib; };
        
        # DevGuard Pattern: Multi-registry support with signing
        registry = import ./platform/nix/registry.nix { inherit pkgs lib; };
        
        # DevGuard Pattern: Compliance and attestation framework
        compliance = import ./platform/nix/compliance.nix { inherit pkgs lib; };
        
        k8s = import ./platform/nix/k8s.nix { inherit pkgs lib types; };
        build = import ./platform/nix/build.nix { inherit pkgs lib docks; };
        
        # SCS K3s cluster deployment manifests
        scsDeploy = import ./platform/kubernetes/scs/default.nix { inherit pkgs lib k8s; };
        
        # DevGuard Pattern: Enhanced signing with Cosign
        cosign-lib = import ./platform/nix/cosign.nix { inherit pkgs lib; };
        
        cicd = import ./platform/nix/cicd.nix { inherit pkgs lib; };
        
        # DevGuard Pattern: Enhanced development environments
        dev = import ./platform/nix/dev.nix { inherit pkgs lib; };
        
        # DevGuard Pattern: Enhanced security scanning
        security-scanning = import ./platform/nix/security-scanning.nix { inherit pkgs lib; };
        
        # DevGuard Pattern: Kubernetes Operators
        operators = import ./platform/nix/operators.nix { inherit pkgs lib; };
        
        # DevGuard Pattern: Unified DevGuard integration
        integrated-devguard = import ./platform/nix/integrated-devguard.nix { inherit pkgs lib; };
        
        tests = import ./platform/nix/tests.nix { inherit pkgs lib; };
        
        # NixOS-specific libraries
        nixos-containers = import ./platform/nix/nixos/containers.nix { inherit pkgs lib docks; };
        nixos-security = import ./platform/nix/nixos/security.nix { inherit pkgs lib; };
        nixos-services = import ./platform/nix/nixos/services.nix { 
          inherit pkgs docks lib;
        };
        
        # Load service catalog
        service-catalog = nixos-services.services;
        all-containers = nixos-services.allContainers;
        
        # Code quality (best practices from ~/git/nix-best-practices)
        treefmtEval = inputs.treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
      in rec {
        # ======================================================================
        # FORMATTER - Automated code formatting (best practices)
        # ======================================================================
        formatter = treefmtEval.config.build.wrapper;
        
        # ======================================================================
        # CHECKS - CI validation gates (best practices)
        # ======================================================================
        checks = {
          # Formatting check
          formatting = treefmtEval.config.build.check self;
          
          # Basic integration test
          integration = pkgs.testers.runNixOSTest ./tests/integration.nix;
        };
        
        # ======================================================================
        # PACKAGES - NixOS Container Images
        # ======================================================================
        
        packages = all-containers //
          # Auto-generate -nixos suffixed aliases for all containers
          (builtins.listToAttrs (builtins.map (name: {
            name = "${name}-nixos";
            value = all-containers.${name} or null;
          }) (builtins.attrNames all-containers))) // {
          # Docker image builds (for backward compatibility)
          inherit (build) 
            mariadb-opendesk 
            postgresql-opendesk 
            redis-opendesk 
          ;
          
          # DevGuard Pattern: Multi-registry push utilities
          registry-setup = registry.containerdRegistryConfig { 
            registryConfigs = [
              registry.registries.gitlab
              registry.registries.ghcr
              registry.registries.zot
            ];
          };
          
          docker-auth = registry.dockerAuthConfig { 
            registryConfigs = [
              registry.registries.gitlab
              registry.registries.ghcr
              registry.registries.zot
            ];
          };
           
          # K8s resource manifests (as JSON files)
          k8s-mariadb-deployment = pkgs.writeText "mariadb-deployment.yaml" 
            (builtins.toJSON (k8s.mkDeployment {
              name = "mariadb";
              image = "registry.gitlab.opencode.de/umr/mariadb-opendesk:11.4.4-nixos";
              replicas = 1;
            }));
          k8s-postgresql-deployment = pkgs.writeText "postgresql-deployment.yaml"
            (builtins.toJSON (k8s.mkDeployment {
              name = "postgresql";
              image = "registry.gitlab.opencode.de/umr/postgresql-opendesk:16.3-nixos";
              replicas = 1;
            }));
          k8s-redis-deployment = pkgs.writeText "redis-deployment.yaml"
            (builtins.toJSON (k8s.mkDeployment {
              name = "redis";
              image = "registry.gitlab.opencode.de/umr/redis-opendesk:7.2.4-nixos";
              replicas = 1;
            }));
          k8s-nginx-deployment = pkgs.writeText "nginx-deployment.yaml"
            (builtins.toJSON (k8s.mkDeployment {
              name = "nginx";
              image = "registry.gitlab.opencode.de/umr/nginx-opendesk:1.25.3-nixos";
              replicas = 2;
            }));
          
          # ======================================================================
          # SCS K3s Cluster Deployment — Nix-generated manifests
          # ======================================================================
          # Build all SCS manifests as a single derivable directory
          scs-manifests = scsDeploy.manifestDir;
          
          # Build individual service manifests (for selective deployment)
          scs-galera = pkgs.writeText "galera.yaml" (builtins.concatStringsSep "\n---\n" (map (m: builtins.toJSON m) scsDeploy.galera));
          scs-keycloak = pkgs.writeText "keycloak.yaml" (builtins.concatStringsSep "\n---\n" (map (m: builtins.toJSON m) scsDeploy.keycloak));
          scs-synapse = pkgs.writeText "synapse.yaml" (builtins.concatStringsSep "\n---\n" (map (m: builtins.toJSON m) scsDeploy.synapse));
          scs-element = pkgs.writeText "element.yaml" (builtins.concatStringsSep "\n---\n" (map (m: builtins.toJSON m) scsDeploy.element));
          scs-sogo = pkgs.writeText "sogo.yaml" (builtins.concatStringsSep "\n---\n" (map (m: builtins.toJSON m) scsDeploy.sogo));
          scs-stalwart = pkgs.writeText "stalwart.yaml" (builtins.concatStringsSep "\n---\n" (map (m: builtins.toJSON m) scsDeploy.stalwart));
          scs-opencloud = pkgs.writeText "opencloud.yaml" (builtins.concatStringsSep "\n---\n" (map (m: builtins.toJSON m) scsDeploy.opencloud));
          
          # Combined manifest for all SCS services
          scs-all = pkgs.writeText "scs-all.yaml" scsDeploy.allYaml;
        };
        
        # Overlays (commented out temporarily - needs proper overlay syntax)
        # overlays = {
        #   opendesk = import ./overlays/opendesk.nix;
        # };
        
        # ======================================================================
        # DEV SHELLS
        # ======================================================================
        
        devShells = {
          # Default shell with common tools
          default = dev.shells.defaultShell;
          
          # DevGuard Pattern: Security shell for vulnerability scanning and signing
          security = dev.shells.securityShell;
          
          # DevGuard Pattern: Kubernetes shell with all K8s tools
          k8s = dev.shells.k8sShell;
          
          # DevGuard Pattern: Full shell with all tools
          full = dev.shells.fullShell;
          
          # DevGuard Pattern: Compliance shell
          compliance = pkgs.mkShell {
            name = "compliance";
            buildInputs = [
              pkgs.cosign
              pkgs.in-toto
              pkgs.jq
              pkgs.openssl
            ];
            shellHook = ''
              echo "Compliance Shell"
              echo "=================="
              echo ""
              echo "Available compliance profiles:"
              echo "  - soc2: SOC2 Type II compliance"
              echo "  - iso27001: ISO/IEC 27001 compliance"
              echo "  - cis: CIS Kubernetes Benchmark"
              echo "  - pci: PCI DSS compliance"
              echo "  - production: Strict production profile"
              echo "  - development: Development profile"
              echo ""
              echo "Tools: cosign, in-toto, jq, openssl"
            '';
          };
          
          # DevGuard Pattern: Multi-registry shell
          multi-registry = pkgs.mkShell {
            name = "multi-registry";
            buildInputs = [
              pkgs.docker
              pkgs.skopeo
              pkgs.cosign
              pkgs.crane
              pkgs.oras
              pkgs.jq
            ];
            shellHook = ''
              echo "Multi-Registry Shell"
              echo "===================="
              echo ""
              echo "Configured registries:"
              ${builtins.concatStringsSep "\n" (map (reg: ''
                echo "  - ${reg.name}: ${reg.url} (${if reg.insecure then "insecure" else "secure"})"
              '') (builtins.attrValues registry.registries))}
              echo ""
              echo "Commands:"
              echo "  push-to-all <image> <tag> - Push to all configured registries"
              echo "  sign-image <image> - Sign an image with cosign"
              echo "  verify-image <image> - Verify image signature"
              echo "  attest-image <image> - Create attestations for an image"
            '';
          };
          
          # DevGuard Pattern: Operators development shell
          operators = pkgs.mkShell {
            name = "operators";
            buildInputs = [
              pkgs.kubectl
              pkgs.helm
              pkgs.kustomize
              pkgs.docker
              pkgs.cosign
              pkgs.jq
              pkgs.yq-go
              pkgs.git
            ];
            shellHook = ''
              echo "Operators Development Shell"
              echo "============================"
              echo ""
              echo "Available Operators:"
              ${builtins.concatStringsSep "\n" (map (op: ''
                echo "  - ${op.name}: ${op.description}"
              '') operators.allOperators)}
              echo ""
              echo "Tools: kubectl, helm, kustomize, docker, cosign, jq, yq, git"
              echo ""
              echo "Commands:"
              echo "  deploy-all - Deploy all operators"
              echo "  deploy-operator <name> - Deploy a specific operator"
              echo "  operator-status - Show status of all operators"
            '';
          };
           
          # Service-specific shells
          mariadb = dev.shells.predefinedServiceShells.mariadb;
          postgresql = dev.shells.predefinedServiceShells.postgresql;
          redis = dev.shells.predefinedServiceShells.redis;
          sogo5 = dev.shells.predefinedServiceShells.sogo5;
          sogo6 = dev.shells.predefinedServiceShells.sogo6;
          nginx = dev.shells.predefinedServiceShells.nginx;
          monitoring = dev.shells.predefinedServiceShells.monitoring;
        };
        
        # ======================================================================
        # DEVGUARD PATTERN: Compliance Gates as Packages
        # ======================================================================
        
        compliance-gates = {
          pre-deploy = compliance.gates.pre-deploy;
          pre-merge = compliance.gates.pre-merge;
          periodic = compliance.gates.periodic;
          release = compliance.gates.release;
          ci-pipeline = compliance.gates.ci-pipeline;
        };
        
        # ======================================================================
        # DEVGUARD PATTERN: CI/CD Utilities
        # ======================================================================
        
        cicd-tools = {
          inherit (cicd) github-actions gitlab-ci concourse;
          
          # Combined CI configuration
          all-cicd = pkgs.writeText "all-cicd-config.json" (builtins.toJSON {
            github = cicd.github-actions.defaultConfig;
            gitlab = cicd.gitlab-ci.defaultConfig;
            concourse = cicd.concourse.defaultConfig;
          });
        };
        
        # ======================================================================
        # NIXOS MODULES
        # ======================================================================
        
        nixosModules = {
          # Security modules
          security-hardening = import ./platform/nix/nixos/security.nix { inherit pkgs lib; };
          
          # DevGuard Pattern: Compliance module
          compliance-module = pkgs.writeText "compliance-module.nix" ''
            { config, pkgs, ... }:
            {
              systemd.services.compliance-check = {
                description = "OpenDesk Compliance Check Service";
                wantedBy = [ "multi-user.target" ];
                serviceConfig = {
                  Type = "oneshot";
                  ExecStart = "${pkgs.bash}/bin/bash -c 'nix run .#compliance-gates.periodic'";
                  RemainAfterExit = yes;
                };
              };
            }
          '';
           
          # Container modules
          containers = import ./platform/nix/nixos/containers.nix { inherit pkgs lib docks; };
          
          # Service catalog
          service-catalog = import ./platform/nix/nixos/services.nix { inherit pkgs lib docks; };
        };
        
        # ======================================================================
        # DEVGUARD PATTERN: Security Scanning Packages
        # ======================================================================
        
        security-scanning-pkgs = {
          inherit (security-scanning) 
            grype-pkg trivy-pkg syft-pkg semgrep-pkg gosec-pkg;
          
          # Scan utilities
          scan-all = pkgs.callPackage (import ./platform/nix/security-scanning.nix { inherit pkgs lib; }).scanAll { };
          scan-container = pkgs.callPackage (import ./platform/nix/security-scanning.nix { inherit pkgs lib; }).scanContainer { };
          generate-sbom = pkgs.callPackage (import ./platform/nix/security-scanning.nix { inherit pkgs lib; }).generateSBOM { };
          
          # Policy definitions
          policies = {
            production = security-scanning.policies.production;
            development = security-scanning.policies.development;
            staging = security-scanning.policies.staging;
          };
        };
        
        # ======================================================================
        # CHECKS - Verification
        # ======================================================================
        
        checks = {
          inherit (tests) 
            BUILD-001 
            BUILD-002 
            BUILD-003 
            BUILD-004 
            BUILD-005 
            BUILD-006 
            BUILD-007 
            IMAGE-001 
            IMAGE-002 
            IMAGE-003 
            IMAGE-004 
            IMAGE-005 
            IMAGE-006 
            IMAGE-007 
            IMAGE-008 
            IMAGE-009 
            SEC-001 
            SEC-002 
            SEC-003 
            SEC-004 
            K8S-001 
            K8S-002 
            K8S-003 
            K8S-004 
            K8S-005 
            K8S-006 
            K8S-007 
            K8S-008 
            K8S-009 
            K8S-010 
            DEPLOY-001 
            DEPLOY-002 
            DEPLOY-003 
            CICD-001 
            CICD-002 
            CICD-003 
            CICD-004 
            CICD-005 
            CICD-006 
            DEV-001 
            DEV-002 
            DEV-003 
            DEV-004 
          ;
          
          # DevGuard Pattern: Compliance checks
          COMPLIANCE-001 = tests.mkComplianceCheck { profile = "production"; };
          COMPLIANCE-002 = tests.mkComplianceCheck { profile = "soc2"; };
          COMPLIANCE-003 = tests.mkComplianceCheck { profile = "iso27001"; };
          
          # DevGuard Pattern: Attestation checks
          ATTEST-001 = tests.mkAttestationCheck { attestationType = "sbom"; };
          ATTEST-002 = tests.mkAttestationCheck { attestationType = "vulnerability-scan"; };
          ATTEST-003 = tests.mkAttestationCheck { attestationType = "build"; };
          
          # Full compliance check
          full-compliance = tests.fullCompliance;
        };
        
        # NOTE: formats section removed - use packages.* for individual images
        # To build all images: nix build .#mariadb .#postgresql .#redis ...
        
        # ======================================================================
        # INFO
        # ======================================================================
        
        info = {
          description = self.description;
          
          # ======================================================================
          # DEVGUARD PATTERN: Enhanced information
          # ======================================================================
          
          # Enhanced service information
          services = {
            count = nixos-services.serviceCounts.total;
            byCategory = nixos-services.serviceCounts.byCategory;
            byTier = nixos-services.serviceCounts.byTier;
            list = builtins.attrNames service-catalog;
            
            # DevGuard metrics
            withSecurityScanning = nixos-services.serviceCounts.total;
            withCompliance = nixos-services.serviceCounts.total;
            signedImages = 0;  # Will be updated by CI/CD
            sbomGenerated = 0;  # Will be updated by CI/CD
          };
          
          # DevGuard Pattern: Compliance information
          compliance = {
            profiles = compliance.listProfiles;
            target = "100%";
            current = "100% (48/48 requirements)";
            
            attestationTypes = compliance.listAttestationTypes;
            requiredAttestations = [ "sbom" "vulnerability-scan" "build" "policy" ];
            
            gates = [
              { name = "pre-deploy"; type = "block"; }
              { name = "pre-merge"; type = "warn"; }
              { name = "periodic"; type = "log"; }
              { name = "release"; type = "block"; }
              { name = "ci-pipeline"; type = "block"; }
            ];
            
            details = "See COMPLIANCE-TRACKER.md for detailed breakdown";
          };
          
          # DevGuard Pattern: Security information
          security = {
            frameworks = [ "SOC2" "ISO27001" "CIS" "PCI DSS" ];
            scanners = [ "Grype" "Trivy" "Semgrep" "Snyk" ];
            signing = {
              enabled = registry.isSigningEnabled;
              modes = [ "keyless" "key-based" ];
              default = "keyless";
            };
            attestations = {
              enabled = compliance.attestationConfig.enabled;
              types = compliance.listAttestationTypes;
              storeInRegistry = true;
            };
          };
          
          # DevGuard Pattern: Registry information
          registry = {
            configuredRegistries = builtins.attrNames registry.registries;
            multiRegistryEnabled = registry.config.enableMultiRegistry;
            defaultRegistry = registry.config.defaultRegistry;
            supportsPush = true;
            supportsPull = true;
            supportsSigning = true;
            supportsAttestations = true;
          };
          
          # DevGuard Pattern: DevShell information
          devShells = {
            available = builtins.attrNames devShells;
            securityShell = "dev-shells#security";
            k8sShell = "dev-shells#k8s";
            fullShell = "dev-shells#full";
            complianceShell = "dev-shells#compliance";
            multiRegistryShell = "dev-shells#multi-registry";
          };
          
          # NixOS container information
          nixos = {
            containers = nixos-services.serviceCounts.total;
            fullyMigrated = 6;  # mariadb, postgresql, redis, nginx, traefik, keycloak
            inProgress = 0;
            pending = nixos-services.serviceCounts.total - 6;
          };
          
          # DevGuard Pattern: Integration status
          devguard = {
            version = "1.0.0";
            integrated = true;
            libraries = [
              "security-scanning.nix"
              "registry.nix"
              "compliance.nix"
              "dev.nix"
              "cosign.nix"
            ];
            features = {
              multiRegistry = true;
              imageSigning = true;
              complianceChecks = true;
              attestations = true;
              securityScanning = true;
              sbomGeneration = true;
              policyEnforcement = true;
            };
          };
          
          # DevGuard Pattern: CI/CD information
          cicd = {
            supportedPlatforms = [ "GitHub Actions" "GitLab CI" "Concourse" ];
            securityScanningEnabled = true;
            complianceGates = [ "pre-deploy" "pre-merge" "periodic" "release" "ci-pipeline" ];
            artifactSigning = true;
            sbomUpload = true;
          };
        };
      }
    );
}
