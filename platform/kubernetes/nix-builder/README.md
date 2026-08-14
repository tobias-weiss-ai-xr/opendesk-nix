# Nix Builder

Kubernetes StatefulSet for building Nix container images inside the cluster.

## Overview

The nix-builder runs `nixos/nix:latest` as a StatefulSet with:
- **Ceph RBD** (50Gi, RWO) for `/nix` — persistent Nix store
- **CephFS** (20Gi, RWX) for `/workspace` — shared build workspace
- **ConfigMap** with build scripts (`setup.sh`, `clone-repo.sh`, `build.sh`)
- **NetworkPolicies** for namespace isolation

## Deploy

```bash
# Apply to cluster
kubectl apply -k platform/kubernetes/nix-builder/

# Or build with Nix
nix build .#scs-nix-builder
kubectl apply -f result
```

## Usage

```bash
# Exec into the builder
kubectl exec -n nix-builder -it nix-builder-0 -- bash

# Setup (first time — installs skopeo and git)
/scripts/setup.sh

# Clone a repo with Nix flake
/scripts/clone-repo.sh https://github.com/opendesk-edu/opendesk-edu.git

# Build an image and push to registry
/scripts/build.sh dkimpy-milter 1.1.8 dkimpy-milter /workspace/opendesk-edu/nix
```

## Build Script

The `build.sh` script:
1. Runs `nix build .#<attr>` in the flake directory
2. Inspects the resulting Docker archive with `skopeo inspect`
3. Pushes to the local registry with `skopeo copy`
4. Verifies the image in the registry

## Configuration

Environment variables (set in the StatefulSet or via overlay):
- `REGISTRY` — container registry URL (default: `172.17.0.6:5001`)
- `HTTP_PROXY` / `HTTPS_PROXY` — proxy settings (empty by default)
- `NIX_PATH` — Nix channel paths
- `NIX_SSL_CERT_FILE` — SSL certificate bundle path

## Storage

| Volume | Mount | Storage Class | Size | Access |
|--------|-------|---------------|------|--------|
| nix-store | /nix | ceph-rbd | 50Gi | RWO |
| nix-workspace | /workspace | ceph-cephfs | 20Gi | RWX |
| scripts | /scripts | ConfigMap | — | RO |

## Overlays

Create an overlay for cluster-specific configuration:

```
nix-builder/
  kustomization.yaml
  namespace.yaml
  pvc.yaml
  configmap.yaml
  statefulset.yaml
  networkpolicy.yaml
  overlay/
    scs/
      kustomization.yaml
      patches/
        proxy.yaml     # Add HTTP_PROXY settings
        registry.yaml   # Change registry URL
```
