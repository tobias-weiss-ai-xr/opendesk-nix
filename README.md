# openDesk-Nix

> Nix monorepo for opendesk-edu: Kubernetes manifest generation and Nix-built
> container images for the SCS K3s cluster (clrz14-06/07/08).

**Deploy path:** `nix build .#scs-manifests` → `kubectl apply -f result/`
**Image registry:** `registry.opencode.de/umr/opendesk-edu/containers/<image>` (CI-built) · `ghcr.io/tobias-weiss-ai-xr/*` (forked services, private — pulled via the zot pull-through cache on the cluster)

> **Note:** the production `opendesk-edu` namespace is ArgoCD-managed from
> `gitlab.hrz.uni-marburg.de/hrz/kubernetes/opendesk/opendesk-edu.git`
> (path `k8s/opendesk-edu`). This repo is the parallel Nix platform layer;
> keep service definitions converged with the ArgoCD source manually
> (see `platform/kubernetes/services/`).

---

## Quick Start

```bash
# Install Nix + flakes
curl -L https://nixos.org/nix/install | sh
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf

# Build all SCS Kubernetes manifests (namespace, services, secrets)
nix build .#scs-manifests

# Inspect / apply
ls result/
kubectl apply -f result/
```

Per-service subsets: `.#scs-stalwart`, `.#scs-sogo`, `.#scs-galera`,
`.#scs-keycloak`, `.#scs-synapse`, … (see `nix flake show`).

## What lives where

```
opendesk-nix/
├── flake.nix                       # Entry point — 180+ outputs (images, manifests, NixOS variants)
├── platform/
│   ├── kubernetes/
│   │   ├── services/               # One .nix per service (stalwart, sogo, galera, keycloak, …)
│   │   ├── environments/scs/       # SCS cluster environment (hosts, storage, secrets resolution)
│   │   └── scs/                    # Aggregates services → full manifest set
│   ├── nix/k8s.nix                 # k8s resource builders (deployment, service, configMap, secret, pvc)
│   └── nixos/                      # NixOS service modules (host-deployed variants)
├── configurations/                 # NixOS node configurations (k3s-node etc.)
├── monitoring/                     # Prometheus / observability config
└── secrets/                        # Sealed-secrets material
```

## Stalwart (mail)

`platform/kubernetes/services/stalwart.nix` deploys the
`stalwart-rewrite` fork (auto-provisioning of default IMAP folders on
first login). Bootstrap is the JSON DataStore registry
(`config.json` → SQLite at `/data/stalwart.db`); all server settings
(listeners, OIDC directory, domains) live in the registry and are
managed via the JMAP API (`urn:stalwart:jmap`) — not in config files.

The image is a **private** ghcr package; the cluster pulls it through
zot (credential upstream mirror), hosts run sha-pinned loaded images.

## CI

`.gitlab-ci.yml` (on gitlab.opencode.de) builds, scans and pushes
service images; GitHub Actions builds the `stalwart-rewrite` fork to
ghcr (`.github/workflows/`).
