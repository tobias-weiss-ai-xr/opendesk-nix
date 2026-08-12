---
capability: cicd
---

## ADDED Requirements

### Requirement: GitHub Actions Support
The system MUST support GitHub Actions alongside existing GitLab CI.

#### Scenario: GitHub Actions build workflow works
Given GitHub Actions nix-build.yml workflow
When triggered by push to main branch
Then Nix environment MUST be set up
And all images MUST be built
And build artifacts MUST be stored

#### Scenario: GitHub Actions security scan workflow works
Given GitHub Actions security-scan.yml workflow
When triggered by push to main branch
Then Nix environment MUST be set up
And security scanning MUST run
And scan reports MUST be stored as artifacts

#### Scenario: GitHub Actions deploy workflow works
Given GitHub Actions deploy.yml workflow
When triggered by tag push
Then images MUST be pushed to all configured registries
And images MUST be signed
And attestations MUST be generated

---

### Requirement: Cache Optimization
CI/CD MUST implement cache optimization.

#### Scenario: Nix store caching works
Given GitHub Actions nix-build.yml workflow
When running on push
Then Nix store MUST be cached between runs
And cache hit MUST improve build time

#### Scenario: Cache hit rate target achieved
Given multiple workflow runs with unchanged dependencies
When measuring cache hit rate
Then cache hit rate MUST be greater than 80%

#### Scenario: Cache invalidation on changes
Given flake.lock file changes
When workflow runs
Then Nix cache MUST be invalidated for changed dependencies
And rebuild MUST occur for affected packages

---

### Requirement: Parallel Testing
CI/CD MUST use parallel jobs.

#### Scenario: Parallel image builds
Given multiple images to build
When build workflow runs
Then images MUST be built in parallel
And maximum parallelism MUST be limited to 5 jobs

#### Scenario: Parallel security scanning
Given multiple images to scan
When security scan workflow runs
Then images MUST be scanned in parallel
And scanners MUST run in parallel for each image

---

## MODIFIED Requirements

### Requirement: GitLab CI Integration Maintained
Existing GitLab CI workflows MUST continue to work alongside GitHub Actions.

#### Scenario: GitLab CI still works
Given existing GitLab CI configuration
When GitHub Actions is added
Then GitLab CI workflows MUST continue to work
And security scanning MUST work in GitLab CI

#### Scenario: Feature parity between CI systems
Given both GitLab CI and GitHub Actions configured
When comparing workflows
Then both systems MUST support image building
And both systems MUST support security scanning
