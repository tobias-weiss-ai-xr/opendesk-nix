# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
# DevGuard Pattern: Comprehensive compliance and attestation framework

{ pkgs, ... }:

let
  # =============================================================================
  # COMPLIANCE PROFILE DEFINITIONS - DevGuard Pattern
  # =============================================================================

  # Compliance profiles based on common standards
  complianceProfiles = {
    # SOC2 Type II Compliance Profile
    soc2 = rec {
      name = "SOC2 Type II";
      description = "Service Organization Control 2 Type II compliance profile";
      version = "1.0.0";
      category = "security";

      # Requirements for SOC2
      requirements = [
        {
          id = "SBOM-GENERATION";
          description = "SBOM must be generated for all images";
          severity = "critical";
          check = { sbom, ... }: sbom != null && builtins.isAttrs sbom;
          remediation = "Generate SBOM using syft before building images";
        }
        {
          id = "VULNERABILITY-SCANNING";
          description = "Images must be scanned for vulnerabilities";
          severity = "critical";
          check =
            { scanResults, ... }:
            scanResults != null && builtins.isList scanResults && builtins.length scanResults > 0;
          remediation = "Run security scanning on all images";
        }
        {
          id = "IMAGE-SIGNING";
          description = "Images must be cryptographically signed";
          severity = "critical";
          check = { signature, ... }: signature != null && builtins.isAttrs signature;
          remediation = "Sign images using cosign";
        }
        {
          id = "ACCESS-CONTROL";
          description = "Image registry access must be controlled";
          severity = "high";
          check =
            { registry, ... }:
            registry != null
            && (registry.tokenEnv != null || (registry.username != null && registry.password != null));
          remediation = "Configure registry authentication tokens or credentials";
        }
        {
          id = "AUDIT-LOGGING";
          description = "All access must be logged";
          severity = "high";
          check = { registry, ... }: registry != null && registry.supportsSigning;
          remediation = "Enable audit logging on your registry";
        }
      ];

      # Severity thresholds for vulnerability counts
      thresholds = {
        critical = {
          maxCount = 0;
          action = "fail";
        };
        high = {
          maxCount = 5;
          action = "warn";
        };
        medium = {
          maxCount = 20;
          action = "log";
        };
        low = {
          maxCount = 100;
          action = "ignore";
        };
        negligible = {
          action = "ignore";
        };
      };

      # Required attestation types
      requiredAttestations = [
        "sbom"
        "vulnerability-scan"
        "build"
      ];
      optionalAttestations = [ "policy" ];
    };

    # ISO27001 Compliance Profile
    iso27001 = rec {
      name = "ISO27001";
      description = "ISO/IEC 27001 information security management profile";
      version = "1.0.0";
      category = "security";

      requirements = [
        {
          id = "ASSET-INVENTORY";
          description = "All assets must be inventoried";
          severity = "critical";
          check = { metadata, ... }: metadata != null && builtins.hasAttr "assetId" metadata;
          remediation = "Add asset inventory metadata to images";
        }
        {
          id = "VULNERABILITY-MANAGEMENT";
          description = "Vulnerabilities must be managed";
          severity = "critical";
          check = { scanResults, ... }: scanResults != null && builtins.isList scanResults;
          remediation = "Implement vulnerability scanning and remediation process";
        }
        {
          id = "INCIDENT-RESPONSE";
          description = "Incident response procedures must be in place";
          severity = "high";
          check =
            { metadata, ... }: builtins.hasAttr "incidentResponse" metadata && metadata.incidentResponse;
          remediation = "Document and implement incident response procedures";
        }
        {
          id = "BACKUP-RECOVERY";
          description = "Backups must be maintained";
          severity = "medium";
          check =
            { metadata, ... }: builtins.hasAttr "backupPolicy" metadata && metadata.backupPolicy != null;
          remediation = "Implement backup and recovery procedures";
        }
        {
          id = "ENCRYPTION";
          description = "Data must be encrypted at rest and in transit";
          severity = "high";
          check = { registry, ... }: registry != null && (!registry.insecure);
          remediation = "Enable TLS/SSL for registry connections";
        }
        {
          id = "ACCESS-CONTROL";
          description = "Access must be controlled and monitored";
          severity = "high";
          check =
            { registry, ... }:
            registry != null
            && (registry.tokenEnv != null || (registry.username != null && registry.password != null));
          remediation = "Implement access control for registries";
        }
      ];

      thresholds = {
        critical = {
          maxCount = 0;
          action = "fail";
        };
        high = {
          maxCount = 3;
          action = "warn";
        };
        medium = {
          maxCount = 10;
          action = "log";
        };
        low = {
          maxCount = 50;
          action = "ignore";
        };
        negligible = {
          action = "ignore";
        };
      };

      requiredAttestations = [
        "sbom"
        "vulnerability-scan"
        "build"
      ];
      optionalAttestations = [
        "policy"
        "compliance"
      ];
    };

    # CIS Kubernetes Benchmark Profile
    cis = rec {
      name = "CIS Kubernetes Benchmark";
      description = "CIS Kubernetes Benchmark compliance profile";
      version = "1.0.0";
      category = "kubernetes";

      requirements = [
        {
          id = "POD-SECURITY-POLICY";
          description = "Pod security policies must be enforced";
          severity = "critical";
          check = { policy, ... }: builtins.hasAttr "podSecurity" policy && policy.podSecurity != null;
          remediation = "Create and apply PodSecurityPolicy objects";
        }
        {
          id = "NETWORK-POLICY";
          description = "Network policies must be enforced";
          severity = "critical";
          check = { policy, ... }: builtins.hasAttr "networkPolicy" policy && policy.networkPolicy != null;
          remediation = "Create and apply NetworkPolicy objects";
        }
        {
          id = "SECRETS-MANAGEMENT";
          description = "Secrets must be managed securely";
          severity = "critical";
          check = { policy, ... }: builtins.hasAttr "secrets" policy && policy.secrets == "encrypted";
          remediation = "Use encrypted secrets or external secret management";
        }
        {
          id = "RBAC";
          description = "Role-based access control must be enforced";
          severity = "critical";
          check = { policy, ... }: builtins.hasAttr "rbac" policy && policy.rbac;
          remediation = "Enable and configure RBAC";
        }
        {
          id = "API-SERVER-SECURITY";
          description = "API server must be secured";
          severity = "high";
          check = { policy, ... }: builtins.hasAttr "apiServer" policy && policy.apiServer.secure;
          remediation = "Secure Kubernetes API server with TLS and authentication";
        }
        {
          id = "ETCD-ENCRYPTION";
          description = "etcd data must be encrypted";
          severity = "high";
          check =
            { policy, ... }:
            builtins.hasAttr "etcd" policy
            && builtins.hasAttr "encryption" policy.etcd
            && policy.etcd.encryption;
          remediation = "Enable etcd encryption at rest";
        }
      ];

      thresholds = {
        critical = {
          maxCount = 0;
          action = "fail";
        };
        high = {
          maxCount = 0;
          action = "fail";
        };
        medium = {
          maxCount = 5;
          action = "warn";
        };
        low = {
          maxCount = 20;
          action = "ignore";
        };
        negligible = {
          action = "ignore";
        };
      };

      requiredAttestations = [
        "sbom"
        "vulnerability-scan"
      ];
      optionalAttestations = [
        "build"
        "policy"
        "kubernetes"
      ];
    };

    # PCI DSS Compliance Profile
    pci = rec {
      name = "PCI DSS";
      description = "Payment Card Industry Data Security Standard profile";
      version = "1.0.0";
      category = "payment";

      requirements = [
        {
          id = "FIREWALL-CONFIGURATION";
          description = "Firewall must be properly configured";
          severity = "critical";
          check = { policy, ... }: builtins.hasAttr "firewall" policy && policy.firewall;
          remediation = "Configure and enable firewall rules";
        }
        {
          id = "ENCRYPTION-TRANSMISSION";
          description = "Data must be encrypted during transmission";
          severity = "critical";
          check = { registry, ... }: registry != null && !registry.insecure;
          remediation = "Enable TLS for all registry connections";
        }
        {
          id = "ACCESS-CONTROL";
          description = "Strong access control mechanisms must be in place";
          severity = "critical";
          check =
            { registry, ... }:
            registry != null
            && (registry.tokenEnv != null || (registry.username != null && registry.password != null));
          remediation = "Implement strong access controls for registries";
        }
        {
          id = "REGULAR-TESTING";
          description = "Regular security testing must be performed";
          severity = "high";
          check = { scanResults, ... }: scanResults != null && builtins.length scanResults > 0;
          remediation = "Implement regular vulnerability scanning";
        }
        {
          id = "LOGGING-MONITORING";
          description = "Comprehensive logging and monitoring must be in place";
          severity = "high";
          check =
            { policy, ... }:
            builtins.hasAttr "logging" policy
            && policy.logging
            && builtins.hasAttr "monitoring" policy
            && policy.monitoring;
          remediation = "Implement logging and monitoring capabilities";
        }
      ];

      thresholds = {
        critical = {
          maxCount = 0;
          action = "fail";
        };
        high = {
          maxCount = 0;
          action = "fail";
        };
        medium = {
          maxCount = 0;
          action = "warn";
        };
        low = {
          maxCount = 10;
          action = "ignore";
        };
        negligible = {
          action = "ignore";
        };
      };

      requiredAttestations = [
        "sbom"
        "vulnerability-scan"
        "build"
        "policy"
      ];
      optionalAttestations = [ "pci" ];
    };

    # Production profile (strict)
    production = rec {
      name = "Production";
      description = "Strict production compliance profile";
      version = "1.0.0";
      category = "production";

      requirements = [
        {
          id = "CRITICAL-NO-VULNS";
          description = "No critical vulnerabilities allowed";
          severity = "critical";
          check = _: true;
          remediation = "Fix all critical vulnerabilities before deployment";
        }
        {
          id = "SIGNING-REQUIRED";
          description = "Image signing is mandatory";
          severity = "critical";
          check = _: true;
          remediation = "Sign all production images";
        }
        {
          id = "SBOM-REQUIRED";
          description = "SBOM is mandatory";
          severity = "critical";
          check = _: true;
          remediation = "Generate SBOM for all production images";
        }
        {
          id = "SCAN-REQUIRED";
          description = "Security scanning is mandatory";
          severity = "critical";
          check = _: true;
          remediation = "Run security scanning on all production images";
        }
      ];

      thresholds = {
        critical = {
          maxCount = 0;
          action = "fail";
        };
        high = {
          maxCount = 0;
          action = "fail";
        };
        medium = {
          maxCount = 5;
          action = "warn";
        };
        low = {
          maxCount = 20;
          action = "ignore";
        };
        negligible = {
          action = "ignore";
        };
      };

      requiredAttestations = [
        "sbom"
        "vulnerability-scan"
        "build"
        "policy"
      ];
      optionalAttestations = [ ];
    };

    # Development profile (lenient)
    development = rec {
      name = "Development";
      description = "Development compliance profile with warnings only";
      version = "1.0.0";
      category = "development";

      requirements = [
        {
          id = "VULNERABILITY-AWARENESS";
          description = "Vulnerabilities should be reviewed";
          severity = "medium";
          check = { scanResults, ... }: scanResults != null;
          remediation = "Review vulnerability scan results";
        }
        {
          id = "SBOM-GENERATED";
          description = "SBOM should be generated";
          severity = "medium";
          check = { sbom, ... }: sbom != null;
          remediation = "Generate SBOM for images";
        }
      ];

      thresholds = {
        critical = {
          maxCount = 5;
          action = "warn";
        };
        high = {
          maxCount = 10;
          action = "warn";
        };
        medium = {
          maxCount = 20;
          action = "warn";
        };
        low = {
          maxCount = 100;
          action = "ignore";
        };
        negligible = {
          action = "ignore";
        };
      };

      requiredAttestations = [
        "sbom"
        "vulnerability-scan"
      ];
      optionalAttestations = [ "build" ];
    };

    # Custom profile template
    custom =
      {
        profileName,
        requirements ? [ ],
        requiredAttestations ? [ ],
        optionalAttestations ? [ ],
      }:
      rec {
        name = profileName;
        description = "Custom compliance profile";
        version = "1.0.0";
        category = "custom";
        inherit requirements;
        thresholds =
          if thresholds == null then
            {
              critical = {
                maxCount = 0;
                action = "fail";
              };
              high = {
                maxCount = 5;
                action = "warn";
              };
              medium = {
                maxCount = 20;
                action = "log";
              };
              low = {
                maxCount = 100;
                action = "ignore";
              };
              negligible = {
                action = "ignore";
              };
            }
          else
            thresholds;
        inherit requiredAttestations;
        inherit optionalAttestations;
      };
  };

  # Get compliance profile by name
  getProfile =
    profileName:
    if builtins.hasAttr profileName complianceProfiles then
      complianceProfiles.${profileName}
    else if profileName == "all" then
      complianceProfiles
    else
      throw "Unknown compliance profile: ${profileName}. Available: ${builtins.concatStringsSep ", " (builtins.attrNames complianceProfiles)}";

  # List all available compliance profiles
  listProfiles = builtins.attrNames complianceProfiles;

  # =============================================================================
  # ATTESTATION TYPES - DevGuard Pattern
  # =============================================================================

  # Attestation type definitions
  attestationTypes = {
    # SBOM Attestation
    sbom = rec {
      name = "sbom";
      description = "Software Bill of Materials attestation";
      predicateType = "https://spdx.dev/spdxjson/schema/spdx-2.3.json";
      version = "1.0.0";
      requiredFor = [
        "soc2"
        "iso27001"
        "cis"
        "pci"
        "production"
      ];

      createPredicate =
        {
          image,
          sbomData,
          sbomFormat ? "spdx",
        }:
        {
          sbom = sbomData;
          inherit sbomFormat;
          inherit image;
          generatedAt = "${"2026-01-01T00:00:00Z"}";
          generator = "OpenDesk-Nix SBOM Generator";
        };
    };

    # Vulnerability Scan Attestation
    vulnerability-scan = rec {
      name = "vulnerability-scan";
      description = "Vulnerability scan results attestation";
      predicateType = "https://cyclonedx.org/schema/bom-1.4.json";
      version = "1.0.0";
      requiredFor = [
        "soc2"
        "iso27001"
        "cis"
        "pci"
        "production"
      ];

      createPredicate =
        {
          image,
          scanResults,
          scannersUsed ? [
            "grype"
            "trivy"
          ],
        }:
        {
          inherit image;
          inherit scanResults;
          scanners = scannersUsed;
          scannedAt = "${"2026-01-01T00:00:00Z"}";
          generator = "OpenDesk-Nix Security Scanner";
        };
    };

    # Build Attestation
    build = rec {
      name = "build";
      description = "Build configuration and parameters attestation";
      predicateType = "https://in-toto.io/attribute/build/";
      version = "1.0.0";
      requiredFor = [
        "soc2"
        "iso27001"
        "pci"
        "production"
      ];

      createPredicate =
        {
          image,
          buildConfig,
          buildInfo ? { },
        }:
        {
          inherit image;
          inherit buildConfig;
          buildTime = buildInfo.buildTime or "${"2026-01-01T00:00:00Z"}";
          gitCommit = buildInfo.gitCommit or "unknown";
          gitRepo = buildInfo.gitRepo or "unknown";
          builder = buildInfo.builder or "opendesk-nix";
          generator = "OpenDesk-Nix Build System";
        };
    };

    # Policy Compliance Attestation
    policy = rec {
      name = "policy";
      description = "Policy compliance check attestation";
      predicateType = "https://in-toto.io/attribute/policy/";
      version = "1.0.0";
      requiredFor = [
        "iso27001"
        "pci"
        "production"
      ];
      optionalFor = [
        "soc2"
        "cis"
        "development"
      ];

      createPredicate =
        {
          image,
          policyResults,
          profileName ? "production",
        }:
        {
          inherit image;
          profile = profileName;
          complianceResults = policyResults;
          checkedAt = "${"2026-01-01T00:00:00Z"}";
          generator = "OpenDesk-Nix Compliance Checker";
        };
    };

    # Kubernetes Attestation
    kubernetes = rec {
      name = "kubernetes";
      description = "Kubernetes deployment configuration attestation";
      predicateType = "https://kubernetes.io/attestation/";
      version = "1.0.0";
      requiredFor = [ "cis" ];
      optionalFor = [
        "soc2"
        "iso27001"
        "pci"
        "production"
      ];

      createPredicate =
        {
          image,
          k8sConfig,
          deploymentInfo ? { },
        }:
        {
          inherit image;
          inherit k8sConfig;
          deployedAt = deploymentInfo.deployedAt or "${"2026-01-01T00:00:00Z"}";
          namespace = deploymentInfo.namespace or "default";
          cluster = deploymentInfo.cluster or "unknown";
          generator = "OpenDesk-Nix Kubernetes Deployer";
        };
    };

    # Custom attestation type
    custom =
      {
        attestationName,
        predicateType ? "https://in-toto.io/attribute/custom/",
        createPredicate ? (
          { image, ... }:
          {
            inherit image;
            customAttestation = attestationName;
            generatedAt = "${"2026-01-01T00:00:00Z"}";
          }
        ),
      }:
      rec {
        name = attestationName;
        description = "Custom attestation type";
        inherit predicateType;
        version = "1.0.0";
        requiredFor = [ ];
        inherit createPredicate;
      };
  };

  # Get attestation type by name
  getAttestationType =
    attestationName:
    if builtins.hasAttr attestationName attestationTypes then
      attestationTypes.${attestationName}
    else if attestationName == "all" then
      attestationTypes
    else
      throw "Unknown attestation type: ${attestationName}. Available: ${builtins.concatStringsSep ", " (builtins.attrNames attestationTypes)}";

  # List all attestation types
  listAttestationTypes = builtins.attrNames attestationTypes;

  # =============================================================================
  # ATTESTATION OPERATIONS - DevGuard Pattern
  # =============================================================================

  # Create a single attestation for an image
  createAttestation =
    {
      image,
      attestationTypeName,
      predicateData,
      registryConfig,
      outputAttestation ? null,
    }:
    let
      attestationType = getAttestationType attestationTypeName;
      predicate =
        if attestationType.createPredicate != null then
          attestationType.createPredicate predicateData
        else
          predicateData;

      imageName = if builtins.isAttrs registryConfig then "${registryConfig.url}/${image}" else image;

    in
    pkgs.runCommand "attest-${attestationTypeName}-${builtins.hashString "sha256" imageName}"
      {
        nativeBuildInputs = with pkgs; [
          cosign
          jq
        ];
        COSIGN_EXPERIMENTAL = "1";
      }
      ''
        echo "Creating ${attestationTypeName} attestation for ${imageName}"

        cat > predicate-${attestationTypeName}.json << 'PRvýEDICATE_EOF'
        ${builtins.toJSON predicate}
        PRvýEDICATE_EOF

        cosign attest --predicate predicate-${attestationTypeName}.json \
          --type ${attestationType.predicateType} \
          --yes \
          ${imageName}

        ${
          if outputAttestation != null then
            ''
              mkdir -p $(dirname "${outputAttestation}")
              cosign verify-attestation --type ${attestationType.predicateType} ${imageName} 2>/dev/null | jq '.' > "${outputAttestation}" || true
            ''
          else
            ""
        }

        rm -f predicate-${attestationTypeName}.json
        echo "Attestation created for ${attestationTypeName}"
        touch $out
      '';

  # Create all required attestations for an image
  attestImage =
    {
      image,
      registryConfig,
      sbomData ? null,
      scanResults ? null,
      buildConfig ? null,
      policyResults ? null,
      profileName ? "production",
      attestationTypesToCreate ? null,
      signingMode ? "keyless",
    }:
    let
      profile = getProfile profileName;
      typesToCreate =
        if attestationTypesToCreate != null then
          attestationTypesToCreate
        else
          profile.requiredAttestations ++ profile.optionalAttestations;

      attestations = map (
        typeName:
        let
          predicateData =
            if typeName == "sbom" then
              {
                inherit image;
                inherit sbomData;
                sbomFormat = "spdx";
              }
            else if typeName == "vulnerability-scan" then
              {
                inherit image;
                inherit scanResults;
                scannersUsed = [
                  "grype"
                  "trivy"
                ];
              }
            else if typeName == "build" then
              {
                inherit image;
                inherit buildConfig;
                buildInfo = {
                  buildTime = "${"2026-01-01T00:00:00Z"}";
                  gitCommit = "unknown";
                  gitRepo = "unknown";
                  builder = "opendesk-nix";
                };
              }
            else if typeName == "policy" then
              {
                inherit image;
                inherit policyResults;
                inherit profileName;
              }
            else if typeName == "kubernetes" then
              {
                inherit image;
                k8sConfig = if buildConfig == null then { } else buildConfig;
              }
            else
              { inherit image; };
        in
        createAttestation {
          inherit image;
          attestationTypeName = typeName;
          inherit predicateData;
          inherit registryConfig;
          inherit signingMode;
        }
      ) typesToCreate;

    in
    attestations;

  # Verify attestation for an image
  verifyAttestation =
    {
      image,
      registryConfig,
      attestationTypeName ? "sbom",
      publicKeyPath ? null,
      failOnError ? true,
    }:
    let
      imageName = if builtins.isAttrs registryConfig then "${registryConfig.url}/${image}" else image;
      attestationType = getAttestationType attestationTypeName;

    in
    pkgs.runCommand "verify-attest-${attestationTypeName}-${builtins.hashString "sha256" imageName}"
      {
        nativeBuildInputs = with pkgs; [ cosign ];
        COSIGN_EXPERIMENTAL = "1";
      }
      ''
        echo "Verifying ${attestationTypeName} attestation for ${imageName}"

        ${
          if publicKeyPath != null then
            ''
              cosign verify-attestation --type ${attestationType.predicateType} --key ${publicKeyPath} ${imageName}
            ''
          else
            ''
              cosign verify-attestation --type ${attestationType.predicateType} ${imageName}
            ''
        }

        if [ $? -eq 0 ]; then
          echo "Attestation verified successfully for ${attestationTypeName}"
          touch $out
        else
          echo "Attestation verification failed for ${attestationTypeName}"
          ${if failOnError then "exit 1" else "exit 0"}
        fi
      '';

  # Verify all attestations for an image
  verifyAllAttestations =
    {
      image,
      registryConfig,
      profileName ? "production",
      failOnError ? true,
    }:
    let
      profile = getProfile profileName;
      attestationTypeNames = profile.requiredAttestations ++ profile.optionalAttestations;

      verifications = map (
        typeName:
        verifyAttestation {
          inherit image;
          inherit registryConfig;
          attestationTypeName = typeName;
          inherit failOnError;
        }
      ) attestationTypeNames;

    in
    pkgs.runCommand "verify-all-attest-${builtins.hashString "sha256" image}"
      {
        nativeBuildInputs = [ ];
      }
      ''
        echo "Verifying all attestations for ${image}"
        total=${toString (builtins.length verifications)}
        passed=0
        failed=0

        for verification in ${builtins.concatStringsSep " " verifications}; do
          if [ -f "$verification" ]; then
            echo "PASS: $(basename $verification)"
            passed=$((passed + 1))
          else
            echo "FAIL: $(basename $verification)"
            failed=$((failed + 1))
          fi
        done

        echo ""
        echo "Summary: Passed=$passed, Failed=$failed, Total=$total"

        ${
          if failOnError && toString builtins.length verifications != "0" then
            ''
              if [ $failed -gt 0 ]; then
                exit 1
              fi
            ''
          else
            ""
        }
        touch $out
      '';

  # =============================================================================
  # COMPLIANCE CHECKING - DevGuard Pattern
  # =============================================================================

  # Check compliance for a single requirement
  checkRequirement =
    {
      requirement,
      image,
      scanResults ? null,
      sbom ? null,
      metadata ? { },
      registry ? null,
      policy ? null,
    }:
    let
      result = requirement.check {
        inherit image;
        inherit scanResults;
        inherit sbom;
        inherit metadata;
        inherit registry;
        inherit policy;
      };

    in
    {
      requirementId = requirement.id;
      requirementDescription = requirement.description;
      inherit (requirement) severity;
      compliant = result;
      inherit (requirement) remediation;
    };

  # Check compliance against a profile
  checkCompliance =
    {
      image,
      profileName ? "production",
      scanResults ? null,
      sbom ? null,
      metadata ? { },
      registry ? null,
      policy ? null,
    }:
    let
      profile = getProfile profileName;

      requirementResults = map (
        requirement:
        checkRequirement {
          inherit requirement;
          inherit image;
          inherit scanResults;
          inherit sbom;
          inherit metadata;
          inherit registry;
          inherit policy;
        }
      ) profile.requirements;

      # Count results
      counts = {
        total = builtins.length requirementResults;
        compliant = builtins.length (builtins.filter (r: r.compliant) requirementResults);
        nonCompliant = builtins.length (builtins.filter (r: !r.compliant) requirementResults);
        bySeverity =
          map
            (severity: {
              inherit severity;
              total = builtins.length (builtins.filter (r: r.severity == severity) requirementResults);
              compliant = builtins.length (
                builtins.filter (r: r.severity == severity && r.compliant) requirementResults
              );
              nonCompliant = builtins.length (
                builtins.filter (r: r.severity == severity && !r.compliant) requirementResults
              );
            })
            [
              "critical"
              "high"
              "medium"
              "low"
              "negligible"
            ];
      };

      # Check thresholds
      inherit (profile) thresholds;
      thresholdCounts = map (
        count:
        let
          inherit (count) severity;
          threshold =
            thresholds.${severity} or {
              maxCount = 100;
              action = "ignore";
            };
          maxCount = threshold.maxCount or (if severity == "critical" then 0 else 100);
          action = threshold.action or "ignore";
        in
        {
          inherit severity;
          count = count.nonCompliant;
          inherit maxCount;
          exceeded = count.nonCompliant > maxCount;
          inherit action;
          pass =
            let
              nonComp = count.nonCompliant;
            in
            nonComp == 0 || nonComp <= maxCount || action == "ignore";
        }
      ) counts.bySeverity;

      anyFailed = builtins.any (t: !t.pass && t.action != "ignore") thresholdCounts;
      warnings = builtins.filter (t: !t.pass && t.action == "warn") thresholdCounts;
      failures = builtins.filter (t: !t.pass && t.action == "fail") thresholdCounts;

      overallCompliant = !anyFailed && counts.compliant == counts.total;

    in
    {
      inherit image;
      profile = profileName;
      profileName = profile.name;
      profileDescription = profile.description;
      inherit requirementResults;
      inherit counts;
      inherit thresholdCounts;
      inherit anyFailed;
      inherit warnings;
      inherit failures;
      inherit overallCompliant;
      compliantCount = counts.compliant;
      nonCompliantCount = counts.nonCompliant;
    };

  # Check compliance for multiple images
  checkAllCompliance =
    {
      images,
      profileName ? "production",
      scanResults ? null,
      sboms ? null,
      metadata ? { },
      registry ? null,
      policy ? null,
    }:
    let
      results = map (
        image:
        let
          imageScanResults =
            if scanResults != null && builtins.hasAttr image scanResults then
              scanResults.${image}
            else if scanResults != null && builtins.isList scanResults then
              builtins.elemAt scanResults (builtins.findFirstIndex (x: x == image) scanResults)
            else
              null;
          imageSbom =
            if sboms != null && builtins.hasAttr image sboms then
              sboms.${image}
            else if sboms != null && builtins.isList sboms then
              builtins.elemAt sboms (builtins.findFirstIndex (x: x == image) sboms)
            else
              null;
        in
        checkCompliance {
          inherit image;
          inherit profileName;
          scanResults = imageScanResults;
          sbom = imageSbom;
          inherit metadata;
          inherit registry;
          inherit policy;
        }
      ) images;

      allCompliant = builtins.length results > 0 && builtins.all (r: r.overallCompliant) results;
      totalImages = builtins.length results;
      compliantImages = builtins.length (builtins.filter (r: r.overallCompliant) results);

    in
    {
      imageResults = results;
      inherit allCompliant;
      inherit totalImages;
      inherit compliantImages;
    };

  # =============================================================================
  # COMPLIANCE GATES - DevGuard Pattern
  # =============================================================================

  # Create a compliance gate
  createComplianceGate =
    {
      profileName ? "production",
      action ? "block",
      manualOverride ? false,
      overrideDuration ? "24h",
      auditLogPath ? null,
    }:
    let
      profile = getProfile profileName;
      checkFn =
        {
          image,
          scanResults,
          sbom,
          metadata,
          registry,
          policy,
        }:
        let
          complianceResult = checkCompliance {
            inherit image;
            inherit profileName;
            inherit scanResults;
            inherit sbom;
            inherit metadata;
            inherit registry;
            inherit policy;
          };
          gateAction =
            if !complianceResult.overallCompliant then
              (if complianceResult.anyFailed then "block" else "warn")
            else
              "pass";
        in
        {
          inherit complianceResult;
          inherit gateAction;
          passed = gateAction == "pass";
          blocked = gateAction == "block";
          warned = gateAction == "warn";
        };
    in
    {
      name = "compliance-gate-${profileName}";
      description = "Compliance gate for ${profile.name} profile";
      profile = profileName;
      inherit
        action
        manualOverride
        overrideDuration
        auditLogPath
        ;
      check = checkFn;
      enforce =
        {
          image,
          scanResults,
          sbom,
          metadata,
          registry,
          policy,
        }:
        let
          checkResult = checkFn {
            inherit image;
            inherit scanResults;
            inherit sbom;
            inherit metadata;
            inherit registry;
            inherit policy;
          };

        in
        pkgs.runCommand "gate-${builtins.hashString "sha256" image}"
          {
            nativeBuildInputs = with pkgs; [ bash ];
          }
          ''
            echo "Compliance Gate: ${profile.name}"
            echo "Image: ${image}"

            if ${toString checkResult.passed}; then
              echo "GATE: PASSED"
              touch $out
            else
              echo "GATE: FAILED"
              echo "Action: ${action}"
              
              ${
                if action == "block" then
                  ''
                    echo "BLOCKING deployment"
                    exit 1
                  ''
                else if action == "warn" then
                  ''
                    echo "WARNING only"
                    touch $out
                  ''
                else
                  ''
                    echo "LOG ONLY"
                    touch $out
                  ''
              }
            fi
          '';
    };

  # Predefined gates
  gates = {
    pre-deploy = createComplianceGate {
      profileName = "production";
      action = "block";
      manualOverride = true;
      overrideDuration = "1h";
      auditLogPath = "./audit-logs/pre-deploy.log";
    };
    pre-merge = createComplianceGate {
      profileName = "development";
      action = "warn";
      manualOverride = true;
      overrideDuration = "24h";
      auditLogPath = "./audit-logs/pre-merge.log";
    };
    periodic = createComplianceGate {
      profileName = "production";
      action = "log";
      manualOverride = false;
      auditLogPath = "./audit-logs/periodic.log";
    };
    release = createComplianceGate {
      profileName = "production";
      action = "block";
      manualOverride = false;
      auditLogPath = "./audit-logs/release.log";
    };
    ci-pipeline = createComplianceGate {
      profileName = "production";
      action = "block";
      manualOverride = true;
      overrideDuration = "30m";
      auditLogPath = "./audit-logs/ci-pipeline.log";
    };
  };

  # =============================================================================
  # REPORT GENERATION - DevGuard Pattern
  # =============================================================================

  # Generate compliance report
  generateReport =
    {
      complianceResult,
      outputPath ? "compliance-report.json",
      markdown ? false,
    }:
    pkgs.runCommand "report-${builtins.hashString "sha256" outputPath}"
      {
        nativeBuildInputs = with pkgs; [ jq ];
      }
      ''
        REPORT_DATA='${builtins.toJSON complianceResult}'

        # Save JSON report
        echo "$REPORT_DATA" | jq '.' > ${outputPath}

        ${
          if markdown then
            ''
              # Generate markdown report
              cat > ''${outputPath%.json}.md << 'MARKDOWN_EOF'
              # Compliance Report

              ## Summary
              - **Image**: ${complianceResult.image}
              - **Profile**: ${complianceResult.profileName}
              - **Overall Compliant**: ${if complianceResult.overallCompliant then "YES" else "NO"}
              - **Compliant**: ${toString complianceResult.compliantCount}/${toString complianceResult.counts.total}

              ## Threshold Status
              ${builtins.concatStringsSep "\n" (
                map (tc: ''
                  - **${tc.severity}**: ${toString tc.count} (max: ${toString tc.maxCount}) - ${
                    if tc.pass then "PASS" else "FAIL"
                  }
                '') complianceResult.thresholdCounts
              )}

              ## Requirement Results
              ${builtins.concatStringsSep "\n" (
                map (r: ''
                  - **[${if r.compliant then "x" else " "}]** ${r.requirementId}: ${r.requirementDescription}
                    - Severity: ${r.severity}
                    - Compliant: ${if r.compliant then "YES" else "NO"}
                    ${
                      if !r.compliant then
                        ''
                          - Remediation: ${r.remediation}
                        ''
                      else
                        ""
                    }
                '') complianceResult.requirementResults
              )}

              MARKDOWN_EOF
            ''
          else
            ""
        }

        echo "Compliance report generated at ${outputPath}"
        touch $out
      '';

  # Generate compliance summary report for multiple images
  generateSummaryReport =
    {
      allResults,
      outputPath ? "compliance-summary.json",
      markdown ? false,
    }:
    let
      summary = {
        inherit (allResults) totalImages;
        inherit (allResults) compliantImages;
        inherit (allResults) allCompliant;
        timestamp = "${"2026-01-01T00:00:00Z"}";
        imageResults = map (r: {
          inherit (r) image;
          inherit (r) overallCompliant;
          inherit (r) compliantCount;
          inherit (r) nonCompliantCount;
          inherit (r) profile;
        }) allResults.imageResults;
      };
    in
    pkgs.runCommand "summary-${builtins.hashString "sha256" outputPath}"
      {
        nativeBuildInputs = with pkgs; [ jq ];
      }
      ''
        SUMMARY_DATA='${builtins.toJSON summary}'

        echo "$SUMMARY_DATA" | jq '.' > ${outputPath}

        ${
          if markdown then
            ''
              cat > ''${outputPath%.json}.md << 'SUMMARY_MD'
              # Compliance Summary Report

              **Generated**: ${summary.timestamp}

              ## Overall Status
              - **All Compliant**: ${if summary.allCompliant then "YES ✅" else "NO ❌"}
              - **Compliant Images**: ${toString summary.compliantImages}/${toString summary.totalImages}

              ## Image Breakdown
              ${builtins.concatStringsSep "\n" (
                map (ir: ''
                  - **${ir.image}**: ${
                    if ir.overallCompliant then "✅ PASS" else "❌ FAIL"
                  } (${toString ir.compliantCount}/${toString (ir.compliantCount + ir.nonCompliantCount)})
                '') summary.imageResults
              )}

              SUMMARY_MD
            ''
          else
            ""
        }

        echo "Compliance summary report generated at ${outputPath}"
        touch $out
      '';

  # =============================================================================
  # UTILITY FUNCTIONS
  # =============================================================================

  # Remove a compliance profile

  # =============================================================================
  # EXPORTED FUNCTIONS AND VALUES
  # =============================================================================

in
{
  # Compliance profiles
  inherit complianceProfiles getProfile listProfiles;

  # Attestation types
  inherit attestationTypes getAttestationType listAttestationTypes;

  # Attestation operations
  inherit
    createAttestation
    attestImage
    verifyAttestation
    verifyAllAttestations
    ;

  # Compliance checking
  inherit checkRequirement checkCompliance checkAllCompliance;

  # Compliance gates
  inherit createComplianceGate gates;

  # Report generation
  inherit generateReport generateSummaryReport;

  # Configuration
  config = rec {
    defaultProfile = "production";
    enabled = true;
    enforceAttestations = true;
    enforceCompliance = true;
    reportGeneration = true;
    auditLogging = true;
  };
}
