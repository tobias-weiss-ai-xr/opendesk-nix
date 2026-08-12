# openDesk Nix Documentation

Welcome to the openDesk Nix documentation. This directory contains all project documentation organized by topic.

## 📚 Documentation Structure

### 🚀 Getting Started
- [Quick Start Guide](getting-started/quickstart.md) - First steps
- [Installation](getting-started/installation.md) - Setup instructions
- [Architecture Overview](getting-started/architecture.md) - System design

### 📦 Deployment
- [Kubernetes Deployment](deployment/kubernetes.md) - K8s setup
- [Docker Deployment](deployment/docker.md) - Container setup
- [Secrets Management](deployment/secrets.md) - Handling secrets
- [Environments](deployment/environments.md) - Environment configs
- [OPENCODE Push Guide](deployment/OPENCODE_DE_PUSH_GUIDE.md) - GitLab registry

### 🔒 Security
- [Security Policy](security/security-policy.md) - Security guidelines
- [Security Hardening](security/security-hardening.md) - Hardening steps
- [Compliance](security/compliance/) - ZKI-IT-Grundschutz
- [Container.gov.de](security/container-gov-de.md) - Compliance framework
- [DevGuard](security/devguard.md) - DevGuard integration
- [Policy Backup](security/policy-backup.md) - Kyverno backup
- [Security Review](security/security-review.md) - Review status

### 🏛️ Governance
- [Best Practices](governance/best-practices.md) - Development guidelines
- [Implementation Plans](governance/) - Priority plans
- [Implementation Status](governance/implementation-status.md) - Current status
- [Next Steps](governance/next-steps-summary.md) - Upcoming work
- [Public Release Notes](governance/public-release-notes.md) - Release info

### 📖 Reference
- [API Documentation](api/) - Service and operator APIs
- [Platform READMEs](reference/) - Component documentation
- [CIS Benchmark](reference/cis-benchmark.md) - Security benchmark
- [K8s Summary](reference/k8s-summary.md) - Kubernetes overview

### 🏗️ Architecture
- [System Architecture](architecture/) - Design documents

### 🔧 Internal (Development Only)
- [Development Summary](internal/development-summary.md) - Dev overview
- [Migration Tracker](internal/migration-upstream-e2e.md) - Migration status
- [Test Suite](internal/test-suite-summary.md) - Testing info
- [Lib Files Fixed](internal/lib-files-fixed.md) - Library changes
- [DPO Review](internal/dpo-review-request.md) - DPO communication
- [Bugs and Fixes](internal/bugs-and-fixes.md) - Known issues
- [Implementation Reports](internal/) - Historical reports

## 📝 Technical Specifications

See [specs/](../specs/) for technical specifications:
- SOGO5, SOGO6, DEV-AGENT, ZOT specs

## 🔬 OpenSpec Artifacts

See [openspec/](../openspec/) for OpenSpec change proposals and tasks.

## 📂 Service Documentation

Each service has its own README in:
- `platform/docker/services/<service>/nixos/README.md`
- `platform/kubernetes/services/<service>.nix`
