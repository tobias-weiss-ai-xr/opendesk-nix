# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
# Enhanced with DevGuard patterns for multi-engine scanning, policy enforcement, and reporting

{ lib, pkgs, docking ? null, ... }:

let
  # =============================================================================
  # SCANNER CONFIGURATION
  # =============================================================================
  
  # Security scanning tools - Enhanced with DevGuard patterns
  scanners = {
    grype = {
      enable = true;
      package = pkgs.grype;
      severity = [ "critical" "high" "medium" "low" "negligible" ];
      ignore = [ ];
      # DevGuard pattern: Configurable exit codes
      exitCode = 0;  # 0 = pass on warnings, 1 = fail on any finding
      # DevGuard pattern: SBOM-based scanning
      useSbom = true;
      sbomFormat = "spdx";
    };
    trivy = {
      enable = true;
      package = pkgs.trivy;
      exitCode = 1;
      ignoreUnfixed = true;
      vulnType = [ "os" "library" ];
      severity = [ "CRITICAL" "HIGH" "MEDIUM" "LOW" "UNKNOWN" ];
      # DevGuard pattern: SBOM-based scanning
      useSbom = true;
      sbomFormat = "cyclonedx";
      # DevGuard pattern: Parallel scanning
      parallel = true;
    };
    snyk = {
      enable = false;  # Requires API token
      package = pkgs.snyk;
      severityThreshold = "high";
      # DevGuard pattern: Token configuration
      tokenEnv = "SNYK_TOKEN";
    };
    semgrep = {
      enable = false;  # Optional static analysis
      package = pkgs.semgrep;
      config = "p/ci";
    };
  };

  # =============================================================================
  # POLICY CONFIGURATION - DevGuard Pattern
  # =============================================================================
  
  # Severity-based enforcement policies
  # DevGuard pattern: Configurable thresholds per environment
  policies = {
    production = {
      name = "production";
      description = "Strict security policy for production environments";
      thresholds = {
        critical = { maxCount = 0; action = "fail"; };
        high = { maxCount = 5; action = "warn"; };
        medium = { maxCount = 20; action = "log"; };
        low = { maxCount = lib.mkDefault (100: 100); action = "ignore"; };
        negligible = { action = "ignore"; };
      };
      # DevGuard pattern: Require multiple scanners
      requireScanners = [ "grype" "trivy" ];
      # DevGuard pattern: Require SBOM
      requireSbom = true;
      # DevGuard pattern: Require signing
      requireSigning = true;
    };
    development = {
      name = "development";
      description = "Leniant security policy for development environments";
      thresholds = {
        critical = { maxCount = 0; action = "fail"; };
        high = { maxCount = 10; action = "warn"; };
        medium = { maxCount = 50; action = "log"; };
        low = { maxCount = lib.mkDefault (100: 100); action = "ignore"; };
        negligible = { action = "ignore"; };
      };
      requireScanners = [ "grype" "trivy" ];
      requireSbom = true;
      requireSigning = false;  # Optional in development
    };
    staging = {
      name = "staging";
      description = "Moderate security policy for staging environments";
      thresholds = {
        critical = { maxCount = 0; action = "fail"; };
        high = { maxCount = 8; action = "warn"; };
        medium = { maxCount = 30; action = "log"; };
        low = { maxCount = lib.mkDefault (100: 100); action = "ignore"; };
        negligible = { action = "ignore"; };
      };
      requireScanners = [ "grype" "trivy" ];
      requireSbom = true;
      requireSigning = true;
    };
    # DevGuard pattern: Custom policy support
    custom = { profileName, thresholds, requireScanners ? [ "grype" "trivy" ], requireSbom ? true, requireSigning ? true }:
      {
        name = profileName;
        description = "Custom security policy";
        thresholds = thresholds;
        requireScanners = requireScanners;
        requireSbom = requireSbom;
        requireSigning = requireSigning;
      };
  };

  # Get policy by name with default fallback
  getPolicy = policyName: 
    if builtins.hasAttr policyName policies then
      policies.${policyName}
    else if policyName == "default" || policyName == null then
      policies.production
    else
      throw "Unknown security policy: ${policyName}. Available: ${builtins.concatStringsSep ", " (builtins.attrNames policies)}";

  # =============================================================================
  # SBOM GENERATION - DevGuard Pattern
  # =============================================================================
  
  # Generate SPDX SBOM using Syft
  generateSpdxSbom = { target, output ? "sbom-spdx.json" }:
    pkgs.runCommand "syft-spdx-${builtins.hashString "sha256" target}" {
      inherit (pkgs) syft;
    }''
      mkdir -p $(dirname ${output})
      syft ${target} -o spdx-json > ${output}
    '';

  # Generate CycloneDX SBOM using Syft
  generateCyclonedxSbom = { target, output ? "sbom-cyclonedx.json" }:
    pkgs.runCommand "syft-cyclonedx-${builtins.hashString "sha256" target}" {
      inherit (pkgs) syft;
    }''
      mkdir -p $(dirname ${output})
      syft ${target} -o cyclonedx-json > ${output}
    '';

  # Generate SBOM for Docker image
  generateImageSbom = { image, formats ? [ "spdx" "cyclonedx" ], outputDir ? ./sbom }:
    let
      results = map (format: 
        if format == "spdx" then generateSpdxSbom { target = image; output = "${outputDir}/sbom-spdx.json"; }
        else if format == "cyclonedx" then generateCyclonedxSbom { target = image; output = "${outputDir}/sbom-cyclonedx.json"; }
        else null
      ) formats;
    in results;

  # =============================================================================
  # SCANNER IMPLEMENTATIONS
  # =============================================================================
  
  # Run Grype scan on a Docker image or directory
  # Enhanced with DevGuard patterns: SBOM-based scanning, configurable exit codes
  scanWithGrype = { 
    target, 
    output ? "grype-report.json", 
    format ? "json",
    severity ? "all",
    useSbom ? true,
    sbomPath ? null,
    exitCode ? 0,
    ignore ? [ ]
  }:
    pkgs.runCommand "grype-${builtins.hashString "sha256" target}-${severity}" {
      inherit (pkgs) grype jq;
    }''
      mkdir -p $(dirname ${output})
      
      # DevGuard pattern: Use SBOM if available and requested
      ${if useSbom && sbomPath != null then ''
        GRYPE_CMD="grype sbom:${sbomPath} -o ${format} > ${output}"
      '' else ''
        GRYPE_CMD="grype ${target} -o ${format} > ${output}"
      }''
      
      # DevGuard pattern: Configure severity filtering
      if [ "${severity}" != "all" ]; then
        GRYPE_CMD="$GRYPE_CMD --fail-on ${severity}"
      fi
      
      # DevGuard pattern: Handle ignore list
      ${if ignore != [ ] then ''
        IGNORE_ARGS=$(echo '${builtins.concatStringsSep " --ignore-cve " ignore}' | sed 's/^ *//')
        GRYPE_CMD="$GRYPE_CMD $IGNORE_ARGS"
      '' else ''''}
      
      # Run scan
      $GRYPE_CMD
      
      # DevGuard pattern: Exit code handling
      exit ${toString exitCode}
    '';

  # Run Trivy scan on a Docker image or filesystem
  # Enhanced with DevGuard patterns: SBOM-based scanning, parallel execution
  scanWithTrivy = { 
    target, 
    output ? "trivy-report.json", 
    format ? "json",
    severity ? "HIGH",
    useSbom ? true,
    sbomPath ? null,
    ignoreUnfixed ? true,
    vulnType ? [ "os" "library" ],
    parallel ? true
  }:
    pkgs.runCommand "trivy-${builtins.hashString "sha256" target}-${severity}" {
      inherit (pkgs) trivy;
    }''
      mkdir -p $(dirname ${output})
      
      # DevGuard pattern: Use SBOM if available and requested
      ${if useSbom && sbomPath != null then ''
        TRIVY_CMD="trivy sbom ${sbomPath} -f ${format} -o ${output}"
      '' else ''
        TRIVY_CMD="trivy fs --security-checks vuln ${target} -f ${format} -o ${output}"
        # Also scan as image if it looks like a container
        if [[ "${target}" == *".tar"* || "${target}" == *":* ]]; then
          TRIVY_CMD="trivy image ${target} -f ${format} -o ${output}"
        fi
      ''}
      
      # DevGuard pattern: Configure severity filtering
      TRIVY_CMD="$TRIVY_CMD --severity ${severity}"
      
      # DevGuard pattern: Configure vulnerability types
      ${if vulnType != [ ] then ''
        VULN_TYPES=$(echo '${builtins.concatStringsSep "," vulnType}' | tr '[:upper:]' '[:lower:]')
        TRIVY_CMD="$TRIVY_CMD --vuln-type $VULN_TYPES"
      '' else ''''}
      
      # DevGuard pattern: Ignore unfixed vulnerabilities
      ${if ignoreUnfixed then ''
        TRIVY_CMD="$TRIVY_CMD --ignore-unfixed"
      '' else ''''}
      
      # DevGuard pattern: Parallel execution for better performance
      ${if parallel then ''
        TRIVY_CMD="$TRIVY_CMD --parallel"
      '' else ''''}
      
      # Run scan
      $TRIVY_CMD 2>/dev/null || true
    '';

  # Run Snyk scan (requires SNYK_TOKEN)
  # Enhanced with DevGuard patterns: Token-based authentication
  scanWithSnyk = { 
    target,
    severityThreshold ? "high",
    tokenEnv ? "SNYK_TOKEN"
  }:
    pkgs.runCommand "snyk-${builtins.hashString "sha256" target}" {
      inherit (pkgs) snyk;
    }''
      # DevGuard pattern: Check for token
      if [ -z "${!'${tokenEnv}'}" ]; then
        echo "Warning: ${tokenEnv} not set, skipping Snyk scan"
        touch $out
        exit 0
      fi
      
      snyk test --severity-threshold=${severityThreshold} ${target} || true
      touch $out
    '';

  # Run Semgrep scan for static analysis
  scanWithSemgrep = { 
    target,
    config ? "p/ci",
    output ? "semgrep-report.json"
  }:
    pkgs.runCommand "semgrep-${builtins.hashString "sha256" target}" {
      inherit (pkgs) semgrep;
    }''
      mkdir -p $(dirname ${output})
      semgrep --config=${config} ${target} -j --json -o ${output} || true
    '';

  # =============================================================================
  # MULTI-ENGINE SCANNING - DevGuard Core Pattern
  # =============================================================================
  
  # Scan a container image with multiple engines
  # DevGuard pattern: Parallel execution, result aggregation, policy enforcement
  scanImage = { 
    image, 
    scannersToUse ? [ "grype" "trivy" ],
    outputDir ? "./security-scans",
    policy ? "production",
    generateSbom ? true,
    sbomFormats ? [ "spdx" "cyclonedx" ]
  }:
    let
      policyConfig = getPolicy policy;
      selectedScanners = builtins.filter (name: 
        (builtins.hasAttr name scanners) && 
        (scanners.${name}.enable || builtins.elem name scannersToUse)
      ) scannersToUse;
      
      # Generate SBOM if requested and not already present
      sbomFiles = lib.optional (generateSbom && scannersToUse != [ ]) (
        generateImageSbom { image = image; formats = sbomFormats; outputDir = outputDir; }
      ) or [ ];
      
      # Run all selected scanners in parallel (DevGuard pattern)
      scanResults = map (scannerName: 
        let
          scannerConfig = scanners.${scannerName};
          useSbomForScanner = scannerConfig.useSbom or false;
          sbomPath = if useSbomForScanner && generateSbom then 
            "${outputDir}/sbom-${scannerConfig.sbomFormat or "spdx"}.json"
          else null;
        in
        if scannerName == "grype" then
          scanWithGrype {
            target = image;
            output = "${outputDir}/${builtins.baseNameOf image}-grype.json";
            useSbom = useSbomForScanner;
            sbomPath = sbomPath;
            severity = builtins.concatStringsSep "," scannerConfig.severity;
          }
        else if scannerName == "trivy" then
          scanWithTrivy {
            target = image;
            output = "${outputDir}/${builtins.baseNameOf image}-trivy.json";
            useSbom = useSbomForScanner;
            sbomPath = sbomPath;
            severity = builtins.concatStringsSep "," scannerConfig.severity;
            ignoreUnfixed = scannerConfig.ignoreUnfixed or false;
            vulnType = scannerConfig.vulnType or [ ];
          }
        else if scannerName == "snyk" then
          scanWithSnyk { target = image; }
        else if scannerName == "semgrep" then
          scanWithSemgrep { target = image; }
        else null
      ) selectedScanners;
      
      # DevGuard pattern: Aggregate scan results and check against policy
      aggregatedResult = aggregateResults { 
        scanResults = scanResults;
        policy = policyConfig;
        image = image;
        sbomGenerated = generateSbom;
        scannersUsed = selectedScanners;
      };
      
      # DevGuard pattern: Generate reports in multiple formats
      reportFiles = generateReports { 
        scanResults = scanResults;
        aggregated = aggregatedResult;
        policy = policyConfig;
        outputDir = outputDir;
        image = image;
      };
      
    in scanResults ++ sbomFiles ++ reportFiles ++ [ aggregatedResult ];

  # Scan a filesystem directory with multiple engines
  scanDirectory = { 
    path, 
    scannersToUse ? [ "grype" "trivy" ],
    outputDir ? "./security-scans",
    policy ? "production",
    generateSbom ? true,
    sbomFormats ? [ "spdx" "cyclonedx" ]
  }:
    let
      policyConfig = getPolicy policy;
      selectedScanners = builtins.filter (name: 
        (builtins.hasAttr name scanners) && 
        (scanners.${name}.enable || builtins.elem name scannersToUse)
      ) scannersToUse;
      
      # Generate SBOM for directory
      sbomFiles = lib.optional (generateSbom && scannersToUse != [ ]) (
        let
          sbomResults = map (format: 
            if format == "spdx" then generateSpdxSbom { target = path; output = "${outputDir}/sbom-spdx.json"; }
            else if format == "cyclonedx" then generateCyclonedxSbom { target = path; output = "${outputDir}/sbom-cyclonedx.json"; }
            else null
          ) sbomFormats;
        in sbomResults
      ) or [ ];
      
      # Run all selected scanners
      scanResults = map (scannerName: 
        let
          scannerConfig = scanners.${scannerName};
          useSbomForScanner = scannerConfig.useSbom or false;
          sbomPath = if useSbomForScanner && generateSbom then 
            "${outputDir}/sbom-${scannerConfig.sbomFormat or "spdx"}.json"
          else null;
        in
        if scannerName == "grype" then
          scanWithGrype {
            target = path;
            output = "${outputDir}/grype-report.json";
            useSbom = useSbomForScanner;
            sbomPath = sbomPath;
          }
        else if scannerName == "trivy" then
          scanWithTrivy {
            target = path;
            output = "${outputDir}/trivy-report.json";
            useSbom = useSbomForScanner;
            sbomPath = sbomPath;
          }
        else if scannerName == "snyk" then
          scanWithSnyk { target = path; }
        else if scannerName == "semgrep" then
          scanWithSemgrep { target = path; }
        else null
      ) selectedScanners;
      
      aggregatedResult = aggregateResults { 
        scanResults = scanResults;
        policy = policyConfig;
        image = path;
        sbomGenerated = generateSbom;
        scannersUsed = selectedScanners;
      };
      
      reportFiles = generateReports { 
        scanResults = scanResults;
        aggregated = aggregatedResult;
        policy = policyConfig;
        outputDir = outputDir;
        image = path;
      };
      
    in scanResults ++ sbomFiles ++ reportFiles ++ [ aggregatedResult ];

  # Scan all images with configured scanners
  scanAllImages = { 
    images,
    config ? scanners,
    outputDir ? "./security-scans",
    policy ? "production",
    generateSbom ? true
  }:
    map (image: 
      scanImage {
        image = image;
        scannersToUse = config;
        outputDir = "${outputDir}/${builtins.baseNameOf image}";
        policy = policy;
        generateSbom = generateSbom;
      }
    ) images;

  # =============================================================================
  # RESULT AGGREGATION - DevGuard Pattern
  # =============================================================================
  
  # Aggregate results from multiple scanners
  aggregateResults = { 
    scanResults,
    policy,
    image,
    sbomGenerated ? false,
    scannersUsed ? [ ]
  }:
    let
      # Parse all scan result files
      parsedResults = map (result: 
        if builtins.isAttrs result && builtins.hasAttr "outPath" result then
          pkgs.runCommand "parse-${builtins.hashString "sha256" result.outPath}" {
            inherit (pkgs) jq;
          }''
            # Parse JSON results using jq
            cat ${result} | jq '.' > $out
          ''
        else if builtins.isAttrs result && builtins.hasAttr "out" result then
          result
        else
          null
      ) scanResults;
      
      # Count vulnerabilities by severity across all scanners
      countVulnerabilities = results: 
        let
          allFindings = builtins.concatMap (result: 
            if result == null then [ ]
            else if builtins.isAttrs result && builtins.hasAttr "matches" result then
              result.matches or [ ]
            else if builtins.isAttrs result && builtins.hasAttr "Results" result then
              builtins.concatMap (r: r.Vulnerabilities or [ ]) (result.Results or [ ])
            else [ ]
          ) results;
          
          countBySeverity = severity: 
            builtins.length (builtins.filter (f: 
              let
                sev = builtins.toLower (f.severity or f.Severity or f.level or "unknown");
              in
                sev == builtins.toLower severity || 
                (severity == "critical" && (sev == "critical" || sev == "crit")) ||
                (severity == "high" && (sev == "high" || sev == "h")) ||
                (severity == "medium" && (sev == "medium" || sev == "med" || sev == "m"))
            ) allFindings);
        in
          map (sev: { name = sev; count = countBySeverity sev; }) [ "critical" "high" "medium" "low" "negligible" ];
      
      severityCounts = countVulnerabilities parsedResults;
      
      # Check if thresholds are exceeded
      checkThresholds = counts: 
        let
          thresholdChecks = map (count: 
            let
              severity = count.name;
              threshold = policy.thresholds.${severity} or { maxCount = lib.mkDefault (100: 100); action = "ignore"; };
              action = threshold.action or "ignore";
              maxCount = threshold.maxCount or (if severity == "critical" then 0 else lib.mkDefault (100: 100));
            in
              {
                severity = severity;
                count = count.count;
                maxCount = maxCount;
                exceeded = count.count > maxCount;
                action = action;
                pass = !count.exceeded || action == "ignore";
              }
          ) counts;
          
          anyFailed = builtins.any (t: !t.pass && t.action != "ignore") thresholdChecks;
          warnings = builtins.filter (t: !t.pass && t.action == "warn") thresholdChecks;
          failures = builtins.filter (t: !t.pass && t.action == "fail") thresholdChecks;
        in
          {
            inherit thresholdChecks anyFailed warnings failures;
            shouldFail = anyFailed && builtins.length failures > 0;
            shouldWarn = anyFailed && builtins.length warnings > 0;
          };
      
      thresholdCheck = checkThresholds severityCounts;
      
      # Check policy requirements
      policyCompliance = {
        requireScanners = {
          required = policy.requireScanners or [ ];
          provided = scannersUsed;
          compliant = builtins.all (r: builtins.elem r provided) (policy.requireScanners or [ ]);
        };
        requireSbom = {
          required = policy.requireSbom or false;
          provided = sbomGenerated;
          compliant = !(policy.requireSbom or false) || sbomGenerated;
        };
        allCompliant = 
          (policyCompliance.requireScanners.compliant || policy.requireScanners == null || policy.requireScanners == [ ]) &&
          (policyCompliance.requireSbom.compliant || !(policy.requireSbom or false));
      };
      
      # Overall pass/fail
      overallPass = !thresholdCheck.shouldFail && policyCompliance.allCompliant;
      
    in pkgs.runCommand "aggregate-${builtins.hashString "sha256" image}" {
      inherit (pkgs) jq;
    }''
      # Create aggregated report
      cat > $out << EOF
      {
        "image": "${image}",
        "scanners": ${builtins.toJSON scannersUsed},
        "sbom_generated": ${builtins.toJSON sbomGenerated},
        "severity_counts": ${builtins.toJSON severityCounts},
        "threshold_checks": ${builtins.toJSON thresholdCheck.thresholdChecks},
        "policy_compliance": ${builtins.toJSON policyCompliance},
        "overall_pass": ${builtins.toJSON overallPass},
        "should_fail": ${builtins.toJSON thresholdCheck.shouldFail},
        "should_warn": ${builtins.toJSON thresholdCheck.shouldWarn},
        "warnings": ${builtins.toJSON thresholdCheck.warnings},
        "failures": ${builtins.toJSON thresholdCheck.failures}
      }
      EOF
      
      # Fail if policy requires it
      ${if thresholdCheck.shouldFail then ''
        echo "SECURITY FAILURE: Vulnerability thresholds exceeded for ${image}"
        echo "Severity counts: ${builtins.concatStringsSep ", " (map (s: "${s.name}: ${toString s.count}") severityCounts)}"
        exit 1
      '' else ''
        ${if thresholdCheck.shouldWarn then ''
          echo "SECURITY WARNING: Vulnerability thresholds exceeded for ${image}"
          echo "Severity counts: ${builtins.concatStringsSep ", " (map (s: "${s.name}: ${toString s.count}") severityCounts)}"
        '' else ''echo "SECURITY PASS: All vulnerability thresholds met for ${image}"''}
      ''}
    '';

  # =============================================================================
  # REPORT GENERATION - DevGuard Pattern
  # =============================================================================
  
  # Generate security reports in multiple formats
  generateReports = { 
    scanResults,
    aggregated,
    policy,
    outputDir ? "./security-reports",
    image ? "unknown",
    reportFormats ? [ "json" "markdown" ]
  }:
    let
      results = map (format: 
        if format == "json" then
          pkgs.runCommand "report-${image}-${format}-${builtins.hashString "sha256" (builtins.toJSON aggregated)}" {
            inherit (pkgs) jq;
          }''
            mkdir -p ${outputDir}
            cp ${aggregated} ${outputDir}/security-report-${image}.json
          ''
        else if format == "markdown" then
          generateMarkdownReport {
            aggregated = aggregated;
            output = "${outputDir}/security-report-${image}.md";
          }
        else if format == "html" then
          generateHtmlReport {
            aggregated = aggregated;
            output = "${outputDir}/security-report-${image}.html";
          }
        else if format == "sarif" then
          generateSarifReport {
            scanResults = scanResults;
            output = "${outputDir}/security-report-${image}.sarif";
          }
        else null
      ) reportFormats;
    in results;

  # Generate Markdown report
  generateMarkdownReport = { aggregated, output }:
    pkgs.runCommand "md-report-${builtins.hashString "sha256" output}" {
      inherit (pkgs) jq;
    }''
      mkdir -p $(dirname ${output})
      
      # Extract data from aggregated JSON
      IMAGE=$(echo '${aggregated}' | jq -r '.image // "unknown"')
      POLICY=$(echo '${aggregated}' | jq -r '.policy_compliance // {} | tostring')
      PASS=$(echo '${aggregated}' | jq -r '.overall_pass // false')
      
      # Build markdown report
      cat > ${output} << 'REPORT_EOF'
# Security Scan Report

## Image: ${IMAGE}

**Scan Date:** $(date)

**Status:** $(if [ "$PASS" = "true" ]; then echo "✅ PASS"; else echo "❌ FAIL"; fi)

---

## 📊 Summary

REPORT_EOF
      
      # Add severity counts
      echo '### Vulnerability Counts' >> ${output}
      echo '' >> ${output}
      echo '| Severity | Count | Threshold | Status |' >> ${output}
      echo '|----------|-------|-----------|--------|' >> ${output}
      
      echo '${aggregated}' | jq -r '.severity_counts[] | "| \(.name | ascii_upcase) | \(.count) | \(.maxCount // "N/A") | \(if .count <= (.maxCount // 100) then "✅ OK" else "❌ EXCEEDED" end) |"' >> ${output}
      
      echo '' >> ${output}
      echo '## 🔍 Scanners Used' >> ${output}
      echo '' >> ${output}
      echo '${aggregated}' | jq -r '.scanners | @tsv' | tr '\t' '\n' | sed 's/^/ - /' >> ${output}
      
      echo '' >> ${output}
      echo '## 📋 Policy Compliance' >> ${output}
      echo '' >> ${output}
      echo '${aggregated}' | jq -r '.policy_compliance | to_entries[] | " - \(.key): \(if .value.compliant then "✅" else "❌" end) \(.value.reason // "")"' >> ${output}
      
      # Add threshold check details
      echo '' >> ${output}
      echo '## ⚖️  Threshold Checks' >> ${output}
      echo '' >> ${output}
      echo '${aggregated}' | jq -r '.threshold_checks[] | " - \(.severity | ascii_upcase): \(.count) found, max \(.maxCount) (\(if .pass then "✅ PASS" else "❌ FAIL" end))"' >> ${output}
      
      if [ "$PASS" = "false" ]; then
        echo '' >> ${output}
        echo '## ❌ Failures' >> ${output}
        echo '' >> ${output}
        echo '${aggregated}' | jq -r '.failures[] | " - \(.severity | ascii_upcase): Found \(.count), max allowed \(.maxCount)"' >> ${output}
      fi
      
      if [ "$PASS" = "true" ] && [ -n "$(echo '${aggregated}' | jq -r '.warnings // [] | @tsv' 2>/dev/null)" ]; then
        echo '' >> ${output}
        echo '## ⚠️  Warnings' >> ${output}
        echo '' >> ${output}
        echo '${aggregated}' | jq -r '.warnings[] | " - \(.severity | ascii_upcase): Found \(.count), max allowed \(.maxCount)"' >> ${output}
      fi
      
      cat >> ${output} << 'REPORT_EOF'

---

*Generated automatically by OpenDesk-Nix Security Scanning*
REPORT_EOF
    '';

  # Generate HTML report
  generateHtmlReport = { aggregated, output }:
    pkgs.runCommand "html-report-${builtins.hashString "sha256" output}" {
      inherit (pkgs) jq;
    }''
      mkdir -p $(dirname ${output})
      
      # Create simple HTML report using jq
      echo '${aggregated}' | jq -r '
        "<html><head><title>Security Report</title></head><body>" +
        "<h1>Security Scan Report</h1>" +
        "<p><strong>Image:</strong> \(.image // "unknown")</p>" +
        "<p><strong>Status:</strong> \(if .overall_pass then "✅ PASS" else "❌ FAIL" end)</p>" +
        "<h2>Vulnerability Counts</h2>" +
        "<table border=\"1\"><tr><th>Severity</th><th>Count</th><th>Status</th></tr>" +
        (".severity_counts[] | \"<tr><td>\(.name | ascii_upcase)</td><td>\(.count)</td><td>\(if .count <= (.maxCount // 100) then "✅" else "❌" end)</td></tr>\")" +
        "</table>" +
        "<h2>Scanners</h2><ul>" +
        (".scanners[] | \"<li>\(.)</li>\")" +
        "</ul>" +
        "</body></html>" 
      ' > ${output}
    '';

  # Generate SARIF report for IDE integration
  generateSarifReport = { scanResults, output }:
    pkgs.runCommand "sarif-report-${builtins.hashString "sha256" output}" {
      inherit (pkgs) jq;
    }''
      mkdir -p $(dirname ${output})
      
      # Combine all scan results into SARIF format
      # This is a simplified version - full SARIF would require more complex transformation
      echo '{"version":"2.1.0","runs":[]}' | jq '
        .runs += [{
          "tool": {"driver": {"name": "OpenDesk-Nix Security Scanner", "version": "1.0.0"}},
          "results": []
        }]
      ' > ${output}
      
      # Add results from each scanner
      for result in ${builtins.concatStringsSep " " scanResults}; do
        if [ -f "$result" ]; then
          jq '.runs[0].results += (
            (try ($result | fromjson | .matches // .Results // []) catch []) | 
            map({
              "ruleId": (.vulnerability.id // .ID // "unknown"),
              "level": (if (.severity // .Severity // "") | ascii_downcase == "critical" then "error" 
                         elif (.severity // .Severity // "") | ascii_downcase == "high" then "warning" 
                         elif (.severity // .Severity // "") | ascii_downcase == "medium" then "note" 
                         else "none" end),
              "message": (.description // .Title // "Security vulnerability found"),
              "locations": [{
                "physicalLocation": {
                  "artifactLocation": {"uri": "docker://${IMAGE}"}
                }
              }]
            })
          )' ${output} > ${output}.tmp && mv ${output}.tmp ${output}
        fi
      done
    '';

  # CIS Kubernetes Benchmark scanning
  scanCISKubernetes = { config ? null }:
    pkgs.runCommand "cis-k8s-scan" {
      inherit (pkgs) kube-bench;
    }''
      mkdir -p ./cis-reports
      kube-bench --targets node,master --json --outputfile ./cis-reports/results.json run || true
      touch $out
    '';

  # Run multiple scanners on a target
  scanWithAll = { 
    target, 
    image ? true, 
    directory ? false, 
    outputDir ? "./security-scans",
    policy ? "production",
    scanners ? [ "grype" "trivy" "snyk" "semgrep" ]
  }:
    let
      scanResults = [
        (scanWithGrype { target = target; output = "${outputDir}/grype-results.json"; })
        (scanWithTrivy { target = target; output = "${outputDir}/trivy-results.json"; })
      ] ++ lib.optional (builtins.elem "snyk" scanners) (
        (scanWithSnyk { target = target; })
      ) ++ lib.optional (builtins.elem "semgrep" scanners) (
        (scanWithSemgrep { target = target; })
      );
      
      sbomFiles = if image then [
        (generateSpdxSbom { target = target; output = "${outputDir}/sbom-spdx.json"; })
        (generateCyclonedxSbom { target = target; output = "${outputDir}/sbom-cyclonedx.json"; })
      ] else [ ];
      
      report = generateReports { 
        scanResults = scanResults;
        aggregated = aggregateResults { scanResults = scanResults; policy = getPolicy policy; image = target; sbomGenerated = true; };
        policy = getPolicy policy;
        outputDir = outputDir;
        image = target;
      };
      
    in scanResults ++ sbomFiles ++ report;

  # =============================================================================
  # HEALTH CHECK AND PERFORMANCE METRICS - DevGuard Pattern
  # =============================================================================
  
  # Check if scanning tools are available
  checkScannersAvailable = {
    inherit pkgs;
  }:
    pkgs.runCommand "check-scanners" {} ''
      echo "Checking scanner availability..."
      
      # Check Grype
      if command -v grype &> /dev/null; then
        echo "✅ Grype is available"
      else
        echo "❌ Grype is NOT available"
      fi
      
      # Check Trivy
      if command -v trivy &> /dev/null; then
        echo "✅ Trivy is available"
      else
        echo "❌ Trivy is NOT available"
      fi
      
      # Check Syft (for SBOM)
      if command -v syft &> /dev/null; then
        echo "✅ Syft is available"
      else
        echo "❌ Syft is NOT available"
      fi
      
      # Check Cosign (for signing)
      if command -v cosign &> /dev/null; then
        echo "✅ Cosign is available"
      else
        echo "❌ Cosign is NOT available"
      fi
      
      touch $out
    '';

  # Measure scanning performance
  measureScanPerformance = { image, iterations ? 3 }:
    pkgs.runCommand "perf-${builtins.hashString "sha256" image}" {
      inherit (pkgs) bash time;
    }''
      echo "Measuring scan performance for ${image} with ${iterations} iterations..."
      
      TOTAL_TIME=0
      for i in $(seq 1 ${iterations}); do
        START=$(date +%s%N)
        
        # Run Grype
        grype ${image} > /dev/null 2>&1
        GRYPE_TIME=$(( $(date +%s%N) - START ))
        
        # Run Trivy
        START=$(date +%s%N)
        trivy image ${image} > /dev/null 2>&1
        TRIVY_TIME=$(( $(date +%s%N) - START ))
        
        TOTAL_TIME=$(( TOTAL_TIME + GRYPE_TIME + TRIVY_TIME ))
        
        echo "Iteration $i: Grype=${GRYPE_TIME}ms, Trivy=${TRIVY_TIME}ms"
      done
      
      AVG_TIME=$(( TOTAL_TIME / (iterations * 2) ))
      echo "Average scan time: ${AVG_TIME}ms per scanner"
      echo "{\"image\":\"${image}\",\"avg_time_ms\":${AVG_TIME},\"iterations\":${iterations}}" > $out
    '';

  # =============================================================================
  # UTILITY FUNCTIONS
  # =============================================================================
  
  # Get scanner configuration by name
  getScannerConfig = name: 
    if builtins.hasAttr name scanners then
      scanners.${name}
    else if name == "all" then
      scanners
    else
      throw "Unknown scanner: ${name}. Available: ${builtins.concatStringsSep ", " (builtins.attrNames scanners)}";

  # List all available scanners
  listScanners = : builtins.attrNames scanners;

  # List all available policies
  listPolicies = : builtins.attrNames policies;

  # Validate configuration
  validateConfig = { config }:
    let
      unknownScanners = builtins.filter (s: !builtins.hasAttr s scanners) (config.scanners or [ ]);
      unknownPolicy = if config.policy != null && !builtins.hasAttr config.policy policies then [ config.policy ] else [ ];
    in
      {
        valid = builtins.length unknownScanners == 0 && builtins.length unknownPolicy == 0;
        errors = {
          unknownScanners = unknownScanners;
          unknownPolicy = unknownPolicy;
        };
      };

in {
  # Scanner configurations
  inherit scanners;
  
  # Scanner functions
  inherit scanWithGrype scanWithTrivy scanWithSnyk scanWithSemgrep;
  
  # SBOM generation
  inherit generateSpdxSbom generateCyclonedxSbom generateImageSbom;
  
  # Multi-engine scanning
  inherit scanImage scanDirectory scanAllImages scanWithAll;
  
  # Result processing
  inherit aggregateResults generateReports generateMarkdownReport generateHtmlReport generateSarifReport;
  
  # Policy configuration
  inherit policies getPolicy;
  
  # CIS benchmark
  inherit scanCISKubernetes;
  
  # Utilities
  inherit getScannerConfig listScanners listPolicies validateConfig checkScannersAvailable measureScanPerformance;
  
  # Configuration options
  config = rec {
    inherit scanners;
    grype = scanners.grype;
    trivy = scanners.trivy;
    snyk = scanners.snyk;
    semgrep = scanners.semgrep;
    minSeverity = "HIGH";
    ignoreCves = [ ];
    reportFormats = [ "json" "markdown" ];
    defaultPolicy = "production";
    generateSbom = true;
    sbomFormats = [ "spdx" "cyclonedx" ];
  };
}
