# Architecture Overview

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    openDesk Nix                         │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │   Nix       │  │  Kubernetes │  │    Docker   │     │
│  │  Builds     │  │  Deployments│  │  Images     │     │
│  └─────────────┘  └─────────────┘  └─────────────┘     │
│         │                  │                  │         │
│         └──────────────────┼──────────────────┘         │
│                            │                            │
├────────────────────────────┼────────────────────────────┤
│         Platform Layer     │                            │
│  ┌─────────────┐  ┌─────────────────────────────┐      │
│  │   Nix       │  │      Kubernetes             │      │
│  │  Libraries  │  │      Manifests              │      │
│  └─────────────┘  └─────────────────────────────┘      │
├─────────────────────────────────────────────────────────┤
│         Services Layer (78+ Services)                   │
│  MariaDB | SOGo | Nextcloud | Moodle | Keycloak | ...  │
└─────────────────────────────────────────────────────────┘
```

## Key Components

### Nix Build System
- Reproducible builds
- 78 service definitions
- SBOM generation
- Image signing (Cosign)

### Kubernetes Platform
- Core services (ING, DB, Storage)
- Service deployments
- Environment configs (hrz, scs, demo, local)
- Security policies (Kyverno)

### DevGuard Integration
- Multi-registry support
- Compliance checking
- Attestation framework
- Security scanning

## Documentation Navigation

- [Quick Start](quickstart.md) - Get started now
- [Deployment](../deployment/kubernetes.md) - Deploy to cluster
- [Security](../security/security-policy.md) - Security guidelines
- [API Reference](../api/) - Technical APIs
