# Installation Guide

Detailed installation instructions for openDesk Nix.

## System Requirements

- Nix 2.18+ with flakes support
- 8GB RAM minimum (16GB recommended)
- 50GB disk space for Nix store
- Kubernetes 1.28+

## Step 1: Install Nix

```bash
# Single-user installation
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# Enable flakes in ~/.config/nix/nix.conf
experimental-features = nix-command flakes
```

## Step 2: Clone Repository

```bash
git clone https://github.com/opendesk-edu/opendesk-nix.git
cd opendesk-nix
```

## Step 3: Configure Environment

```bash
# Set registry URL (if using custom registry)
export OPENCODE_REGISTRY="registry.opencode.de/umr/opendesk-edu/opendesk-nix"

# Configure Kubernetes context
kubectl config use-context your-cluster
```

## Step 4: Build First Image

```bash
# Build SOGo 5 image
nix build .#docker-image-sogo5

# Verify build
ls -lh result/
```

## Troubleshooting

See [Bugs and Fixes](../internal/bugs-and-fixes.md) for known issues.
