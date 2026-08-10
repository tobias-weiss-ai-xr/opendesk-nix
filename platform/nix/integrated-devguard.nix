# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
# OpenDesk-Nix DevGuard Integration - Unified security, compliance, and registry management

{ lib, pkgs, ... }:

let
  # =============================================================================
  # IMPORT ALL DEVGUARD LIBRARIES
  # =============================================================================
  
  # Import sub-libraries with DevGuard patterns
  security-nix = import ./security-scanning.nix { inherit pkgs lib; };
  registry-nix = import ./registry.nix { inherit pkgs lib; };
  compliance-nix = import ./compliance.nix { inherit pkgs lib; };
  cosign-nix = import ./cosign.nix { inherit pkgs lib; };

  # Re-export all types for convenience
  inherit (security-nix) 
    ScannerType CVEType SBOMFormatType SeverityType PolicyType 
    VulnerabilityType PackageType ImageType ScanResultType 
    AggregateResultType ScannerConfig Type; 

  inherit (registry-nix) 
    registryType registries registryTypeNames 
    formatImageName formatImageReference parseImageReference;

  inherit (compliance-nix) 
    complianceProfiles attestationTypes 
    getProfile getAttestationType listProfiles listAttestationTypes;

  # =============================================================================
  # DEVGUARD PATTERN: UNIFIED CONFIGURATION
  # =============================================================================

  # Default DevGuard configuration
  defaultConfig = rec {
    # Scanner configuration
    scanners = {
      grype = {
        enabled = true;
        priority = 1;
        config = {
          db.autoUpdate = true;
          onlyFixed = false;
          failOnSeverity = "high";
        };
      };
      trivy = {
        enabled = true;
        priority = 1;
        config = {
          cacheDir = "${lib.xdg.cacheHome}/trivy";
          severity = "CRITICAL,HIGH";
          exitCode = 1;
        };
      };
      snyk = {
        enabled = false;
        priority = 2;
        config = {
          tokenEnv = "SNYK_TOKEN";
        };
      };
      semgrep = {
        enabled = true;
        priority = 2;
        config = {
          configPath = "./config/semgrep";
        };
      };
    };

    # Registry configuration
    registry = {
      enabled = true;
      multiRegistry = true;
      targets = [ "gitlab" "ghcr" "zot" ];
      
      # Default registries
      defaultPush = "gitlab";
      defaultPull = "gitlab";
      
      # Authentication
      authEnvVars = [
        "GITHUB_TOKEN"
        "OPENCODE_TOKEN"
        "ZOT_TOKEN"
      ];
    };

    # Signing configuration
    signing = {
      enabled = true;
      mode = "keyless";  # or "key-based"
      
      keyless = {
        fulcioUrl = "https://fulcio.sigstore.dev";
        rekorUrl = "https://rekor.sigstore.dev";
      };
      
      keyBased = {
        enabled = false;
        privateKeyPath = "/path/to/cosign/private.key";
        publicKeyPath = "/path/to/cosign/public.key";
        passwordEnv = "COSIGN_PASSWORD";
      };
      
      # What to sign
      signImages = true;
      signAttestations = true;
    };

    # Compliance configuration
    compliance = {
      enabled = true;
      enforce = true;
      
      defaultProfile = "production";
      profiles = [
        "production"
        "soc2"
        "iso27001"
      ];
      
      gates = [
        { name = "pre-deploy"; enable = true; action = "block"; }
        { name = "pre-merge"; enable = true; action = "warn"; }
        { name = "periodic"; enable = true; action = "log"; }
      ];
    };

    # Attestation configuration
    attestation = {
      enabled = true;
      storeInRegistry = true;
      signAttestations = true;
      verifyAttestations = true;
      
      requiredTypes = [
        "sbom"
        "vulnerability-scan"
        "build"
        "policy"
      ];
      
      optionalTypes = [
        "kubernetes"
      ];
    };

    # SBOM configuration
    sbom = {
      enabled = true;
      generate = true;
      formats = [ "spdx" "cyclonedx" ];
      defaultFormat = "spdx";
      
      include = [
        "os"
        "packages"
        "dependencies"
        "licenses"
      ];
    };

    # Policy configuration
    policy = {
      enabled = true;
      enforce = true;
      
      default = "production";
      environments = {
        production = {
          blockOn = [ "critical" "high" ];
          warnOn = [ "medium" ];
          thresholds = {
            critical = 0;
            high = 0;
            medium = 5;
            low = 20;
          };
        };
        staging = {
          blockOn = [ "critical" ];
          warnOn = [ "high" "medium" ];
          thresholds = {
            critical = 0;
            high = 3;
            medium = 10;
            low = 20;
          };
        };
        development = {
          blockOn = [ ];
          warnOn = [ "critical" "high" ];
          thresholds = {
            critical = 5;
            high = 10;
            medium = 20;
            low = 100;
          };
        };
      };
    };

    # Reporting configuration
    reporting = {
      enabled = true;
      formats = [ "json" "markdown" "sarif" "html" ];
      
      outputs = {
        json = true;
        markdown = true;
        sarif = true;
        html = false;
      };
      
      directories = {
        json = "./reports/json";
        markdown = "./reports/markdown";
        sarif = "./reports/sarif";
        html = "./reports/html";
      };
    };
  };

  # =============================================================================
  # DEVGUARD PATTERN: UNIFIED PIPELINE FUNCTIONS
  # =============================================================================

  # Complete security pipeline for an image
  securePipeline = { 
    image,
    tag ? "latest", 
    config ? defaultConfig,
    registryConfig ? registry-nix.registries.gitlab,
    profileName ? "production",
    signingMode ? "keyless"
  }:
    let
      # Step 1: Generate SBOM
      sbom = security-nix.syftScan { 
        image = image;
        outputDir = config.reporting.directories.json;
      };
      
      # Step 2: Run vulnerability scans
      scans = {
        grype = security-nix.grypeScan { image = image; };
        trivy = security-nix.trivyScan { image = image; };
        semgrep = if config.scanners.semgrep.enabled then 
          security-nix.semgrepScan { image = image; } 
        else null;
      };
      
      # Step 3: Aggregate results
      aggregate = security-nix.aggregateResults {
        results = [ scans.grype scans.trivy ] ++ (if scans.semgrep != null then [ scans.semgrep ] else [ ]);
        image = image;
      };
      
      # Step 4: Check policy
      policy = security-nix.checkPolicy {
        results = aggregate;
        policyType = "production";
      };
      
      # Step 5: Check compliance
      compliance = compliance-nix.checkCompliance {
        image = image;
        scanResults = aggregate;
        sbom = sbom;
        policy = config.policy.environments.${profileName};
        profileName = profileName;
      };
      
      # Step 6: Sign image
      signedImage = if config.signing.enabled then
        registry-nix.signImage {
          image = image;
          registryConfig = registryConfig;
          signingMode = signingMode;
          annotations = {
            builder = "opendesk-nix";
            gitCommit = "${lib.belleza.getGitRev}" or "unknown";
            gitRepo = "${lib.belleza.getGitRepo}" or "unknown";
          };
        }
      else null;
      
      # Step 7: Create attestations
      attestations = if config.attestation.enabled then
        compliance-nix.attestImage {
          image = image;
          registryConfig = registryConfig;
          sbomData = sbom;
          scanResults = aggregate;
          buildConfig = config;
          policyResults = policy;
          profileName = profileName;
          attestationTypesToCreate = config.attestation.requiredTypes;
          signingMode = signingMode;
        }
      else [ ];
      
      # Step 8: Push to registries
      pushedImages = if builtins.hasAttr "targets" config.registry && config.registry.multiRegistry then
        registry-nix.pushToAll {
          image = image;
          tag = tag;
          registriesToUse = config.registry.targets;
          signingMode = signingMode;
        }
      else null;
      
      # Step 9: Verify attestations
      verifiedAttestations = if config.attestation.enabled && config.attestation.verifyAttestations then
        compliance-nix.verifyAllAttestations {
          image = image;
          registryConfig = registryConfig;
          profileName = profileName;
          failOnError = config.compliance.enforce;
        }
      else null;
      
    in rec {
      inherit image tag config registryConfig profileName signingMode;
      
      # Pipeline results
      sbom = sbom;
      scans = scans;
      aggregate = aggregate;
      policy = policy;
      compliance = compliance;
      signedImage = signedImage;
      attestations = attestations;
      pushedImages = pushedImages;
      verifiedAttestations = verifiedAttestations;
      
      # Status
      success = policy.block == false && compliance.overallCompliant;
      warnings = policy.warnCount + (if compliance.anyFailed then 1 else 0) + compliance.counts.nonCompliant;
      errors = policy.blockCount + (if compliance.anyFailed && config.compliance.enforce then 1 else 0);
      
      # Reports
      report = security-nix.generateReports {
        results = aggregate;
        formats = if config.reporting.enabled then config.reporting.formats else [ "json" ];
        outputDirs = if config.reporting.enabled then config.reporting.directories else { };
      };
      
      complianceReport = compliance-nix.generateReport {
        complianceResult = compliance;
        outputPath = "${config.reporting.directories.json or "./reports/json"}/compliance-${image}-${tag}.json";
        markdown = true;
      };
    };

  # =============================================================================
  # DEVGUARD PATTERN: BATCH PROCESSING
  # =============================================================================

  # Process multiple images through the pipeline
  batchSecurePipeline = { 
    images,
    tag ? "latest",
    config ? defaultConfig,
    registryConfig ? registry-nix.registries.gitlab,
    profileName ? "production",
    signingMode ? "keyless"
  }:
    let
      results = map (image: 
        securePipeline {
          image = image;
          tag = tag;
          config = config;
          registryConfig = registryConfig;
          profileName = profileName;
          signingMode = signingMode;
        }
      ) (builtins.isList images ? images : [ images ]);
      
      # Aggregate statistics
      stats = {
        total = builtins.length results;
        successful = builtins.length (builtins.filter (r: r.success) results);
        failed = builtins.length (builtins.filter (r: !r.success) results);
        totalWarnings = builtins.sum (map (r: r.warnings) results);
        totalErrors = builtins.sum (map (r: r.errors) results);
      };
      
      # Generate summary report
      summaryReport = compliance-nix.generateSummaryReport {
        allResults = {
          imageResults = results;
          allCompliant = stats.successful == stats.total;
          totalImages = stats.total;
          compliantImages = stats.successful;
        };
        outputPath = "${config.reporting.directories.json or "./reports/json"}/summary-report.json";
        markdown = true;
      };
      
    in rec {
      inherit images tag config registryConfig profileName signingMode;
      
      results = results;
      stats = stats;
      summaryReport = summaryReport;
      
      allSuccessful = stats.successful == stats.total;
      anyFailed = stats.failed > 0;
    };

  # =============================================================================
  # DEVGUARD PATTERN: DEPLOYMENT GUARD
  # =============================================================================

  # Deployment guard that enforces security policies
  deploymentGuard = { 
    image,
    tag ? "latest",
    targetEnvironment ? "production",
    config ? defaultConfig,
    registryConfig ? registry-nix.registries.gitlab,
    signingMode ? "keyless"
  }:
    let
      pipeline = securePipeline {
        image = image;
        tag = tag;
        config = config;
        registryConfig = registryConfig;
        profileName = targetEnvironment;
        signingMode = signingMode;
      };
      
      # Determine gate action
      gate = compliance-nix.createComplianceGate {
        profileName = targetEnvironment;
        action = if targetEnvironment == "production" then "block" else "warn";
        manualOverride = true;
        overrideDuration = if targetEnvironment == "production" then "1h" else "24h";
      };
      
      gateResult = gate.check {
        image = image;
        scanResults = pipeline.aggregate;
        sbom = pipeline.sbom;
        metadata = { targetEnvironment = targetEnvironment; };
        registry = registryConfig;
        policy = config.policy.environments.${targetEnvironment};
      };
      
    in rec {
      inherit image tag targetEnvironment config registryConfig signingMode;
      
      pipeline = pipeline;
      gate = gate;
      gateResult = gateResult;
      
      # Decision
      allowDeployment = gateResult.passed;
      blockDeployment = gateResult.blocked;
      warnOnly = gateResult.warned;
      
      # Reason for decision
      reason = if gateResult.passed then
        "All security checks passed"
      else if gateResult.blocked then
        "Critical security violations detected"
      else
        "Security warnings detected - manual review required";
      
      # Detailed blocking reasons
      blockingIssues = if !gateResult.passed && pipeline.compliance != null then
        map (r: {
          id = r.requirementId;
          description = r.requirementDescription;
          severity = r.severity;
          remediation = r.remediation;
        }) (builtins.filter (r: !r.compliant && r.severity == "critical") pipeline.compliance.requirementResults)
      else [ ];
      
      # Warnings
      warnings = if gateResult.warned && pipeline.compliance != null then
        map (r: {
          id = r.requirementId;
          description = r.requirementDescription;
          severity = r.severity;
          remediation = r.remediation;
        }) (builtins.filter (r: !r.compliant && r.severity != "critical") pipeline.compliance.requirementResults)
      else [ ];
      
      # Generate audit log
      auditLog = pkgs.writeText "deployment-audit-${image}-${tag}.log" (builtins.toJSON {
        timestamp = "${pkgs.lib.strftime "%Y-%m-%dT%H:%M:%SZ"}";
        image = image;
        tag = tag;
        targetEnvironment = targetEnvironment;
        allowDeployment = allowDeployment;
        blockDeployment = blockDeployment;
        blockingIssues = blockingIssues;
        warnings = warnings;
        complianceReport = pipeline.compliance;
        scanResults = pipeline.aggregate;
      });
    };

  # =============================================================================
  # DEVGUARD PATTERN: CI/CD INTEGRATION
  # =============================================================================

  # Create GitHub Actions workflow for DevGuard pipeline
  githubWorkflow = { 
    name ? "devguard-security",
    triggers ? { push = [ "main" ]; pull_request = [ "main" ]; },
    config ? defaultConfig,
    profileName ? "production"
  }:
    let
      workflowFile = pkgs.writeText "${name}.yml" ''
name: ${name}

on:
${if builtins.hasAttr "push" triggers then ''
  push:
    branches: ${builtins.concatStringsSep ", " (builtins.map (b: "[ "${b}" ]") triggers.push)}
'' else ''''}
${if builtins.hasAttr "pull_request" triggers then ''
  pull_request:
    branches: ${builtins.concatStringsSep ", " (builtins.map (b: "[ "${b}" ]") triggers.pull_request)}
'' else ''''}

jobs:
  security-pipeline:
    name: Security Pipeline
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
      id-token: write
    
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      
      - name: Set up Nix
        uses: DeterminateSystems/nix-installer-action@v10
      
      - name: Set up magic-nix-cache
        uses: DeterminateSystems/magic-nix-cache-action@v2
      
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3
      
      - name: Log in to GitHub Container Registry
        if: github.event_name != 'pull_request'
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ github.token }}
      
      - name: Log in to GitLab Container Registry
        if: github.event_name != 'pull_request' && env.OPENCODE_TOKEN != ''
        uses: docker/login-action@v3
        with:
          registry: registry.gitlab.com
          username: token
          password: ${{ secrets.OPENCODE_TOKEN }}
      
      - name: Run DevGuard Security Pipeline
        run: |
          nix develop -c opendesk-nix#full --command bash -c "
            ${if config.sbom.enabled then ''
            echo 'Generating SBOM...'
            security-nix.syftScan \${{ steps.meta.outputs.tags }}
            '' else ''''}
            
            ${if config.scanners.grype.enabled || config.scanners.trivy.enabled then ''
            echo 'Running vulnerability scans...'
            ${if config.scanners.grype.enabled then ''security-nix.grypeScan \${{ steps.meta.outputs.tags }}'' else ''''}
            ${if config.scanners.trivy.enabled then ''security-nix.trivyScan \${{ steps.meta.outputs.tags }}'' else ''''}
            '' else ''''}
            
            ${if config.compliance.enabled then ''
            echo 'Checking compliance...'
            nix run .#compliance-gates.ci-pipeline
            '' else ''''}
            
            ${if config.signing.enabled then ''
            echo 'Signing images...'
            cosign sign \${{ steps.meta.outputs.tags }} --yes
            '' else ''''}
          "
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          OPENCODE_TOKEN: ${{ secrets.OPENCODE_TOKEN }}
          COSIGN_EXPERIMENTAL: "1"
      
      - name: Push to registries
        if: github.event_name != 'pull_request'
        run: |
          nix run .#registry-nix.pushToAll \${{ steps.meta.outputs.tags }}
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          OPENCODE_TOKEN: ${{ secrets.OPENCODE_TOKEN }}
          ZOT_TOKEN: ${{ secrets.ZOT_TOKEN }}
      
      - name: Upload reports
        uses: actions/upload-artifact@v4
        with:
          name: security-reports
          path: |
            reports/
            *.json
            *.md
'';
      
    in workflowFile;

  # Create GitLab CI configuration for DevGuard pipeline
  gitlabCIConfig = { 
    config ? defaultConfig
  }:
    let
      ciFile = pkgs.writeText ".gitlab-ci-devguard.yml" ''
include:
  - template: Security/SAST.gitlab-ci.yml
  - template: Security/Secret-Detection.gitlab-ci.yml
  - template: Security/Dependency-Scanning.gitlab-ci.yml

stages:
  - build
  - security
  - compliance
  - deploy

variables:
  COSIGN_EXPERIMENTAL: "1"
  DOCKER_DRIVER: overlay2
  DOCKER_TLS_CERTDIR: ""

# DevGuard Security Pipeline
.devguard-template: &devguard-template
  image: nixos/nix:latest
  before_script:
    - nix-env -iA cachix -f https://cachix.org/api/v1/install
    - cachix use opendesk
    - echo "${CI_JOB_TOKEN}" | docker login -u "gitlab-ci-token" --password-stdin registry.gitlab.com
  cache:
    key: "${CI_COMMIT_REF_SLUG}"
    paths:
      - .cachix

build-images:
  stage: build
  <<: *devguard-template
  script:
    - nix build .#mariadb .#postgresql .#redis
  artifacts:
    paths:
      - result/
  tags:
    - nix
    - build

security-scan:
  stage: security
  <<: *devguard-template
  script:
    - nix develop -c opendesk-nix#security --command bash -c "
        echo 'Running Grype scan...'
        grype dir:/build result/
        echo 'Running Trivy scan...'
        trivy fs result/
      "
  needs: [build-images]
  tags:
    - security
    - scan

compliance-check:
  stage: compliance
  <<: *devguard-template
  script:
    - nix run .#compliance-gates.pre-deploy
    ${if config.compliance.enforce then ''
    - if [ $CI_COMMIT_DEFAULT_BRANCH == \$CI_COMMIT_REF_NAME ]; then nix run .#compliance-gates.release; fi
    '' else ''''}
  needs: [security-scan]
  tags:
    - compliance

sign-and-push:
  stage: deploy
  <<: *devguard-template
  script:
    - echo "Signing and pushing images..."
    - nix run .#registry-nix.pushToAll result/
    - echo "Creating attestations..."
    - nix run .#compliance-nix.attestImage result/
  only:
    - main
    - tags
  needs: [compliance-check]
  tags:
    - deploy
    - signing

# Serve reports
pages:
  stage: deploy
  image: alpine:latest
  script:
    - mkdir -p public
    - cp -r reports/* public/ || true
    - cp -r result/* public/ || true
  artifacts:
    paths:
      - public
  only:
    - main
'';
      
    in ciFile;

  # =============================================================================
  # DEVGUARD PATTERN: MONITORING AND ALERTING
  # =============================================================================

  # Health check for DevGuard components
  healthCheck = { 
    checkRegistries ? true,
    checkScanners ? true,
    checkSigning ? true
  }:
    pkgs.runCommand "health-check-${builtins.hashString "sha256" (toString checkRegistries)}" {
      nativeBuildInputs = with pkgs; [ curl bash ];
    }''
      set -e
      
      echo "DevGuard Health Check"
      echo "====================="
      echo ""
      
      extract_value() {
        echo "$1" | grep -oP '(?<="$2":\s*)"[^"]*"|[^,}]*' | head -1
      }
      
      ${if checkRegistries then ''
      echo "[1/3] Checking registries..."
      REGISTRIES=("ghcr.io" "registry.gitlab.com" "${ZOT_REGISTRY_FALLBACK:-registry.example.com:5000}")  # Replace with your registry
      for reg in "${REGISTRIES[@]}"; do
        if curl -k -I "$reg" >/dev/null 2>&1; then
          echo "  ✅ $reg is accessible"
        else
          echo "  ❌ $reg is NOT accessible"
        fi
      done
      '' else ''''}
      
      ${if checkScanners then ''
      echo ""
      echo "[2/3] Checking scanners..."
      SCANNERS=("grype" "trivy" "syft")
      for scanner in "${SCANNERS[@]}"; do
        if command -v $scanner >/dev/null 2>&1; then
          VERSION=$($scanner version 2>/dev/null | head -1)
          echo "  ✅ $scanner is installed ($VERSION)"
        else
          echo "  ❌ $scanner is NOT installed"
        fi
      done
      '' else ''''}
      
      ${if checkSigning then ''
      echo ""
      echo "[3/3] Checking signing..."
      if command -v cosign >/dev/null 2>&1; then
        VERSION=$(cosign version 2>/dev/null)
        echo "  ✅ cosign is installed ($VERSION)"
        
        # Check for cosign keys
        if [ -f "cosign.key" ]; then
          echo "  ✅ cosign.key found"
        else
          echo "  ⚠️  cosign.key NOT found (keyless signing still works)"
        fi
      else
        echo "  ❌ cosign is NOT installed"
      fi
      '' else ''''}
      
      echo ""
      echo "Health check complete"
      touch $out
    '';

  # =============================================================================
  # DEVGUARD PATTERN: AUDIT LOGGING
  # =============================================================================

  # Create audit log entry
  auditLog = { 
    action,
    image ? "",
    tag ? "",
    user ? (builtins.getEnv "USER" or "unknown"),
    status ? "success",
    details ? { },
    timestamp ? "${pkgs.lib.strftime "%Y-%m-%dT%H:%M:%SZ"}"
  }:
    let
      logEntry = {
        timestamp = timestamp;
        action = action;
        image = image;
        tag = tag;
        user = user;
        status = status;
        details = details;
        environment = builtins.getEnv "CI_ENVIRONMENT_NAME" or "local";
        commit = builtins.getEnv "GIT_COMMIT" or "unknown";
        jobId = builtins.getEnv "CI_JOB_ID" or "local-${builtins.hashString "sha256" timestamp}";
      };
      
    in pkgs.writeText "audit-${action}-${image}-${tag}-${timestamp}.json" (builtins.toJSON logEntry);

  # Query audit logs
  queryAuditLogs = { 
    action ? null,
    image ? null,
    user ? null,
    status ? null,
    since ? null,
    until ? null
  }:
    # This would need a proper audit log storage backend
    # For now, return a query command
    pkgs.runCommand "query-audit-${builtins.hashString "sha256" (toString action)}" {
      nativeBuildInputs = with pkgs; [ jq ];
    }''
      echo "Audit Log Query Parameters:"
      echo "  Action: ${action or "all"}"
      echo "  Image: ${image or "all"}"
      echo "  User: ${user or "all"}"
      echo "  Status: ${status or "all"}"
      echo "  Since: ${since or "foreach"}"
      echo "  Until: ${until or "foreach"}"
      
      echo ""
      echo "Query command:"
      echo "  find . -name 'audit-*.json' -type f | xargs jq 'select(${toJSON ({ 
        action = action;
        image = image;
        user = user;
        status = status;
      })} | .[])'"
      
      touch $out
    '';

  # =============================================================================
  # EXPORTED VALUES
  # =============================================================================

in {
  # Configuration
  inherit defaultConfig;
  
  # Unified pipeline functions
  inherit securePipeline batchSecurePipeline;
  
  # Deployment guard
  inherit deploymentGuard;
  
  # CI/CD integration
  inherit githubWorkflow gitlabCIConfig;
  
  # Monitoring and alerting
  inherit healthCheck;
  
  # Audit logging
  inherit auditLog queryAuditLogs;
  
  # Re-export all sub-libraries for convenience
  inherit (security-nix) 
    ScannerType CVEType SBOMFormatType SeverityType PolicyType 
    VulnerabilityType PackageType ImageType ScanResultType 
    AggregateResultType ScannerConfig Type
    grypeScan trivyScan syftScan semgrepScan gosecScan aggregateResults
    checkPolicy generateReports;
  
  inherit (registry-nix)
    registryType registries registryTypeNames
    formatImageName formatImageReference parseImageReference
    pushToRegistry pullFromRegistry pushToAll pushToAllSequential
    signImage verifySignature verifyAndEnforceSignature
    containerdRegistryConfig dockerAuthConfig dockerDaemonConfig;
  
  inherit (compliance-nix)
    complianceProfiles attestationTypes
    getProfile getAttestationType listProfiles listAttestationTypes
    createAttestation attestImage verifyAttestation verifyAllAttestations
    checkRequirement checkCompliance checkAllCompliance
    createComplianceGate gates generateReport generateSummaryReport;
  
  inherit (cosign-nix) cosignSign cosignVerify cosignAttest;
  
  # Combined configuration
  config = rec {
    devguard = defaultConfig // {
      version = "1.0.0";
      integrated = true;
      libraries = [
        "security-scanning.nix"
        "registry.nix"
        "compliance.nix"
        "cosign.nix"
        "integrated-devguard.nix"
      ];
    };
  };
  
  # Helper values
  profiles = complianceProfiles;
  attestationTypes = attestationTypes;
  registries = registries;
  
  # Version information
  version = "1.0.0";
  description = "OpenDesk-Nix DevGuard Integration";
}
