# Public Release Notes

**Release Date:** 2026-08-07  
**Repository:** https://github.com/tobias-weiss-ai-xr/opendesk-nix  
**Status:** ✅ **PUBLIC**

---

## Overview

The `opendesk-nix` repository is now publicly available on GitHub. This release contains the complete Nix-based container build infrastructure for openDesk Edu, including security policies, compliance frameworks, and deployment automation.

---

## What's Included

### 🏗️ Build Infrastructure
- **78 container definitions** - Complete Nix build recipes for all openDesk services
- **Multi-registry support** - Build and push to GitHub, GitLab, and custom registries
- **SBOM generation** - SPDX and CycloneDX software bill of materials
- **Image signing** - Cosign keyless signing with Sigstore

### 🔒 Security & Compliance
- **Kyverno policies** - 7 production-ready security policies
- **ZKI-IT-Grundschutz** - 64% compliance coverage (71/111 points)
- **Vulnerability scanning** - Grype, Trivy, Snyk integration
- **DevGuard pipeline** - Unified security, compliance, and registry management

### 📦 Operators
- **Compliance Operator** - Automated ZKI-111 checkpoint scanning
- **Image Builder Operator** - Nix build automation for containers

### 📚 Examples
- **Basic** - Single MariaDB deployment example
- **Advanced** - Groupware stack (MariaDB + Stalwart + SOGo)
- **Compliance** - ZKI-Compliance Kyverno policies

### 🚀 Deployment Automation
- **TLS certificate generation** - Automated Kyverno webhook certificates
- **Operator deployment** - One-command operator installation
- **Policy backup** - Automated Kyverno policy backup with SOPS encryption
- **Emergency procedures** - L1-L4 escalation for policy emergencies

---

## Security Review

All internal infrastructure references have been removed:
- ✅ Internal IP addresses replaced with environment variables
- ✅ No credentials or secrets in repository
- ✅ Public HRZ URLs retained (public deployment targets)
- ✅ Placeholder passwords clearly documented

See `SECURITY-REVIEW.md` for detailed assessment.

---

## Repository Structure

```
opendesk-nix/
├── lib/                          # Core libraries
│   ├── compliance.nix            # ZKI-111 compliance checks
│   ├── registry.nix              # Multi-registry support
│   ├── security-scanning.nix     # Vulnerability scanning
│   └── integrated-devguard.nix   # Unified DevGuard pipeline
│
├── examples/                     # Production-ready examples
│   ├── basic/                    # Single service deployment
│   ├── advanced/                 # Groupware stack
│   └── compliance/               # Kyverno policies
│
├── k8s/                          # Kubernetes configurations
│   ├── security/                 # Security infrastructure
│   │   ├── kyverno-webhook/      # TLS certificates
│   │   ├── policy-backup/        # Automated backup
│   │   └── emergency/            # Emergency procedures
│   └── services/                 # Service definitions
│
├── scripts/                      # Deployment automation
│   ├── generate-tls-certificates.sh
│   ├── deploy-operators.sh
│   └── deployment-guide.md
│
├── docs/                         # Documentation
│   ├── SECURITY_POLICY.md        # Security policy (DPO review)
│   └── POLICY-BACKUP.md          # Backup strategy
│
└── IMPLEMENTATION-*.md           # Implementation plans
```

---

## Getting Started

### Quick Start

```bash
# Clone repository
git clone https://github.com/tobias-weiss-ai-xr/opendesk-nix.git
cd opendesk-nix

# Build a container
nix build .#mariadb

# Deploy operators
./scripts/deploy-operators.sh --namespace opendesk --wait

# Run compliance scan
nix run .#compliance-gates.pre-deploy
```

### Documentation

- **README.md** - Project overview and quick start
- **scripts/deployment-guide.md** - Step-by-step deployment
- **examples/*/README.md** - Example-specific documentation
- **SECURITY-REVIEW.md** - Public release security assessment

---

## Registry Configuration

The repository supports multiple container registries:

| Registry | URL | Status |
|----------|-----|--------|
| GitHub Container Registry | `ghcr.io/tobias-weiss-ai-xr` | ✅ Public |
| GitLab Container Registry | `registry.gitlab.com` | ✅ Public |
| GitLab opencode.de | `registry.opencode.de/umr/opendesk-edu` | 🔒 Private |
| Custom Registry | `registry.example.com` | ⚙️ Configure |

**Configuration:** Use environment variables for registry credentials:
```bash
export GITHUB_TOKEN=xxx
export OPENCODE_TOKEN=xxx
export ZOT_REGISTRY_FALLBACK=registry.example.com:5000
```

---

## Compliance Status

### ZKI-IT-Grundschutz Coverage: 64% (71/111)

| Category | Coverage |
|----------|----------|
| IAM & Authentifizierung | 60% |
| Netzwerksicherheit | 70% |
| Container-Sicherheit | 84% |
| Datensicherheit | 67% |
| Compliance & Audit | 53% |
| Notfallmanagement | 70% |

**Target:** 90%+ by Q4 2026

---

## License

All code and documentation are licensed under the **Apache License 2.0**.

---

## Contributing

We welcome contributions! Please see our contribution guidelines before submitting pull requests.

### Security Issues

If you discover a security vulnerability, please report it responsibly:
- **Email:** security@opendesk-edu.org
- **Do not** disclose vulnerabilities publicly before a fix is available

---

## Support

| Type | Contact |
|------|---------|
| General Questions | devops@opendesk-edu.org |
| Security Issues | security@opendesk-edu.org |
| Compliance Questions | tobias.weiss@hrz.uni-marburg.de |

---

## Changelog

### 2026-08-07 - Initial Public Release

- ✅ Removed all internal IP addresses
- ✅ Added SECURITY-REVIEW.md
- ✅ Published 11 commits with 10,000+ lines of code
- ✅ Complete DevGuard pipeline
- ✅ 7 Kyverno security policies
- ✅ 2 Kubernetes Operators
- ✅ 3 production-ready examples
- ✅ Automated deployment scripts

---

## Acknowledgments

openDesk Edu is developed by the University of Marburg HRZ team and the openDesk community.

**Special Thanks:**
- ZKI (Zentrales Rechenzentrum der KIT) for IT-Grundschutz framework
- BSI (Bundesamt für Sicherheit in der Informationstechnik)
- DevGuard community for security patterns
- Sigstore team for keyless signing

---

**Last Updated:** 2026-08-07  
**Repository:** https://github.com/tobias-weiss-ai-xr/opendesk-nix  
**Status:** ✅ Public
