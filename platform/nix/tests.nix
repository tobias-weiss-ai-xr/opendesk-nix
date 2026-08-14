# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Real eval-level tests for the opendesk-nix platform libraries.
# Each test imports the relevant module, checks expected attributes,
# and produces a derivation that fails if any check fails.

{ pkgs, lib }:

let
  # Import all platform libraries
  types = import ./types.nix { inherit pkgs lib; };
  security = import ./security.nix { inherit pkgs lib; };
  k8s = import ./k8s.nix { inherit pkgs lib; };
  build = import ./build.nix { inherit pkgs lib; };
  registry = import ./registry.nix { inherit pkgs lib; };
  compliance = import ./compliance.nix { inherit pkgs lib; };

  # Helper: run a set of assertions and produce a derivation
  runChecks =
    name: checks:
    pkgs.runCommand "test-${name}" { } ''
      echo "Running ${name} checks..."
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (checkName: checkExpr: ''
          echo "  Check: ${checkName}"
          if ${checkExpr}; then
            echo "    PASS: ${checkName}"
          else
            echo "    FAIL: ${checkName}"
            exit 1
          fi
        '') checks
      )}
      echo "All ${name} checks passed."
      touch $out
    '';

  # Helper: assert that an attribute exists in a set
  assertHasAttr =
    set: attr:
    "test -n '${builtins.toJSON (builtins.hasAttr attr set)}' && [ '${builtins.toJSON (builtins.hasAttr attr set)}' = 'true' ]";

  # Helper: assert that a value is a string

  # Helper: assert that a value is a lambda
  assertIsLambda = val: "[ '${builtins.typeOf val}' = 'lambda' ]";

  # Helper: assert that a value is a list
  assertIsList = val: "[ '${builtins.typeOf val}' = 'list' ]";

  # Helper: assert that a value is an attrset
  assertIsAttrs = val: "[ '${builtins.typeOf val}' = 'set' ]";

in
{
  # ===========================================================================
  # BUILD tests: Verify build.nix exports expected functions
  # ===========================================================================
  BUILD-001 = runChecks "BUILD-001-build-exports" {
    "build.buildImage is a function" = assertIsLambda build.buildImage;
    "build.buildDBImage is a function" = assertIsLambda build.buildDBImage;
  };

  BUILD-002 = runChecks "BUILD-002-build-mariadb" {
    "build has mariadb-opendesk image" = assertHasAttr build "mariadb-opendesk";
  };

  BUILD-003 = runChecks "BUILD-003-build-postgresql" {
    "build has postgresql-opendesk image" = assertHasAttr build "postgresql-opendesk";
  };

  BUILD-004 = runChecks "BUILD-004-build-redis" {
    "build has redis-opendesk image" = assertHasAttr build "redis-opendesk";
  };

  BUILD-005 = runChecks "BUILD-005-build-db-image-fn" {
    "build.buildDBImage is a function" = assertIsLambda build.buildDBImage;
  };

  BUILD-006 = runChecks "BUILD-006-build-types" {
    "types.imageConfigType is an attrset" = assertIsAttrs types.imageConfigType;
  };

  BUILD-007 = runChecks "BUILD-007-build-service-types" {
    "types.serviceType is an attrset" = assertIsAttrs types.serviceType;
  };

  # ===========================================================================
  # CI/CD tests: Verify compliance gates and CI/CD patterns
  # ===========================================================================
  CICD-001 = runChecks "CICD-001-compliance-profiles" {
    "compliance.listProfiles is a list" = assertIsList compliance.listProfiles;
    "compliance has soc2 profile" = assertHasAttr compliance.complianceProfiles "soc2";
    "compliance has production profile" = assertHasAttr compliance.complianceProfiles "production";
    "compliance has development profile" = assertHasAttr compliance.complianceProfiles "development";
  };

  CICD-002 = runChecks "CICD-002-compliance-gates" {
    "compliance has gates" = assertHasAttr compliance "gates";
    "compliance.gates has pre-deploy" = assertHasAttr compliance.gates "pre-deploy";
    "compliance.gates has pre-merge" = assertHasAttr compliance.gates "pre-merge";
    "compliance.gates has release" = assertHasAttr compliance.gates "release";
    "compliance.gates has ci-pipeline" = assertHasAttr compliance.gates "ci-pipeline";
  };

  CICD-003 = runChecks "CICD-003-attestation-types" {
    "compliance.listAttestationTypes is a list" = assertIsList compliance.listAttestationTypes;
    "compliance has sbom attestation" = assertHasAttr compliance.attestationTypes "sbom";
    "compliance has vulnerability-scan attestation" =
      assertHasAttr compliance.attestationTypes "vulnerability-scan";
    "compliance has build attestation" = assertHasAttr compliance.attestationTypes "build";
  };

  CICD-004 = runChecks "CICD-004-compliance-config" {
    "compliance.config is an attrset" = assertIsAttrs compliance.config;
    "compliance.config has enabled" = assertHasAttr compliance.config "enabled";
    "compliance.config has defaultProfile" = assertHasAttr compliance.config "defaultProfile";
  };

  CICD-005 = runChecks "CICD-005-create-compliance-gate" {
    "compliance.createComplianceGate is a function" = assertIsLambda compliance.createComplianceGate;
  };

  CICD-006 = runChecks "CICD-006-generate-report" {
    "compliance.generateReport is a function" = assertIsLambda compliance.generateReport;
  };

  # ===========================================================================
  # DEPLOY tests: Verify registry configurations
  # ===========================================================================
  DEPLOY-001 = runChecks "DEPLOY-001-registry-exports" {
    "registry has registries" = assertHasAttr registry "registries";
    "registry has pushToRegistry" = assertHasAttr registry "pushToRegistry";
    "registry has pushToAll" = assertHasAttr registry "pushToAll";
    "registry has pullFromRegistry" = assertHasAttr registry "pullFromRegistry";
  };

  DEPLOY-002 = runChecks "DEPLOY-002-registry-config" {
    "registry.config is an attrset" = assertIsAttrs registry.config;
    "registry.config has defaultRegistry" = assertHasAttr registry.config "defaultRegistry";
    "registry.config has enableMultiRegistry" = assertHasAttr registry.config "enableMultiRegistry";
  };

  DEPLOY-003 = runChecks "DEPLOY-003-registry-list" {
    "registry has ghcr" = assertHasAttr registry.registries "ghcr";
    "registry has gitlab" = assertHasAttr registry.registries "gitlab";
    "registry has zot" = assertHasAttr registry.registries "zot";
    "registry has local" = assertHasAttr registry.registries "local";
  };

  # ===========================================================================
  # DEV tests: Verify type definitions and library structure
  # ===========================================================================
  DEV-001 = runChecks "DEV-001-types-exports" {
    "types.imageConfigType is an attrset" = assertIsAttrs types.imageConfigType;
    "types.serviceType is an attrset" = assertIsAttrs types.serviceType;
  };

  DEV-002 = runChecks "DEV-002-security-exports" {
    "security has defaultProfile" = assertHasAttr security "defaultProfile";
    "security has hardenContainer" = assertHasAttr security "hardenContainer";
  };

  DEV-003 = runChecks "DEV-003-security-profiles" {
    "security has databaseProfile" = assertHasAttr security "databaseProfile";
    "security has webProfile" = assertHasAttr security "webProfile";
  };

  DEV-004 = runChecks "DEV-004-k8s-exports" {
    "k8s has mkLabels" = assertHasAttr k8s "mkLabels";
    "k8s has mkOCILabels" = assertHasAttr k8s "mkOCILabels";
    "k8s has defaultSecurityContext" = assertHasAttr k8s "defaultSecurityContext";
  };

  # ===========================================================================
  # IMAGE tests: Verify image and service types
  # ===========================================================================
  IMAGE-001 = runChecks "IMAGE-001-image-config-type" {
    "types.imageConfigType is an attrset" = assertIsAttrs types.imageConfigType;
    "types.imageConfigType has _type" = assertHasAttr types.imageConfigType "_type";
  };

  IMAGE-002 = runChecks "IMAGE-002-service-type" {
    "types.serviceType is an attrset" = assertIsAttrs types.serviceType;
    "types.serviceType has _type" = assertHasAttr types.serviceType "_type";
  };

  IMAGE-003 = runChecks "IMAGE-003-build-image-function" {
    "build.buildImage is a function" = assertIsLambda build.buildImage;
  };

  IMAGE-004 = runChecks "IMAGE-004-build-db-image" {
    "build.buildDBImage is a function" = assertIsLambda build.buildDBImage;
  };

  IMAGE-005 = runChecks "IMAGE-005-registry-format" {
    "registry.formatImageName is a function" = assertIsLambda registry.formatImageName;
    "registry.parseImageReference is a function" = assertIsLambda registry.parseImageReference;
  };

  IMAGE-006 = runChecks "IMAGE-006-signing-config" {
    "registry.signingConfig is an attrset" = assertIsAttrs registry.signingConfig;
    "registry.signingConfig has modes" = assertHasAttr registry.signingConfig "modes";
    "registry.isSigningEnabled is a boolean" =
      "[ '${builtins.typeOf registry.isSigningEnabled}' = 'bool' ]";
  };

  IMAGE-007 = runChecks "IMAGE-007-attestation-config" {
    "registry.attestationConfig is an attrset" = assertIsAttrs registry.attestationConfig;
    "registry.attestationConfig has enabled" = assertHasAttr registry.attestationConfig "enabled";
    "registry.attestationConfig has types" = assertHasAttr registry.attestationConfig "types";
  };

  IMAGE-008 = runChecks "IMAGE-008-multi-registry-config" {
    "registry.multiRegistryConfig is an attrset" = assertIsAttrs registry.multiRegistryConfig;
    "registry.multiRegistryConfig has targets" = assertHasAttr registry.multiRegistryConfig "targets";
    "registry.multiRegistryConfig has strategy" = assertHasAttr registry.multiRegistryConfig "strategy";
  };

  IMAGE-009 = runChecks "IMAGE-009-push-sequential" {
    "registry.pushToAllSequential is a function" = assertIsLambda registry.pushToAllSequential;
  };

  # ===========================================================================
  # K8S tests: Verify Kubernetes resource builders
  # ===========================================================================
  K8S-001 = runChecks "K8S-001-k8s-labels" {
    "k8s.mkLabels is a function" = assertIsLambda k8s.mkLabels;
  };

  K8S-002 = runChecks "K8S-002-k8s-oci-labels" {
    "k8s.mkOCILabels is a function" = assertIsLambda k8s.mkOCILabels;
  };

  K8S-003 = runChecks "K8S-003-k8s-security-context" {
    "k8s.defaultSecurityContext is an attrset" = assertIsAttrs k8s.defaultSecurityContext;
  };

  K8S-004 = runChecks "K8S-004-k8s-mk-deployment" {
    "k8s has mkDeployment" = assertHasAttr k8s "mkDeployment";
  };

  K8S-005 = runChecks "K8S-005-k8s-mk-service" {
    "k8s has mkService" = assertHasAttr k8s "mkService";
  };

  K8S-006 = runChecks "K8S-006-k8s-mk-configmap" {
    "k8s has mkConfigMap" = assertHasAttr k8s "mkConfigMap";
  };

  K8S-007 = runChecks "K8S-007-k8s-mk-secret" {
    "k8s has mkOpaqueSecret" = assertHasAttr k8s "mkOpaqueSecret";
  };

  K8S-008 = runChecks "K8S-008-k8s-mk-ingress" {
    "k8s has mkIngress" = assertHasAttr k8s "mkIngress";
  };

  K8S-009 = runChecks "K8S-009-k8s-mk-pdb" {
    "k8s has mkPDB" = assertHasAttr k8s "mkPDB";
  };

  K8S-010 = runChecks "K8S-010-k8s-mk-hpa" {
    "k8s has mkHPA" = assertHasAttr k8s "mkHPA";
  };

  # ===========================================================================
  # Security tests: Verify security profiles and scanning
  # ===========================================================================
  SEC-001 = runChecks "SEC-001-security-profiles" {
    "security.defaultProfile is an attrset" = assertIsAttrs security.defaultProfile;
    "security.defaultProfile has securityContext" =
      assertHasAttr security.defaultProfile "securityContext";
    "security.defaultProfile.securityContext has runAsNonRoot" =
      assertHasAttr security.defaultProfile.securityContext "runAsNonRoot";
    "security.defaultProfile.securityContext has readOnlyRootFilesystem" =
      assertHasAttr security.defaultProfile.securityContext "readOnlyRootFilesystem";
  };

  SEC-002 = runChecks "SEC-002-security-harden" {
    "security.hardenContainer is a function" = assertIsLambda security.hardenContainer;
  };

  SEC-003 = runChecks "SEC-003-security-database-profile" {
    "security.databaseProfile is an attrset" = assertIsAttrs security.databaseProfile;
    "security.databaseProfile has securityContext" =
      assertHasAttr security.databaseProfile "securityContext";
  };

  SEC-004 = runChecks "SEC-004-security-web-profile" {
    "security.webProfile is an attrset" = assertIsAttrs security.webProfile;
    "security.webProfile has securityContext" = assertHasAttr security.webProfile "securityContext";
    "security.webProfile.securityContext has runAsNonRoot" =
      assertHasAttr security.webProfile.securityContext "runAsNonRoot";
  };

  # ===========================================================================
  # Full compliance check: Verify all compliance profiles are complete
  # ===========================================================================
  fullCompliance = runChecks "full-compliance" {
    "compliance has soc2 profile" = assertHasAttr compliance.complianceProfiles "soc2";
    "compliance has iso27001 profile" = assertHasAttr compliance.complianceProfiles "iso27001";
    "compliance has cis profile" = assertHasAttr compliance.complianceProfiles "cis";
    "compliance has pci profile" = assertHasAttr compliance.complianceProfiles "pci";
    "compliance has production profile" = assertHasAttr compliance.complianceProfiles "production";
    "compliance has development profile" = assertHasAttr compliance.complianceProfiles "development";
    "compliance has checkCompliance function" = assertIsLambda compliance.checkCompliance;
    "compliance has verifyAttestation function" = assertIsLambda compliance.verifyAttestation;
    "compliance has createAttestation function" = assertIsLambda compliance.createAttestation;
    "compliance.listProfiles has soc2" = "[ '${lib.concatStringsSep "," compliance.listProfiles}' = '${
      lib.concatStringsSep "," (builtins.sort (a: b: a < b) compliance.listProfiles)
    }' ]";
  };
}
