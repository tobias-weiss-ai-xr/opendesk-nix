---
capability: security-scanning
---

## ADDED Requirements

### Requirement: Multi-Engine Vulnerability Scanning
All container images MUST be scanned by at least 2 different vulnerability scanners.

#### Scenario: Image scanned by Grype and Trivy
Given a Docker image built from OpenDesk-Nix
When the security scanning workflow runs
Then Grype scanning MUST be executed
And Trivy scanning MUST be executed
And both scanners MUST run in parallel
And results from both scanners MUST be aggregated

#### Scenario: Conflicting results flagged
Given a Docker image with conflicting scan results
When the security scanning workflow runs
Then conflicting results MUST be identified
And flagged for manual review

---

### Requirement: SBOM-Based Scanning
All vulnerability scanning MUST use SBOM as input.

#### Scenario: SBOM generated and used for scanning
Given a Docker image
When security scanning runs
Then SPDX format SBOM MUST be generated for the image
And SBOM MUST be stored as build artifact
And all scanners MUST use SBOM as input

#### Scenario: SBOM includes all dependencies
Given a Docker image with multiple dependencies
When SBOM is generated
Then SBOM MUST include all direct dependencies
And SBOM MUST include all transitive dependencies

---

### Requirement: Policy-Based Enforcement
Security scanning MUST support configurable severity-based enforcement.

#### Scenario: Production policy enforces strict thresholds
Given production environment configuration
When security scanning runs
Then critical vulnerabilities with count > 0 MUST cause build failure
And high vulnerabilities with count > 5 MUST generate warning

#### Scenario: Development policy enforces lenient thresholds
Given development environment configuration
When security scanning runs
Then critical vulnerabilities with count > 0 MUST cause build failure
And high vulnerabilities with count > 10 MUST generate warning

---

### Requirement: Automated Reporting
Security scan results MUST be formatted and stored as CI artifacts.

#### Scenario: Scan results stored as CI artifacts
Given security scanning completes
When storing results
Then JSON format report MUST be generated
And Markdown format report MUST be generated
And reports MUST be stored as CI artifacts
And reports MUST be retained for 1 year

#### Scenario: Reports contain required information
Given a security scan report
When viewed
Then report MUST contain vulnerability list with CVEs
And report MUST contain severity distribution
And report MUST contain affected packages
And report MUST contain fix suggestions

---

### Requirement: Performance Optimization
Security scanning MUST be optimized for performance.

#### Scenario: Single scanner performance
Given a Docker image
When scanned by a single scanner
Then scan MUST complete in less than 30 seconds

#### Scenario: Multi-scanner performance
Given a Docker image
When scanned by all enabled scanners in parallel
Then all scans MUST complete in less than 2 minutes

#### Scenario: SBOM generation performance
Given a Docker image
When SBOM is generated
Then generation MUST complete in less than 10 seconds

---

## MODIFIED Requirements

### Requirement: Existing Security Scanning Enhanced
The existing Grype-based security scanning MUST be extended to support multi-engine scanning.

#### Scenario: Backward compatibility maintained
Given existing security-scanning.nix usage
When new version is deployed
Then existing Grype-only scanning MUST still work
And existing flake configurations MUST remain valid

#### Scenario: Existing reports extended
Given existing security reports
When new multi-engine scanning runs
Then reports MUST include Grype results
And reports MUST include Trivy results
