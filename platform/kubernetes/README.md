# OpenDesk Edu - NixOS Container Deployment for HRZ K3s

Complete NixOS-built container deployment for the openDesk Edu platform on the HRZ Kubernetes cluster.

## ✅ All 78 Services Ready

**Registry**: `registry.opencode.de/umr/opendesk-edu/opendesk-nix`
**Code**: `gitlab.opencode.de/umr/opendesk-edu/opendesk-nix`

### Image Pull Test

```bash
# Test pulling all images
docker pull registry.opencode.de/umr/opendesk-edu/opendesk-nix/nginx:1.25.3-nixos
docker pull registry.opencode.de/umr/opendesk-edu/opendesk-nix/mariadb:11.4.4-nixos
docker pull registry.opencode.de/umr/opendesk-edu/opendesk-nix/keycloak:24.0.0-nixos
```

### Login to Registry

```bash
# Using PAT
echo "$OPENCODE_PAT" | docker login registry.opencode.de -u weiss --password-stdin

# Or using existing token
echo "glpat-RWF58M7NPeyay0BDeHSNGG86MQp1Ojd6Ygk.01.0z17kdnvg" | docker login registry.opencode.de -u weiss --password-stdin
```

## 📁 Directory Structure

```
-opendesk-nix/
  └── k8s/
      ├── README.md                    # This file
      ├── namespace.yaml              # OpenDesk namespace
      ├── image-pull-secret.yaml      # Registry authentication
      ├── core/                       # Core infrastructure
      │   ├── databases/
      │   ├── identity/
      │   └── networking/
      ├── groupware/                  # Groupware services
      ├── learning/                   # Education platforms
      ├── monitoring/                 # Observability stack
      ├── security/                   # Security services
      ├── ai/                         # AI/ML services
      └── values.yaml                 # Global Helm values
```
