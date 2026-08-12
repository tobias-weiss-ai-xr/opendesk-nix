# Quick Start Guide

Get openDesk Nix up and running in minutes.

## Prerequisites

- Nix with flakes enabled
- Kubernetes cluster (K3s, k3d, or cloud)
- kubectl configured
- Container registry access

## Quick Deployment

```bash
# Build a service image
nix build .#docker-image-sogo5

# Deploy to local cluster
nix run .#deploy-kubernetes -- --environment local

# Check status
kubectl get pods -n opendesk
```

## Next Steps

- [Installation Guide](installation.md) - Detailed setup
- [Architecture Overview](architecture.md) - Understanding the system
- [Deployment Guide](../deployment/kubernetes.md) - Production deployment
