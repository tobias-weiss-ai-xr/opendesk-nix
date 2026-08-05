---
capability: compliance
---

## ADDED Requirements

### Requirement: In-toto Attestations
All container images MUST have in-toto attestations.

#### Scenario: SBOM attestation generated
Given an image with SBOM
When attestation generation runs
Then SBOM attestation MUST be created as in-toto attestation
And attestation MUST contain SBOM data
And attestation MUST be signed with Cosign

#### Scenario: Vulnerability scan attestation generated
Given an image with scan results
When attestation generation runs
Then vulnerability-scan attestation MUST be created
And attestation MUST contain scan results
And attestation MUST be signed with Cosign

#### Scenario: Build attestation generated
Given a built image
When attestation generation runs
Then build attestation MUST be created
And attestation MUST contain build configuration
And attestation MUST be signed with Cosign

#### Scenario: Attestations stored in OCI registry
Given attestations generated for an image
When storing attestations
Then attestations MUST be pushed to OCI registry
And attestations MUST be associated with image
And attestations MUST be retrievable from registry

#### Scenario: Attestations verified
Given attestations in OCI registry
When verification runs
Then attestations MUST be fetched from registry
And signatures MUST be verified with Cosign
And verification result MUST be returned

---

### Requirement: Compliance Profiles
The system MUST support predefined compliance profiles.

#### Scenario: SOC2 Type II profile applied
Given SOC2 compliance profile selected
When compliance check runs
Then all SOC2 requirements MUST be checked
And critical threshold MUST be set to 0
And high threshold MUST be set to 5

#### Scenario: ISO27001 profile applied
Given ISO27001 compliance profile selected
When compliance check runs
Then all ISO27001 requirements MUST be checked
And critical threshold MUST be set to 0
And high threshold MUST be set to 3

#### Scenario: CIS Kubernetes profile applied
Given CIS Kubernetes compliance profile selected
When compliance check runs
Then all CIS requirements MUST be checked
And critical threshold MUST be set to 0
And high threshold MUST be set to 0

#### Scenario: Custom profile supported
Given custom compliance profile configured
When compliance check runs
Then user-defined requirements MUST be checked
And user-defined thresholds MUST be applied

---

### Requirement: Policy-Based Deployment Gates
Deployments MUST be automatically blocked if compliance checks fail.

#### Scenario: Deployment blocked on compliance failure
Given compliance check fails
When deployment is attempted
Then deployment MUST be blocked
And error message MUST explain failure reason

#### Scenario: Manual override with audit log
Given compliance failure blocks deployment
When manual override is triggered
Then deployment MUST proceed
And override MUST be logged with timestamp and user
And audit trail MUST be maintained

---

### Requirement: Automated Compliance Reporting
Compliance reports MUST be automatically generated and stored.

#### Scenario: Compliance report generated
Given compliance check runs
When generating report
Then report MUST be created in JSON format
And report MUST be created in Markdown format
And report MUST contain compliance status per requirement

#### Scenario: Compliance report contains required information
Given a compliance report
When viewed
Then report MUST contain requirements met count
And report MUST contain requirements failed count
And report MUST contain severity counts
And report MUST contain recommendations
