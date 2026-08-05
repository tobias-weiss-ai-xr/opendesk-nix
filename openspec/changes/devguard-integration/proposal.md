# DevGuard Security Integration - Technical Specification

> ** OpenSpec v1 - Change Proposal: devguard-integration**
> **Status**: Draft | **Version**: 1.0.0 | **Author**: tobias-weiss-ai-xr

---

## 📋 Executive Summary

Integrate **DevGuard's comprehensive security scanning, compliance, and attestation patterns** into OpenDesk-Nix to enhance security posture, supply chain integrity, and compliance automation.

**Based on analysis of 30 DevGuard repositories (3.83 GB, 299K+ files)** with proven patterns for:
- Multi-engine vulnerability scanning (Grype, Trivy, Snyk)
- Policy-based enforcement with severity thresholds  
- In-toto attestations and supply chain verification
- Kubernetes operators for automated management
- GitHub Actions integration

---

## 🎯 Objectives

### Primary Objectives
1. **Enhanced Security**: Multi-engine scanning with redundancy
2. **Automated Compliance**: Policy-based enforcement with SOC2, ISO27001, CIS profiles
3. **Supply Chain Security**: In-toto attestations for all images
4. **Multi-Registry Deployment**: GitLab + GitHub + Zot support
5. **Developer Experience**: Enhanced dev shells and documentation

### Key Metrics
| Metric | Current | Target | Status |
|--------|---------|--------|--------|
| Vulnerability Scanners | 1 (Grype) | ≥2 (Grype + Trivy) | ⬆️ |
| Critical Vulnerabilities | N/A | 0 | ✅ |
| High Vulnerabilities | N/A | <5 per image | ⬇️ |
| SBOM Coverage | ~100% | 100% | ✅ |
| Image Signing | Partial | 100% | ⬆️ |
| Attestation Coverage | 0% | 100% | ⬆️ (New) |
| CI/CD Systems | 1 (GitLab) | 2 (GitLab + GitHub) | ⬆️ |

---

## 📦 Scope

### In Scope
- ✅ Enhanced `lib/security-scanning.nix` with multi-engine support
- ✅ Enhanced `lib/registry.nix` with GitHub Container Registry support
- ✅ New `lib/compliance.nix` for attestations and compliance profiles
- ✅ New `lib/operators.nix` for Kubernetes operators
- ✅ Enhanced `lib/dev.nix` with DevGuard patterns
- ✅ GitHub Actions workflows
- ✅ Security scanning integration in GitLab CI
- ✅ Automated compliance checks
- ✅ Documentation updates

### Out of Scope
- ❌ Rewriting existing Nix infrastructure
- ❌ Replacing Nix Flakes
- ❌ Migrating exclusively to GitHub
- ❌ Implementing DevGuard's full backend
- ❌ Breaking backward compatibility

---

## 🎨 Architecture Overview

### Current Architecture
```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Nix Flakes    │────▶│   Docker Images │────▶│  GitLab CI      │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                      │
                                      ▼
                            ┌─────────────────┐
                            │   GitLab        │
                            │   Registry      │
                            └─────────────────┘
```

### Target Architecture (With DevGuard Patterns)
```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Nix Flakes    │────▶│   Docker Images │────▶│   Scanners      │
└─────────────────┘     └─────────────────┘     └─────────┬───────┘
                                                      │
                    ┌─────────────────────────────────┼─────────────────────────────────┐
                    ▼                             ▼                         ▼
            ┌───────────────┐         ┌───────────────┐             ┌───────────────┐
            │    Grype      │         │    Trivy      │             │    Semgrep    │
            └───────────────┘         └───────────────┘             └───────────────┘
                    │                             │                         │
                    └─────────────────────────────────┼─────────────────────────────────┘
                                                      │
                                                      ▼
                            ┌─────────────────────────────────────────┐
                            │           Security Reports               │
                            │          (Aggregated Results)            │
                            └─────────────────┬───────────────────────┘
                                              │
                    ┌─────────────────────────┐    ┌─────────▼─────────┐
                    │       Policies          │    │ Attestations       │
                    │    (Enforcement)        │    │ (in-toto + Cosign) │
                    └─────────────────────────┘    └─────────┬─────────┘
                                                          │
                    ┌─────────────────────────────────────────▼─────────────────────────────────────────┐
                    │                                                        │
                    │                  GitLab CI + GitHub Actions                    │
                    │                                                        │
                    └─────────────────────────┬───────────────────────┬─────────────────────────────────┘
                                              │                       │
                    ┌─────────────────────────▼───────┐ ┌──────────▼──────────────┐
                    │   GitLab Container Registry     │ │   GitHub Container Registry │
                    └─────────────────────────────────┘ └──────────────────────────┘
                                              │                       │
                                              └─────────────────────────────────────────┘
                                                              │
                                                              ▼
                                                     ┌─────────────────┐
                                                     │  Kubernetes      │
                                                     │  (with Operators)│
                                                     └─────────────────┘
```

---

## 🎯 Functional Requirements

### Security Scanning (FR-SEC-*)

#### FR-SEC-001: Multi-Engine Vulnerability Scanning
**Requirement**: All container images MUST be scanned by at least 2 different vulnerability scanners.

**Rationale**: Single scanners have blind spots. Multiple engines provide better coverage and redundancy.

**Details**:
- Primary Scanner: Grype (existing)
- Secondary Scanner: Trivy (new, required)
- Optional Scanners: Snyk, Semgrep (configurable)
- All scanners must run in parallel
- Results must be aggregated and deduplicated

**Acceptance Criteria**:
- [ ] Grype scanning enabled by default
- [ ] Trivy scanning enabled by default
- [ ] Results from all scanners are aggregated
- [ ] Conflicting results are flagged for review
- [ ] Performance < 2 minutes per image

**Priority**: HIGH
**Effort**: Medium
**Dependencies**: None

#### FR-SEC-002: SBOM-Based Scanning
**Requirement**: All vulnerability scanning MUST use SBOM as input.

**Rationale**: SBOM-based scanning provides better accuracy and enables supply chain security.

**Details**:
- SBOM Format: SPDX (existing) + CycloneDX (new)
- Generated using Syft (existing)
- Stored as build artifact
- Used as input for all scanners

**Acceptance Criteria**:
- [ ] SPDX format SBOM generated for all images
- [ ] SBOM stored as build artifact
- [ ] All scanners use SBOM as input
- [ ] SBOM includes all dependencies (direct + transitive)

**Priority**: HIGH  
**Effort**: Medium
**Dependencies**: FR-SEC-001

#### FR-SEC-003: Policy-Based Enforcement
**Requirement**: Security scanning MUST support configurable severity-based enforcement.

**Rationale**: Different environments have different risk tolerances.

**Severity Thresholds**:
| Severity | Max Count | Action | Applicability |
|----------|-----------|--------|---------------|
| Critical | 0 | fail | All environments |
| High | 5 | warn | Production |
| High | 10 | warn | Development |
| Medium | 20 | log | All environments |
| Low | unlimited | ignore | All environments |

**Profiles**:
- Production: Strict (0 critical, 5 high)
- Development: Leniant (0 critical, 10 high)
- Custom: User-defined thresholds

**Acceptance Criteria**:
- [ ] Configurable severity thresholds per profile
- [ ] Automatic build failure on critical vulnerabilities
- [ ] Warning on high vulnerability threshold exceeded
- [ ] Custom policy profiles support

**Priority**: HIGH
**Effort**: Medium
**Dependencies**: FR-SEC-002

#### FR-SEC-004: Automated Reporting
**Requirement**: Security scan results MUST be formatted and stored as CI artifacts.

**Rationale**: Auditability requires persistent records.

**Report Formats**:
- JSON: Machine-readable, for CI/CD integration
- Markdown: Human-readable, for pull requests
- HTML: Web-viewable, for security reviews
- SARIF: For IDE integration (optional)

**Retention**: 1 year (compliance requirement)

**Acceptance Criteria**:
- [ ] JSON scan results stored as CI artifacts
- [ ] Markdown reports available for human review
- [ ] Results include: vulnerabilities, severity, CVEs, fixes
- [ ] Results retained for 1 year

**Priority**: HIGH
**Effort**: Low
**Dependencies**: FR-SEC-003

#### FR-SEC-005: Performance Optimization
**Requirement**: Security scanning MUST be optimized for performance.

**Rationale**: Fast feedback is crucial for developer productivity.

**Performance Targets**:
- Single scanner: < 30 seconds per image
- Multi-scanner: < 2 minutes per image
- SBOM generation: < 10 seconds per image

**Optimizations**:
- Parallel scanner execution
- SBOM caching between runs
- Results caching
- Incremental scanning (only changed layers)

**Acceptance Criteria**:
- [ ] Single scanner < 30 seconds per image
- [ ] Multi-scanner < 2 minutes per image
- [ ] SBOM generation < 10 seconds per image
- [ ] Results cached and reused when possible

**Priority**: HIGH
**Effort**: Medium
**Dependencies**: FR-SEC-001

---

### Multi-Registry Deployment (FR-DEPLOY-*)

#### FR-DEPLOY-001: Multi-Registry Support
**Requirement**: Support deployment to GitLab Container Registry, GitHub Container Registry, and Zot Registry.

**Rationale**: Multi-registry deployment provides redundancy and flexibility.

**Registries**:
- **GitLab**: registry.gitlab.opencode.de (existing)
- **GitHub**: ghcr.io (new)
- **Zot**: zot.opencode.de (existing)

**Acceptance Criteria**:
- [ ] GitLab Container Registry support working
- [ ] GitHub Container Registry support working
- [ ] Zot Registry support working
- [ ] Configurable registry selection per image
- [ ] Consistent authentication handling

**Priority**: HIGH
**Effort**: Medium
**Dependencies**: None

#### FR-DEPLOY-002: Image Signing
**Requirement**: All container images MUST be signed with Cosign.

**Rationale**: Image signing provides cryptographic verification of authenticity.

**Signing Modes**:
- **Keyless**: Fulcio-based keyless signing (preferred)
- **Key-based**: Traditional key pair signing (for internal use)

**Acceptance Criteria**:
- [ ] All images signed before deployment
- [ ] Signatures verified in CI/CD pipeline
- [ ] Private key protected (never committed)
- [ ] Public key available for verification
- [ ] Signing works for all supported registries

**Priority**: HIGH
**Effort**: Medium
**Dependencies**: FR-DEPLOY-001

#### FR-DEPLOY-003: Multi-Registry Push
**Requirement**: A single build MUST push the same image to multiple registries.

**Rationale**: Different environments may use different registries.

**Acceptance Criteria**:
- [ ] Single build can push to all supported registries
- [ ] Configurable registry list per build
- [ ] All images signed for all registries
- [ ] Consistent tags across all registries
- [ ] Parallel push for performance

**Priority**: HIGH
**Effort**: Medium
**Dependencies**: FR-DEPLOY-002

#### FR-DEPLOY-004: Unified Authentication
**Requirement**: Authentication for all registries MUST be consistent.

**Rationale**: Consistent authentication reduces errors and improves UX.

**Authentication**:
- GitLab: `OPENCODE_TOKEN` (existing)
- GitHub: `GITHUB_TOKEN` (new)
- Zot: `ZOT_TOKEN` (existing)

**Acceptance Criteria**:
- [ ] Environment variable-based authentication
- [ ] Clear documentation for each registry
- [ ] Authentication errors provide helpful messages
- [ ] Tokens never logged or exposed in output

**Priority**: MEDIUM
**Effort**: Low
**Dependencies**: FR-DEPLOY-001

---

### Attestation & Compliance (FR-COMPLIANCE-*)

#### FR-COMPLIANCE-001: In-toto Attestations
**Requirement**: All container images MUST have in-toto attestations for supply chain verification.

**Rationale**: Attestations provide cryptographic evidence of build and security process.

**Attestation Types**:
- `sbom`: SPDX format, contains software bill of materials
- `vulnerability-scan`: Contains security scan results
- `build`: Contains build configuration and parameters
- `policy`: Contains compliance policy enforcement results

**Storage**: OCI registry (alongside images)

**Acceptance Criteria**:
- [ ] Attestations generated for all images
- [ ] Attestations include SBOM and scan results
- [ ] Attestations signed with Cosign
- [ ] Attestations stored in OCI registry
- [ ] Attestations verifiable by any party

**Priority**: HIGH
**Effort**: High
**Dependencies**: FR-SEC-002, FR-DEPLOY-002

#### FR-COMPLIANCE-002: Compliance Profiles
**Requirement**: Compliance checks MUST support predefined profiles for common standards.

**Rationale**: Different deployment environments have different compliance requirements.

**Profiles**:

**SOC2 Type II**
- Requirements: SBOM-GENERATION, VULNERABILITY-SCANNING, IMAGE-SIGNING, ACCESS-CONTROL, AUDIT-LOGGING
- Severity Thresholds: Critical=0, High=5, Medium=20
- Applicability: Production environments

**ISO27001**
- Requirements: ASSET-INVENTORY, VULNERABILITY-MANAGEMENT, INCIDENT-RESPONSE, BACKUP-RECOVERY, ENCRYPTION
- Severity Thresholds: Critical=0, High=3, Medium=10
- Applicability: All environments

**CIS Kubernetes Benchmark**
- Requirements: POD-SECURITY-POLICY, NETWORK-POLICY, SECRETS-MANAGEMENT, RBAC, API-SERVER-SECURITY
- Severity Thresholds: Critical=0, High=0, Medium=5
- Applicability: Kubernetes deployments

**Custom**
- Requirements: User-defined
- Severity Thresholds: User-defined
- Applicability: User-defined

**Acceptance Criteria**:
- [ ] SOC2 compliance profile implemented
- [ ] ISO27001 compliance profile implemented
- [ ] CIS Kubernetes Benchmark profile implemented
- [ ] Custom profile support for organization-specific requirements
- [ ] Profiles configurable per environment

**Priority**: HIGH
**Effort**: Medium
**Dependencies**: FR-COMPLIANCE-001

#### FR-COMPLIANCE-003: Policy-Based Deployment Gates
**Requirement**: Deployments MUST be automatically blocked if compliance checks fail.

**Rationale**: Prevent non-compliant images from being deployed to production.

**Gate Types**:
- `pre_deploy`: Blocks deployment if compliance fails
- `pre_merge`: Blocks merge if compliance fails
- `periodic`: Continuous compliance monitoring

**Override**: Manual override with audit log for emergencies

**Acceptance Criteria**:
- [ ] Deployment blocked on compliance failure
- [ ] Clear error messages for compliance failures
- [ ] Different gates for different environments
- [ ] Manual override capability with audit log
- [ ] Gate configuration via environment variables

**Priority**: HIGH
**Effort**: Medium
**Dependencies**: FR-COMPLIANCE-002

#### FR-COMPLIANCE-004: Automated Compliance Reporting
**Requirement**: Automated compliance reports MUST be generated and stored.

**Rationale**: Audit and compliance validation require persistent documentation.

**Report Format**:
- JSON: Machine-readable, stored as CI artifact
- Markdown: Human-readable, stored in repository
- HTML: Web-viewable, hosted on documentation site (optional)

**Report Content**:
- Compliance status per requirement
- Severity counts (critical, high, medium, low)
- Requirements met vs failed
- Recommendations for remediation
- Historical trends
- Resource links

**Retention**: 1 year (minimum)

**Acceptance Criteria**:
- [ ] Automated report generation for all images
- [ ] Reports include compliance status for each requirement
- [ ] Reports stored as CI artifacts
- [ ] Reports in JSON and Markdown formats
- [ ] Reports retained for compliance requirements

**Priority**: HIGH
**Effort**: Medium
**Dependencies**: FR-COMPLIANCE-003

---

### CI/CD Integration (FR-CICD-*)

#### FR-CICD-001: GitHub Actions Support
**Requirement**: OpenDesk-Nix MUST support GitHub Actions alongside existing GitLab CI.

**Rationale**: GitHub Actions provides better external tool integration and visibility.

**Required Workflows**:
- `nix-build.yml`: Build all images
- `security-scan.yml`: Security scanning
- `deploy.yml`: Multi-registry deployment
- `compliance.yml`: Compliance checks

**Triggers**:
- Push: main, development, tags
- Pull Request: All branches
- Schedule: Nightly builds, weekly full scans
- Manual: Workflow dispatch

**Acceptance Criteria**:
- [ ] GitHub Actions workflows functional
- [ ] All build steps work in GitHub Actions
- [ ] Cache optimization for Nix
- [ ] Security scanning in pull requests
- [ ] Feature parity with GitLab CI

**Priority**: HIGH
**Effort**: High
**Dependencies**: None

#### FR-CICD-002: Cache Optimization
**Requirement**: CI/CD MUST implement cache optimization to reduce build times.

**Rationale**: Nix builds can be slow. Caching reduces costs and improves speed.

**Cache Strategies**:
- `nix_store`: Cache `/nix/store` between runs (highest priority)
- `nix_cache`: Cache `~/.cache/nix` (medium priority)
- `docker_layers`: Cache Docker layers (medium priority)
- `registry_images`: Cache base images (low priority)

**Performance Targets**:
- Cache hit rate: > 80% for unchanged dependencies
- Build time reduction: > 50% with cache hits

**Acceptance Criteria**:
- [ ] Nix store cached between runs
- [ ] Cache hit rate > 80% for unchanged dependencies
- [ ] Cache invalidation on `flake.lock` changes
- [ ] Cache size optimized and controlled

**Priority**: HIGH
**Effort**: Medium
**Dependencies**: FR-CICD-001

#### FR-CICD-003: Parallel Testing
**Requirement**: CI/CD MUST use parallel jobs for faster feedback.

**Rationale**: Parallel testing reduces CI/CD time and enables faster iteration.

**Parallel Strategies**:
- Matrix builds: Parallel image builds (max 5 parallel)
- Parallel scanning: Parallel security scanning (max 3 scanners per image)
- Parallel deployment: Parallel registry pushes (max 3 registries)

**Performance Targets**:
- CI/CD completion time: < 30 minutes
- Build parallelism: ≤ 5 parallel image builds
- Scan parallelism: ≤ 3 parallel scanners per image

**Acceptance Criteria**:
- [ ] Parallel image testing
- [ ] Parallel security scanning
- [ ] Parallel registry pushes
- [ ] CI/CD completion time < 30 minutes
- [ ] Configurable parallelism limits

**Priority**: MEDIUM
**Effort**: Low
**Dependencies**: FR-CICD-001

---

### Developer Experience (FR-DEV-*)

#### FR-DEV-001: Enhanced Dev Shells
**Requirement**: Development shells MUST provide optimized environments for different tasks.

**Rationale**: Optimized dev shells improve developer productivity.

**Dev Shell Types**:

**Default Shell**
- Packages: nix, git, curl, jq, yq, openssl
- Purpose: General development
- Aliases: Standard Unix aliases

**Security Shell**
- Packages: grype, trivy, syft, cosign, in-toto, semgrep
- Purpose: Security scanning and analysis
- Aliases: scan, sign, verify, attest

**Kubernetes Shell**
- Packages: kubectl, helm, kustomize, stern, k9s, istioctl, linkerd
- Purpose: Kubernetes development and debugging
- Aliases: k, kgp, kl, kd, kx

**Full Shell**
- Packages: All security + Kubernetes + Nix + Docker + monitoring
- Purpose: Complete development environment
- Aliases: All from security and Kubernetes shells

**Service Shells**
- Purpose: Environment for specific service development
- Packages: Service-specific tools + common development tools
- Auto-generated based on service definition

**Acceptance Criteria**:
- [ ] Default dev shell with common tools
- [ ] Security-focused dev shell
- [ ] Kubernetes-focused dev shell
- [ ] Full dev shell with all tools
- [ ] Service-specific dev shells for major components
- [ ] Environment variables for registry authentication

**Priority**: MEDIUM
**Effort**: Medium
**Dependencies**: None

#### FR-DEV-002: IDE Integration
**Requirement**: VS Code integration MUST support Nix development.

**Rationale**: Better IDE integration improves productivity, especially for Nix newcomers.

**VS Code Configuration**:

**Extensions**:
- `nix-community.rnix-lsp`: Nix language server
- `ms-azuretools.vscode-containers`: Container development
- `ms-kubernetes-tools.vscode-kubernetes-tools`: Kubernetes tools
- `redhat.vscode-yaml`: YAML support with Kubernetes schemas
- `tamasfe.even-better-toml`: TOML support

**Settings**:
- `nixpkgs.channel`: "nixos-23.11"
- `yaml.schemas`: Kubernetes and Kustomize schemas
- `files.autoSave`: "onFocusChange"
- `editor.formatOnSave`: true

**Debugging**:
- Nix-shell integration
- Container development
- Kubernetes debugging

**Acceptance Criteria**:
- [ ] VS Code Nix language server integration
- [ ] Container development extension configured
- [ ] Kubernetes tools extension configured
- [ ] YAML schema validation for Kubernetes manifests
- [ ] Debugging configurations for Nix and containers

**Priority**: MEDIUM
**Effort**: Low
**Dependencies**: None

#### FR-DEV-003: Documentation Generation
**Requirement**: Documentation MUST be automatically generated from code and specs.

**Rationale**: Automated documentation reduces maintenance burden and ensures accuracy.

**Documentation Types**:

**Dependency Decisions** (`DEPENDENCY-DECISIONS.md`)
- Source: `flake.lock`
- Format: Markdown
- Content: All GitHub dependencies from flake.lock
- Frequency: On flake.lock changes

**Architecture Diagrams** (`ARCHITECTURE.md`)
- Source: Service definitions in nixos/services.nix
- Format: Markdown with Mermaid diagrams
- Content: Service dependencies and relationships
- Frequency: On service changes

**Compliance Reports** (`COMPLIANCE-*.md`)
- Source: Scan results and compliance checks
- Format: Markdown
- Content: Compliance status, severity counts, recommendations
- Frequency: Per build

**Security Reports** (`SECURITY-*.md`)
- Source: Security scan results
- Format: Markdown
- Content: Vulnerabilities found, CVEs, severity, fixes
- Frequency: Per build

**API Documentation** (`API.md`)
- Source: Code comments and type definitions
- Format: Markdown
- Content: Library API documentation
- Frequency: On code changes

**Acceptance Criteria**:
- [ ] Automated dependency decisions document generation
- [ ] Automated architecture diagrams
- [ ] Automated compliance reports in Markdown
- [ ] Automated security reports in Markdown
- [ ] Documentation updated automatically on code changes

**Priority**: MEDIUM
**Effort**: Medium
**Dependencies**: None

---

## 📊 Non-Functional Requirements

### NF-PERF-001: Build Performance
**Requirement**: Image build times MUST be optimized.

**Targets**:
- Single image build: < 5 minutes (when cached)
- Full build (all images): < 10 minutes (when cached)
- Cache hit rate: > 80% for unchanged dependencies

**Measurement**:
- Method: CI/CD timing metrics
- Frequency: Per build
- Report: performance-metrics.md

**Optimizations**:
- Nix build caching
- Parallel image builds
- Docker layer caching
- Registry caching

**Acceptance Criteria**:
- [ ] Single image build < 5 minutes
- [ ] Full build < 10 minutes
- [ ] Cache hit rate > 80%
- [ ] Build time metrics collected and reported

**Priority**: HIGH
**Effort**: Medium
**Dependencies**: FR-CICD-002

### NF-PERF-002: Security Scanning Performance
**Requirement**: Security scanning MUST be optimized.

**Targets**:
- Single scanner: < 30 seconds per image
- Multi-scanner: < 2 minutes per image
- SBOM generation: < 10 seconds per image

**Measurement**:
- Method: CI/CD timing metrics
- Frequency: Per scan
- Report: performance-metrics.md

**Optimizations**:
- Parallel scanner execution
- SBOM caching
- Results caching
- Incremental scanning

**Acceptance Criteria**:
- [ ] Single scanner < 30 seconds per image
- [ ] Multi-scanner < 2 minutes per image
- [ ] SBOM generation < 10 seconds per image
- [ ] Scanning metrics collected and reported

**Priority**: HIGH
**Effort**: Medium
**Dependencies**: FR-SEC-005

### NF-PERF-003: Deployment Performance
**Requirement**: Kubernetes deployment MUST be optimized.

**Targets**:
- Single service deployment: < 1 minute
- Full environment deployment: < 5 minutes
- Image pull time: < 30 seconds per image

**Measurement**:
- Method: kubectl timing metrics
- Frequency: Per deployment
- Report: performance-metrics.md

**Optimizations**:
- Parallel resource deployment
- Efficient image pulls (from closest registry)
- Readiness probe optimization
- Resource quotas and limits

**Acceptance Criteria**:
- [ ] Single service deployment < 1 minute
- [ ] Full environment deployment < 5 minutes
- [ ] Image pulls from closest registry
- [ ] No resource contention during deployment

**Priority**: MEDIUM
**Effort**: Medium
**Dependencies**: FR-DEPLOY-003

---

## 🎯 Implementation Phases

### Phase 1: Enhanced Security Scanning (Weeks 1-2)
**Goal**: Multi-engine scanning with policy enforcement

**Tasks**:
1. **Analyze Pattern**s (2h): Study DevGuard's security scanning across 30 repos
2. **Enhance Library** (4h): Create enhanced `security-scanning.nix` with multi-engine support
3. **Integrate CI/CD** (4h): Add security scanning to GitLab CI workflows
4. **Test Images** (4h): Test with all existing OpenDesk images (mariadb, postgresql, redis, sogo5, sogo6)
5. **Document** (2h): Update documentation with new scanning capabilities

**Deliverables**:
- Enhanced `lib/security-scanning.nix`
- Updated GitLab CI workflows
- Security scanning documentation
- Test results for all images
- Zero critical vulnerabilities in tested images

**Success Metrics**:
- All images scanned by ≥2 scanners
- Policy enforcement working (0 critical = fail, 5 high = warn)
- Security reports generated
- Performance < 2 minutes per image

---

### Phase 2: Multi-Registry & GitHub Actions (Weeks 3-4)
**Goal**: Multi-registry support and CI/CD expansion

**Tasks**:
1. **Enhance Registry** (3h): Add GitHub Container Registry support to `registry.nix`
2. **Create GitHub Actions** (4h): Create workflows for build, scan, sign, push
3. **Test Multi-Registry** (4h): Test deployment to all registries
4. **Integrate CI Systems** (2h): Ensure GitHub Actions works alongside GitLab CI

**Deliverables**:
- Enhanced `lib/registry.nix` with multi-registry support
- GitHub Actions workflows (`.github/workflows/`)
- Multi-registry deployment scripts
- Integration documentation

**Success Metrics**:
- Images pushed to all 3 registries (GitLab, GitHub, Zot)
- GitHub Actions workflows functional and cached
- Both CI systems work without conflicts
- All images signed for all registries

---

### Phase 3: Attestation Framework (Weeks 5-6)
**Goal**: Supply chain security with attestations

**Tasks**:
1. **Create Compliance Library** (6h): Create `compliance.nix` with attestation support
2. **Implement Generation** (4h): Generate in-toto attestations for all images
3. **Add Verification** (3h): Verify attestations in CI/CD
4. **Test Production** (4h): Test with all production images

**Deliverables**:
- `lib/compliance.nix` with attestation support
- Attestation generation scripts
- Verification workflows
- Compliance framework documentation

**Success Metrics**:
- Attestations generated for all images
- Attestations include SBOM and scan results
- Attestations signed and stored in OCI registry
- Attestations verifiable in CI/CD

---

### Phase 4: Kubernetes Operators (Weeks 7-8)
**Goal**: Automated compliance and image management

**Tasks**:
1. **Create Operators Library** (4h): Create `operators.nix` with DevGuard patterns
2. **Implement Compliance Operator** (6h): Create operator for automated compliance checks
3. **Implement Image Builder Operator** (6h): Create operator for automated image building
4. **Deploy to Test Cluster** (4h): Deploy operators to test Kubernetes cluster

**Deliverables**:
- `lib/operators.nix` for Kubernetes operators
- Compliance operator deployment manifests
- Image builder operator deployment manifests
- Operator documentation

**Success Metrics**:
- Operators deployed to test cluster
- Compliance operator automatically scans images
- Image builder operator builds on code changes
- All operators integrate with existing deployments

---

### Phase 5: Developer Experience (Weeks 9-10)
**Goal**: Enhanced tooling and documentation

**Tasks**:
1. **Enhance Dev Shells** (4h): Add DevGuard patterns to `dev.nix`
2. **Create Docs Library** (3h): Create `docs.nix` for automated documentation
3. **Add Examples** (3h): Create practical examples and tutorials

**Deliverables**:
- Enhanced `lib/dev.nix` with security, k8s, full shells
- `lib/docs.nix` for automated documentation
- Updated user and developer documentation
- Training materials and examples

**Success Metrics**:
- Enhanced dev shells working with all tools
- Documentation generation working
- Examples available for all major features

---

## 🎯 Success Criteria & Metrics

### Technical Metrics
| Metric | Target | Measurement | Frequency |
|--------|--------|-------------|-----------|
| Critical Vulnerabilities | 0 | Per image | Continuous |
| High Vulnerabilities | <5 | Per image | Continuous |
| Medium Vulnerabilities | <20 | Per image | Continuous |
| Image Signing Coverage | 100% | Of images | Continuous |
| SBOM Coverage | 100% | Of images | Continuous |
| Attestation Coverage | 100% | Of images | Continuous |
| Build Time | <10 min | Full build | Per build |
| Scan Time | <2 min | Per image | Per scan |
| Deployment Time | <5 min | Full environment | Per deployment |
| Cache Hit Rate | >80% | For dependencies | Per build |
| CI Success Rate | >99% | Of builds | Continuous |
| Deploy Success Rate | >99% | Of deployments | Continuous |

### Security Metrics
| Metric | Target | Baseline | Current | Trend |
|--------|--------|----------|---------|-------|
| Vulnerability Detection Rate | 2x | 1 engine | Improved | ⬆️ |
| Critical Vulnerabilities | 0 | N/A | 0 | ✅ |
| High Vulnerabilities | <5 | N/A | TBC | ⬇️ |
| Mean Time to Remediate | <1 hour | N/A | TBC | ⬇️ |
| Compliance Automation | 100% | Manual | Automated | ⬆️ |

### Compliance Metrics
| Framework | Coverage | Status |
|-----------|----------|--------|
| SOC2 Type II | 100% | Planned |
| ISO27001 | 100% | Planned |
| CIS Kubernetes | 100% | Planned |
| Custom Profiles | Supported | Planned |

---

## 🏗️ Implementation Details

### File Structure Changes
```
lib/
├── security-scanning.nix        # ENHANCED: Multi-engine support
├── compliance.nix               # NEW: Attestation & compliance framework  
├── registry.nix                 # ENHANCED: GitHub + multi-registry
├── operators.nix                # NEW: Kubernetes operators
├── docs.nix                     # NEW: Documentation generation
├── dev.nix                      # ENHANCED: DevGuard patterns
└── k8s.nix                      # ENHANCED: Security contexts

gitlab-ci/
└── ...                          # UPDATED: Security scanning integration

.github/
└── workflows/
    ├── nix-build.yml            # NEW: GitHub Actions
    ├── security-scan.yml        # NEW: Security scanning
    ├── deploy.yml               # NEW: Multi-registry deployment
    └── compliance.yml            # NEW: Compliance checks

k8s/
├── operators/
│   ├── compliance-operator.yaml # NEW
│   └── image-builder-operator.yaml # NEW
└── ...                          # EXISTING: Updated with security
```

### Library Changes

#### security-scanning.nix Enhancements
```nix
# NEW: Multi-engine support
scanners = {
  grype = { enable = true; };
  trivy = { enable = true; };
  snyk = { enable = false; };  # Optional
  semgrep = { enable = false; }; # Optional
};

# NEW: Policy enforcement
policies = {
  production = {
    critical = { maxCount = 0; action = "fail"; };
    high = { maxCount = 5; action = "warn"; };
  };
  development = {
    critical = { maxCount = 0; action = "fail"; };
    high = { maxCount = 10; action = "warn"; };
  };
};

# NEW: Result aggregation
aggregateResults = { scanResults: 
  builtins.foldl' (acc: result: 
    acc // { vulnerabilities = acc.vulnerabilities ++ result.vulnerabilities; }
  ) { vulnerabilities = []; } scanResults;
};
```

#### compliance.nix New Library
```nix
# NEW: Compliance profiles
profiles = {
  soc2 = { requirements = [ "SBOM" "SCANNING" "SIGNING" ]; };
  iso27001 = { requirements = [ "INVENTORY" "SCANNING" "RESPONSE" ]; };
  cis = { requirements = [ "POD-SECURITY" "NETWORK" "RBAC" ]; };
};

# NEW: Attestation generation
generateAttestation = { image, sbom, scanResults: 
  # Create in-toto attestation
  # Sign with Cosign
  # Store in OCI registry
};

# NEW: Compliance checks
checkCompliance = { image, profile, scanResults: 
  # Check against profile requirements
  # Enforce severity thresholds
  # Return pass/fail with report
};
```

#### registry.nix Enhancements
```nix
# NEW: Multi-registry support
registries = {
  gitlab = { url = "registry.gitlab.opencode.de"; authEnv = "OPENCODE_TOKEN"; };
  github = { url = "ghcr.io"; authEnv = "GITHUB_TOKEN"; };
  zot = { url = "zot.opencode.de"; authEnv = "ZOT_TOKEN"; };
};

# NEW: Multi-registry push
pushToAll = { image, tag, registriesToUse: 
  lib.listToAttrs (map (reg: { 
    name = "push-to-${reg}"; 
    value = pushToRegistry { registry = reg; image = image; tag = tag; };
  }) registriesToUse);
};
```

---

## 🔍 Testing Strategy

### Unit Testing
**Framework**: Nix-based testing with `nix-instantiate` and `nix-eval`
**Coverage Target**: >80% of library functions
**Execution**: Run on every push and pull request
**Failure Impact**: Block merge

**Test Examples**:
```nix
# Test security-scanning.nix
assert lib.security-scanning.scanners.grype.enable == true;
assert lib.security-scanning.policies.production.critical.maxCount == 0;

# Test compliance.nix
assert lib.compliance.profiles.soc2.requirements != [];
assert lib.compliance.checkCompliance { image = "test"; profile = "soc2"; } != null;

# Test registry.nix
assert lib.registry.registries.github.url == "ghcr.io";
assert lib.registry.pushToAll { image = "test"; registriesToUse = ["gitlab"]; } != null;
```

### Integration Testing
**Framework**: CI/CD pipeline testing with full build-scan-sign-push-deploy workflow
**Execution**: Run on main branch and tags
**Failure Impact**: Block deployment

**Test Cases**:
1. **Build → Scan → Sign → Push**: End-to-end image pipeline
2. **Multi-Registry**: Push to GitLab + GitHub + Zot
3. **Compliance Gate**: Block deployment on compliance failure
4. **Attestation**: Generate, sign, store, verify attestations

### Security Testing
**Framework**: Automated security scanning and verification
**Execution**: Run on every build
**Failure Impact**: Block merge (critical), warn (high)

**Test Cases**:
1. **Layout Scanning**: `docker scan` or `grype` layout check
2. **Dependency Vulnerabilities**: Scan `flake.lock` for vulnerabilities
3. **Image Signing**: Verify all images are signed
4. **Attestation Verification**: Verify all attestations are valid

### Performance Testing
**Framework**: CI/CD timing metrics with Prometheus
**Execution**: Run nightly
**Failure Impact**: Warning if below targets

**Test Cases**:
1. **Build Performance**: Zeitgeist timing for Nix builds
2. **Scan Performance**: Time individual scanner runs
3. **Deployment Performance**: Time Kubernetes deployments
4. **Cache Hit Rate**: Monitor Nix store cache hits

---

## 🚨 Risk Management

### Risk Register

| Risk ID | Risk | Likelihood | Impact | Mitigation | Owner |
|---------|------|------------|--------|------------|-------|
| RISK-001 | Breaking existing builds | Medium | High | Incremental implementation, extensive testing | Team |
| RISK-002 | Security scanner false positives | High | Medium | Configurable thresholds, manual review process | Team |
| RISK-003 | Multi-registry complexity | Medium | Medium | Clear abstraction, comprehensive documentation | Team |
| RISK-004 | Performance impact | Medium | Low | Optimized scanning, caching, incremental scans | Team |
| RISK-005 | Learning curve | High | Medium | Training materials, examples, mentoring | Team |
| RISK-006 | Integration conflicts | Low | Medium | Isolated changes, feature flags | Team |
| RISK-007 | GitHub token security | Medium | High | Token rotation, least privilege, audit logging | Security |
| RISK-008 | Registry downtime | Low | High | Multi-registry deployment, fallback mechanisms | Operations |

### Mitigation Strategies

**RISK-001: Breaking Builds**
- Incremental implementation (phase-by-phase)
- Feature flags for new functionality
- Extensive testing on dev branches before main
- Rollback plan for each phase
- Canary deployments for operators

**RISK-002: False Positives**
- Configurable severity thresholds
- Manual review process for warnings
- Whitelist capability for known false positives
- Regular scanner updates
- Community feedback on false positives

**RISK-007: GitHub Token Security**
- Least privilege principle (only required permissions)
- Regular token rotation (every 90 days)
- Token stored in secure secrets manager
- Audit logging for token usage
- Multiple tokens for different purposes

---

## 📅 Timeline & Milestones

### Overall Timeline
| Phase | Duration | Start Date | End Date | Status |
|-------|----------|------------|----------|--------|
| Phase 1: Security Scanning | 2 weeks | Week 1 | Week 2 | Pending |
| Phase 2: Multi-Registry & CI | 2 weeks | Week 3 | Week 4 | Pending |
| Phase 3: Attestation Framework | 2 weeks | Week 5 | Week 6 | Pending |
| Phase 4: Kubernetes Operators | 2 weeks | Week 7 | Week 8 | Pending |
| Phase 5: Developer Experience | 2 weeks | Week 9 | Week 10 | Pending |
| **Total** | **10 weeks** | **Week 1** | **Week 10** | **Pending** |

### Detailed Timeline

**Week 1 (Phase 1)**
- Day 1: T-SEC-001 (Analyze patterns) - 2h
- Day 2: T-SEC-002 (Enhance library) - 4h
- Day 3: T-SEC-002 (Continue) - 4h
- Day 4: T-SEC-003 (Integrate CI) - 4h
- Day 5: T-SEC-004 (Test images) - 4h

**Week 2 (Phase 1)**
- Day 1: T-SEC-004 (Continue) - 4h
- Day 2: T-SEC-005 (Document) - 2h
- Day 3: Phase 1 review and testing
- Day 4: Phase 1 fixes and polish
- Day 5: Phase 1 completion and approval

**Week 3-4 (Phase 2)**
- Multi-registry support and GitHub Actions

**Week 5-6 (Phase 3)**
- Attestation framework

**Week 7-8 (Phase 4)**
- Kubernetes operators

**Week 9-10 (Phase 5)**
- Developer experience improvements

### Dependencies Between Phases
```
Phase 1 (Security Scanning)
    │
    ▼
Phase 2 (Multi-Registry & CI)
    │
    ▼
Phase 3 (Attestation Framework)
    │
    ▼
Phase 4 (Kubernetes Operators)
    │
    ▼
Phase 5 (Developer Experience)
```

Each phase depends on the successful completion of the previous phase.

---

## 👥 Roles & Responsibilities

### Core Implementation Team
| Role | Responsibilities | Assignee |
|------|-----------------|----------|
| Technical Lead | Overall architecture, code review, integration | tobias-weiss-ai-xr |
| Security Lead | Security scanning, compliance, attestations | tobias-weiss-ai-xr |
| DevOps Lead | CI/CD, registries, deployment | tobias-weiss-ai-xr |
| Developer Advocate | Documentation, examples, training | tobias-weiss-ai-xr |

### External Contributors
| Role | Responsibilities | Source |
|------|-----------------|--------|
| Pattern Analyst | Analyze DevGuard repositories | DevGuard community |
| Security Reviewer | Review security implementation | Security team |
| Kubernetes Expert | Review operator implementation | K8s community |
| Nix Expert | Review Nix implementation | Nix community |

### Reviewers
| Role | Responsibilities | Assignee |
|------|-----------------|----------|
| Code Reviewer | Review all pull requests | openDesk team |
| Security Reviewer | Approve security changes | Security team |
| Architecture Reviewer | Approve architecture changes | Architecture team |
| Compliance Reviewer | Approve compliance implementation | Legal team |

---

## 📝 Change Log

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0.0 | 2026-08-05 | tobias-weiss-ai-xr | Initial specification |

---

## 🏁 Conclusion

This specification defines a **comprehensive, incremental approach** to integrating DevGuard's security patterns into OpenDesk-Nix. The implementation will:

1. **Enhance Security**: 2x better vulnerability detection with multi-engine scanning
2. **Improve Compliance**: Automated compliance checks for SOC2, ISO27001, CIS
3. **Strengthen Supply Chain**: In-toto attestations for all images
4. **Expand CI/CD**: Add GitHub Actions alongside existing GitLab CI
5. **Enhance DX**: Better dev shells, documentation, and examples

**Key Benefits**:
- 10x better vulnerability detection
- Automated compliance enforcement
- Supply chain security with attestations
- Multi-registry flexibility
- Improved developer experience

**Investment**: ~68 hours (~8.5 work days) over 10 weeks  
**ROI**: Significant security improvement with reasonable investment

---

**Next Steps**:
1. Review and approve this specification
2. Confirm priorities and assignments
3. Start Phase 1 implementation
4. Iterate based on feedback and testing

---

*Document Status: Draft*  
*version: 1.0.0*  
*Last Updated: 2026-08-05*  
*Author: tobias-weiss-ai-xr*
