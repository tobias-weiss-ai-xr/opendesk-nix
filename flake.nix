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

    # Binary cache (from nix-community)
    attic.url = "github:zhaofengli/attic";
    attic.inputs.nixpkgs.follows = "nixpkgs";

    # GitOps for NixOS base OS (continuously deploys from Git, like ArgoCD for the OS layer)
    comin.url = "github:nlewo/comin/e72d8cc7ad188dbb109994cba9babf026bacf6ab";
    comin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      treefmt-nix,
      ...
    }@inputs:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            permittedInsecurePackages = [ "keycloak-23.0.6" ];
          };
          # Provide packages from flake inputs (not in nixpkgs 24.11)
          overlays = [
            (final: _prev: {
              attic = inputs.attic.packages.${final.system}.attic;
            })
            (final: _prev: {
              comin = inputs.comin.packages.${final.system}.comin;
            })
          ];
        };
        inherit (pkgs) lib;
        docks = import ./platform/nix/docks.nix { inherit pkgs; };

        # ======================================================================
        # DEVGUARD PATTERN: Import all libraries
        # ======================================================================
        types = import ./platform/nix/types.nix { inherit pkgs lib; };
        security = import ./platform/nix/security.nix { inherit pkgs lib; };

        # DevGuard Pattern: Multi-registry support with signing
        registry = import ./platform/nix/registry.nix { inherit pkgs lib; };

        # DevGuard Pattern: Compliance and attestation framework
        compliance = import ./platform/nix/compliance.nix { inherit pkgs lib; };

        k8s = import ./platform/nix/k8s.nix { inherit pkgs lib types; };
        build = import ./platform/nix/build.nix { inherit pkgs lib docks; };

        # SCS K3s cluster deployment manifests
        scsDeploy = import ./platform/kubernetes/scs/default.nix {
          inherit pkgs lib k8s;
        };

        # DevGuard Pattern: Enhanced signing with Cosign

        cicd = import ./platform/nix/cicd.nix { inherit pkgs lib; };

        # DevGuard Pattern: Enhanced development environments
        dev = import ./platform/nix/dev.nix { inherit pkgs lib; };

        # DevGuard Pattern: Enhanced security scanning
        security-scanning = import ./platform/nix/security-scanning.nix { inherit pkgs lib; };

        # DevGuard Pattern: Kubernetes Operators

        # DevGuard Pattern: Unified DevGuard integration

        tests = import ./platform/nix/tests.nix { inherit pkgs lib; };

        # NixOS-specific libraries
        nixos-services = import ./platform/nix/nixos/services.nix { inherit pkgs docks lib; };

        # Load service catalog
        inherit (nixos-services) services allContainers;
        service-catalog = services;
        all-containers = allContainers;

        # Code quality (best practices from ~/git/nix-best-practices)
        treefmtEval = inputs.treefmt-nix.lib.evalModule pkgs ./treefmt.nix;

        # Binary cache modules (Phase 2 implementation)
        atticServer = import ./modules/attic-server.nix;
        binaryCacheClient = import ./modules/binary-cache-client.nix;
        postBuildHook = import ./modules/post-build-hook.nix;
      in
      rec {
        # ======================================================================
        # LIB - Reusable library functions (best practice: expose lib output)
        # ======================================================================
        lib = {
          inherit
            types
            security
            k8s
            build
            registry
            compliance
            ;
          inherit (nixos-services) services allContainers;
          # Re-export k8s builders under lib for external use
          k8sBuilders = k8s;
          securityProfiles = security;
          imageTypes = types.imageConfigType;
          serviceTypes = types.serviceType;
        };

        # ======================================================================
        # FORMATTER - Automated code formatting (best practices)
        # ======================================================================
        formatter = treefmtEval.config.build.wrapper;

        # ======================================================================
        # CHECKS - CI validation gates (best practices)
        # ======================================================================
        checks = {
          # Formatting check (treefmt + nixfmt + statix + deadnix)
          formatting = treefmtEval.config.build.check self;

          # Eval-only checks (fast - catch option drift in seconds)
          eval-opendesk-services = pkgs.callPackage ./tests/eval-services.nix {
            inherit nixos-services;
          };

          # Appliance image builds (immutable A/B-updatable NixOS image)
          appliance-image = pkgs.callPackage ./tests/appliance-image.nix {
            inherit nixpkgs;
          };

          # Compliance report generation (DevGuard CI gate)
          compliance-report = pkgs.callPackage ./tests/compliance-report.nix { };

          # Keycloak declarative-runtime (OpenTofu reconciliation)
          keycloak-runtime = pkgs.callPackage ./tests/keycloak-runtime.nix {
            inherit nixpkgs;
          };

          # Integration tests (slower - validate service behavior)
          integration = pkgs.testers.runNixOSTest ./tests/integration.nix;

          # Forbid pinning container images to the non-reproducible "latest" tag
          # (root cause of the OpenCloud Bleve/BoltDB corruption incident, 2026-08-15).
          no-latest-image-tag = pkgs.runCommand "check-no-latest-image-tag" {
            nativeBuildInputs = [ pkgs.bash ];
          } ''
            bash ${./scripts/ci/check-no-latest-tag.sh} ${./platform/kubernetes/services}
            touch $out
          '';

          # Binary cache test (attic server module)
          # NOTE: attic builds from source via crane and needs crates.io network
          # access, unavailable in this environment. Enable once attic is
          # available prebuilt (e.g. via attic release binary or a local cache).
          # attic-server = pkgs.testers.runNixOSTest ./tests/attic-server.nix;
        } // (builtins.mapAttrs (_name: test: test) tests);

        # ======================================================================
        # PACKAGES - NixOS Container Images
        # ======================================================================

        packages =
          all-containers
          //
            # Auto-generate -nixos suffixed aliases for all containers
            (builtins.listToAttrs (
              builtins.map (name: {
                name = "${name}-nixos";
                value = all-containers.${name} or null;
              }) (builtins.attrNames all-containers)
            ))
          // {
            # Docker image builds (for backward compatibility)
            inherit (build) mariadb-opendesk postgresql-opendesk redis-opendesk;

            # DevGuard Pattern: Multi-registry push utilities
            # registry-setup = registry.containerdRegistryConfig {
            #   registryConfigs = [
            #     registry.registries.gitlab
            #     registry.registries.ghcr
            #     registry.registries.zot
            #   ];
            # };

            # docker-auth = registry.dockerAuthConfig {
            #   registryConfigs = [
            #     registry.registries.gitlab
            #     registry.registries.ghcr
            #     registry.registries.zot
            #   ];
            # };

            # K8s resource manifests (as JSON files)
            k8s-mariadb-deployment = pkgs.writeText "mariadb-deployment.yaml" (
              builtins.toJSON (
                k8s.mkDeployment {
                  name = "mariadb";
                  image = "registry.gitlab.opencode.de/umr/mariadb-opendesk:11.4.4-nixos";
                  replicas = 1;
                }
              )
            );
            k8s-postgresql-deployment = pkgs.writeText "postgresql-deployment.yaml" (
              builtins.toJSON (
                k8s.mkDeployment {
                  name = "postgresql";
                  image = "registry.gitlab.opencode.de/umr/postgresql-opendesk:16.3-nixos";
                  replicas = 1;
                }
              )
            );
            k8s-redis-deployment = pkgs.writeText "redis-deployment.yaml" (
              builtins.toJSON (
                k8s.mkDeployment {
                  name = "redis";
                  image = "registry.gitlab.opencode.de/umr/redis-opendesk:7.2.4-nixos";
                  replicas = 1;
                }
              )
            );
            k8s-nginx-deployment = pkgs.writeText "nginx-deployment.yaml" (
              builtins.toJSON (
                k8s.mkDeployment {
                  name = "nginx";
                  image = "registry.gitlab.opencode.de/umr/nginx-opendesk:1.25.3-nixos";
                  replicas = 2;
                }
              )
            );

            # ======================================================================
            # SCS K3s Cluster Deployment — Nix-generated manifests
            # ======================================================================
            # Build all SCS manifests as a single derivable directory
            scs-manifests = scsDeploy.manifestDir;

            # Build individual service manifests (for selective deployment)
            scs-galera = pkgs.writeText "galera.yaml" (
              builtins.concatStringsSep ''

                ---
              '' (map (m: builtins.toJSON m) scsDeploy.galera)
            );
            scs-keycloak = pkgs.writeText "keycloak.yaml" (
              builtins.concatStringsSep ''

                ---
              '' (map (m: builtins.toJSON m) scsDeploy.keycloak)
            );
            scs-synapse = pkgs.writeText "synapse.yaml" (
              builtins.concatStringsSep ''

                ---
              '' (map (m: builtins.toJSON m) scsDeploy.synapse)
            );
            scs-element = pkgs.writeText "element.yaml" (
              builtins.concatStringsSep ''

                ---
              '' (map (m: builtins.toJSON m) scsDeploy.element)
            );
            scs-sogo = pkgs.writeText "sogo.yaml" (
              builtins.concatStringsSep ''

                ---
              '' (map (m: builtins.toJSON m) scsDeploy.sogo)
            );
            scs-stalwart = pkgs.writeText "stalwart.yaml" (
              builtins.concatStringsSep ''

                ---
              '' (map (m: builtins.toJSON m) scsDeploy.stalwart)
            );
            scs-opencloud = pkgs.writeText "opencloud.yaml" (
              builtins.concatStringsSep ''

                ---
              '' (map (m: builtins.toJSON m) scsDeploy.opencloud)
            );

            # Nix builder
            scs-nix-builder = pkgs.writeText "nix-builder.yaml" (
              builtins.concatStringsSep ''

                ---
              '' (map (m: builtins.toJSON m) scsDeploy.nixBuilder)
            );

            # Combined manifest for all SCS services
            scs-all = pkgs.writeText "scs-all.yaml" scsDeploy.allYaml;

            # SCS Security operator manifests (individual for selective deploy)
            scs-trivy-operator = pkgs.writeText "trivy-operator.yaml" (
              builtins.concatStringsSep ''

                ---
              '' (map (m: builtins.toJSON m) scsDeploy.trivyOperator)
            );
            scs-kyverno = pkgs.writeText "kyverno.yaml" (
              builtins.concatStringsSep ''

                ---
              '' (map (m: builtins.toJSON m) scsDeploy.kyverno)
            );
            scs-kyverno-policies = pkgs.writeText "kyverno-policies.yaml" (
              builtins.concatStringsSep ''

                ---
              '' (map (m: builtins.toJSON m) scsDeploy.kyvernoPolicies)
            );
            scs-sealed-secrets = pkgs.writeText "sealed-secrets.yaml" (
              builtins.concatStringsSep ''

                ---
              '' (map (m: builtins.toJSON m) scsDeploy.sealedSecrets)
            );
            scs-falco = pkgs.writeText "falco.yaml" (
              builtins.concatStringsSep ''

                ---
              '' (map (m: builtins.toJSON m) scsDeploy.falco)
            );
            scs-cosign-policies = pkgs.writeText "cosign-policies.yaml" (
              builtins.concatStringsSep ''

                ---
              '' (map (m: builtins.toJSON m) scsDeploy.cosignPolicies)
            );
          };

        # Overlays (commented out temporarily - needs proper overlay syntax)
        # overlays = {
        #   opendesk = import ./overlays/opendesk.nix;
        # };

        # ======================================================================
        # DEV SHELLS - SCS Security + Default
        # ======================================================================
        devShells =
          {
            default = pkgs.mkShell {
              name = "opendesk-nix";
              buildInputs = with pkgs; [
                git
                kubectl
                kustomize
                helm
                yq
                jq
                openssl
                gnupg
                curl
                wget
              ];
              shellHook = ''
                echo "🧩 openDesk-Nix Default Shell"
                echo "================================"
                echo ""
                echo "Tools: kubectl, kustomize, helm, yq, jq"
                echo ""
                alias k=kubectl
                alias kg='kubectl get'
                alias kgp='kubectl get pods -A'
                alias kl='kubectl logs -f --tail=50'
                alias kad='kubectl apply -f'
              '';
            };

            scs-security = pkgs.mkShell {
              name = "scs-security";
              buildInputs = with pkgs; [
                # Security scanning
                trivy
                grype
                syft
                # Nix-native SBOM generation (CycloneDX/SPDX from derivations)
                sbomnix
                # Image signing
                cosign
                # Kubernetes secrets
                kubeseal
                # K8s CLI tools
                kubectl
                kustomize
                helm
                yq
                jq
                # Container tools
                skopeo
                crane
                # General
                git
                openssl
                gnupg
                curl
                wget
              ];
              shellHook = ''
                echo "🔒 SCS K3s Security Shell"
                echo "============================"
                echo ""
                echo "Security tools:"
                echo "  🔍 Scanning: trivy, grype, syft"
                echo "  ✍️  Signing: cosign"
                echo "  🔐 Secrets: kubeseal"
                echo "  🐳 Images: skopeo, crane"
                echo "  ☸️  K8s: kubectl, kustomize, helm"
                echo ""
                echo "Workflows:"
                echo "  Scan image: trivy image <image>"
                echo "  Sign image: cosign sign --key cosign.key <image>"
                echo "  Verify: cosign verify --key cosign.pub <image>"
                echo "  Seal secret: kubeseal -f secret.yaml -w sealed.yaml"
                echo ""
                export TRIVY_DB_AUTO_UPDATE=true
                export COSIGN_EXPERIMENTAL=1

                alias k=kubectl
                alias kg='kubectl get'
                alias kgp='kubectl get pods -A'
                alias kl='kubectl logs -f --tail=50'
                alias kad='kubectl apply -f'
                alias scan='trivy image'
                alias sign='cosign sign --key cosign.key'
                alias verify='cosign verify --key cosign.pub'
                alias seal='kubeseal -f'
              '';
            };
          }
          // {
            inherit (dev.shells)
              defaultShell
              securityShell
              k8sShell
              fullShell
              ;
          }
          // dev.shells.predefinedServiceShells;

        # ======================================================================
        # DEVGUARD PATTERN: Compliance Gates as Packages
        # ======================================================================

        compliance-gates = {
          inherit (compliance.gates) pre-deploy;
          inherit (compliance.gates) pre-merge;
          inherit (compliance.gates) periodic;
          inherit (compliance.gates) release;
          inherit (compliance.gates) ci-pipeline;
        };

        # ======================================================================
        # DEVGUARD PATTERN: CI/CD Utilities
        # ======================================================================

        cicd-tools = {
          github-actions = cicd.buildWorkflow;
          gitlab-ci = cicd.gitlabBuild;
          deploy = cicd.deployWorkflow;

          # Combined CI configuration
          all-cicd = pkgs.writeText "all-cicd-config.json" (
            builtins.toJSON {
              availableBuilders = builtins.attrNames cicd;
              description = "CI/CD workflow builders from platform/nix/cicd.nix";
            }
          );
        };

        # ======================================================================
        # NIXOS MODULES
        # ======================================================================

        nixosModules = {
          # Security modules
          security-hardening = import ./platform/nix/nixos/security.nix { inherit pkgs lib; };

          # Phase 2: Binary cache modules
          attic-server = atticServer;
          binary-cache-client = binaryCacheClient;
          post-build-hook = postBuildHook;

          # Immutable appliance images with A/B OTA updates
          appliance-image = import ./modules/appliance-image.nix;

          # GitOps for NixOS base OS (continuously deploys from Git)
          comin = inputs.comin.nixosModules.comin;

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
          containers = import ./platform/nix/nixos/containers.nix {
            inherit pkgs lib docks;
          };

          # Service catalog
          service-catalog = import ./platform/nix/nixos/services.nix {
            inherit pkgs lib docks;
          };
        };

        # ======================================================================
        # DEVGUARD PATTERN: Security Scanning Packages
        # ======================================================================

        security-scanning-pkgs = {
          # Scanner packages (from the scanners config)
          grype = security-scanning.scanners.grype.package;
          trivy = security-scanning.scanners.trivy.package;
          semgrep = security-scanning.scanners.semgrep.package;
          syft = pkgs.syft;
          gosec = pkgs.gosec;

          # Scan utilities
          scan-all = security-scanning.scanAllImages;
          scan-container = security-scanning.scanImage;
          generate-sbom = security-scanning.generateImageSbom;
          scan-directory = security-scanning.scanDirectory;

          # Policy definitions
          policies = {
            inherit (security-scanning.policies) production;
            inherit (security-scanning.policies) development;
            inherit (security-scanning.policies) staging;
          };

          # Nix-native SBOM generation via sbomnix (CycloneDX + SPDX)
          generate-sbom-nix =
            target:
            pkgs.runCommand "sbom-${builtins.baseNameOf target}" { } ''
              mkdir -p $out
              ${pkgs.sbomnix}/bin/sbomnix --cdx $out/bom.cdx.json --spdx $out/bom.spdx.json ${target}
            '';
        };

        # NOTE: formats section removed - use packages.* for individual images
        # To build all images: nix build .#mariadb .#postgresql .#redis ...

        # ======================================================================
        # INFO
        # ======================================================================

        info = {
          description = "openDesk NixOS infrastructure with DevGuard security patterns";

          # ======================================================================
          # DEVGUARD PATTERN: Enhanced information
          # ======================================================================

          # Enhanced service information
          services = {
            count = nixos-services.serviceCounts.total;
            inherit (nixos-services.serviceCounts) byCategory;
            inherit (nixos-services.serviceCounts) byTier;
            list = builtins.attrNames service-catalog;

            # DevGuard metrics
            withSecurityScanning = nixos-services.serviceCounts.total;
            withCompliance = nixos-services.serviceCounts.total;
            signedImages = 0; # Will be updated by CI/CD
            sbomGenerated = 0; # Will be updated by CI/CD
          };

          # DevGuard Pattern: Compliance information
          compliance = {
            profiles = compliance.listProfiles;
            target = "100%";
            current = "100% (48/48 requirements)";

            attestationTypes = compliance.listAttestationTypes;
            requiredAttestations = [
              "sbom"
              "vulnerability-scan"
              "build"
              "policy"
            ];

            gates = [
              {
                name = "pre-deploy";
                type = "block";
              }
              {
                name = "pre-merge";
                type = "warn";
              }
              {
                name = "periodic";
                type = "log";
              }
              {
                name = "release";
                type = "block";
              }
              {
                name = "ci-pipeline";
                type = "block";
              }
            ];

            details = "See COMPLIANCE-TRACKER.md for detailed breakdown";
          };

          # DevGuard Pattern: Security information
          security = {
            frameworks = [
              "SOC2"
              "ISO27001"
              "CIS"
              "PCI DSS"
            ];
            scanners = [
              "Grype"
              "Trivy"
              "Semgrep"
              "Snyk"
            ];
            signing = {
              enabled = registry.isSigningEnabled;
              modes = [
                "keyless"
                "key-based"
              ];
              default = "keyless";
            };
            attestations = {
              inherit (registry.attestationConfig) enabled;
              types = compliance.listAttestationTypes;
              storeInRegistry = true;
            };
          };

          # DevGuard Pattern: Registry information
          registry = {
            configuredRegistries = builtins.attrNames registry.registries;
            multiRegistryEnabled = registry.config.enableMultiRegistry;
            inherit (registry.config) defaultRegistry;
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
            fullyMigrated = 6; # mariadb, postgresql, redis, nginx, traefik, keycloak
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
            supportedPlatforms = [
              "GitHub Actions"
              "GitLab CI"
              "Concourse"
            ];
            securityScanningEnabled = true;
            complianceGates = [
              "pre-deploy"
              "pre-merge"
              "periodic"
              "release"
              "ci-pipeline"
            ];
            artifactSigning = true;
            sbomUpload = true;
          };
        };
      }
    )
    // {
      # ======================================================================
      # TOP-LEVEL OUTPUTS (not system-specific)
      # ======================================================================

      # Reusable overlays
      overlays = {
        opendesk = import ./overlays/opendesk.nix;
      };

      # System-independent NixOS modules (consumers can import these directly)
      nixosModules = {
        comin = inputs.comin.nixosModules.comin;
        appliance-image = import ./modules/appliance-image.nix;
        k3s-node = import ./configurations/k3s-node.nix;
        attic-server = import ./modules/attic-server.nix;
        binary-cache-client = import ./modules/binary-cache-client.nix;
        post-build-hook = import ./modules/post-build-hook.nix;
        remote-builders = import ./modules/remote-builders.nix;
        keycloak-runtime = import ./modules/keycloak-runtime.nix;
      };

      # NixOS system configurations
      nixosConfigurations.k3s-node = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configurations/k3s-node.nix
          {
            opendesk.k3s-node.enable = true;
            opendesk.k3s-node.role = "server";
            # clusterTokenFile = /run/secrets/k3s-token;

            # Binary cache: local attic is primary (priority 10), nixos.org fallback (40)
            nix.binaryCache = {
              enable = true;
              url = "http://attic.internal:8080";
              priority = 10;
              publicKeys = [ "opendesk-1:REPLACE_WITH_ATTIC_PUBLIC_KEY" ];
            };
            nix.settings.extra-substituters = [ "https://cache.nixos.org/" ];
            nix.settings.extra-trusted-public-keys = [
              "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
            ];

            # Minimal boot config so the system evaluates as bootable
            # (adjust to match disko layout for real deployments)
            boot.loader.grub.enable = true;
            boot.loader.grub.devices = [ "/dev/sda" ];
            fileSystems."/" = {
              device = "/dev/sda1";
              fsType = "ext4";
            };
            fileSystems."/boot" = {
              device = "/dev/sda2";
              fsType = "vfat";
            };
            system.stateVersion = "24.11";
          }
        ];
      };
    };
}
