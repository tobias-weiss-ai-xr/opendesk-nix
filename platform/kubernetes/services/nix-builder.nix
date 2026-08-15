# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Nix Builder — Kubernetes StatefulSet for building Nix container images
# inside the cluster using Ceph-backed PVCs.
#
# The nix-builder provides a persistent Nix environment (nixos/nix:2.35.2)
# with /nix on Ceph RBD and /workspace on CephFS. Build scripts are mounted
# from a ConfigMap. Use `kubectl exec` to run builds.
#
# Usage:
#   nix build .#nix-builder
#   kubectl apply -f result/

{
  lib,
  env ? import ../environments/scs/default.nix { inherit lib; },
  ...
}:

let
  name = "nix-builder";
  namespace = "nix-builder";

  labels = lib.mkLabels { inherit name; } // {
    "app.kubernetes.io/component" = "build";
    "app.kubernetes.io/managed-by" = "nix";
  };

  # Build scripts mounted into the container
  buildScripts = {
    setup.sh = ''
      #!/usr/bin/env bash
      set -euo pipefail
      echo "=== Nix Builder Setup ==="
      if ! command -v skopeo &>/dev/null; then
        echo "Installing skopeo..."
        nix profile install nixpkgs#skopeo
        echo "skopeo installed."
      else
        echo "skopeo already available."
      fi
      if ! command -v git &>/dev/null; then
        echo "Installing git..."
        nix profile install nixpkgs#git
      fi
      echo ""
      echo "=== Nix info ==="
      nix --version
      echo "Store: $(du -sh /nix/store 2>/dev/null | cut -f1)"
      echo "Profile packages: $(ls /nix/var/nix/profiles/default/bin/ 2>/dev/null | wc -l) bins"
      echo ""
      echo "Setup complete. Use /workspace for your git repos and build context."
      echo "Build with: nix build .#<image-name>"
      echo "Push with:  skopeo copy docker-archive:result docker://''${REGISTRY:-172.17.0.6:5001}/<name>:<tag>"

      # Create containers policy for skopeo (allows insecure registries)
      mkdir -p /root/.config/containers
      echo '{"default": [{"type": "insecureAcceptAnything"}]}' > /root/.config/containers/policy.json
      echo "Containers policy created."
    '';

    clone-repo.sh = ''
      #!/usr/bin/env bash
      set -euo pipefail
      REPO_URL="''${1:?Usage: clone-repo.sh <repo-url> [destination]}"
      DEST="''${2:-/workspace/$(basename "$REPO_URL" .git)}"
      echo "Cloning $REPO_URL → $DEST"
      mkdir -p /workspace
      if [ -d "$DEST" ]; then
        echo "Destination exists, pulling..."
        cd "$DEST"
        git pull
      else
        git clone "$REPO_URL" "$DEST"
        cd "$DEST"
      fi
      echo ""
      echo "=== Nix files ==="
      ls -la nix/ 2>/dev/null || echo "No nix/ directory"
      echo ""
      echo "=== Available images ==="
      if [ -f nix/flake.nix ]; then
        cd nix
        nix flake show 2>/dev/null || echo "Run 'nix flake update' first"
      else
        echo "No flake.nix found"
      fi
    '';

    build.sh = ''
      #!/usr/bin/env bash
      set -euo pipefail
      IMAGE_NAME="''${1:?Usage: build.sh <image-name> <tag> [flake-attr] [flake-dir]}"
      TAG="''${2:?Usage: build.sh <image-name> <tag> [flake-attr] [flake-dir]}"
      ATTR="''${3:-$IMAGE_NAME}"
      FLAKE_DIR="''${4:-/workspace/opendesk-edu/nix}"
      REGISTRY="''${REGISTRY:-172.17.0.6:5001}"
      echo "=== Building $ATTR → $REGISTRY/$IMAGE_NAME:$TAG ==="
      if [ ! -f "$FLAKE_DIR/flake.nix" ]; then
        echo "ERROR: $FLAKE_DIR/flake.nix not found."
        echo "Run clone-repo.sh first, or specify flake-dir as 4th argument."
        exit 1
      fi
      cd "$FLAKE_DIR"
      echo "Building $ATTR from $FLAKE_DIR..."
      nix build .#"$ATTR" --print-build-logs
      if [ ! -L "./result" ]; then
        echo "ERROR: nix build did not produce ./result"
        exit 1
      fi
      RESULT=$(readlink -f ./result)
      echo "Built: $RESULT"
      echo ""
      echo "=== Image info ==="
      skopeo inspect docker-archive:"$RESULT" 2>/dev/null | head -20 || true
      echo ""

      # Ensure containers policy exists for skopeo
      mkdir -p /root/.config/containers
      echo '{"default": [{"type": "insecureAcceptAnything"}]}' > /root/.config/containers/policy.json

      echo "=== Pushing to $REGISTRY/$IMAGE_NAME:$TAG ==="
      skopeo copy --dest-tls-verify=false \
        docker-archive:"$RESULT" \
        docker://$REGISTRY/$IMAGE_NAME:$TAG
      echo ""
      echo "=== Verifying in registry ==="
      skopeo inspect --tls-verify=false docker://$REGISTRY/$IMAGE_NAME:$TAG 2>/dev/null | head -10 || true
      echo ""
      echo "Done. Image available at $REGISTRY/$IMAGE_NAME:$TAG"
    '';
  };

  # Init container: copy nix store to PVC on first run

  # Main container
  nixContainer = {
    name = "nix";
    image = "nixos/nix:2.35.2";
    imagePullPolicy = "IfNotPresent";
    command = [
      "sh"
      "-c"
      ''
        if [ ! -f /etc/nsswitch.conf ]; then
          echo "hosts: files dns" > /etc/nsswitch.conf
          echo "networks: files dns" >> /etc/nsswitch.conf
        fi
        if [ ! -e /lib ]; then
          GLIBC_LIB=$(ls -d /nix/store/*-glibc-*/lib 2>/dev/null | head -1)
          if [ -n "$GLIBC_LIB" ]; then
            ln -sf "$GLIBC_LIB" /lib
          fi
        fi
        if ! grep -q "experimental-features" /etc/nix/nix.conf 2>/dev/null; then
          echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf
        fi
        exec sleep infinity
      ''
    ];
    env = [
      {
        name = "NIX_PATH";
        value = "/nix/var/nix/profiles/per-user/root/channels:/root/.nix-defexpr/channels";
      }
      {
        name = "NIX_SSL_CERT_FILE";
        value = "/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt";
      }
      {
        name = "SSL_CERT_FILE";
        value = "/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt";
      }
      {
        name = "GIT_SSL_CAINFO";
        value = "/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt";
      }
      {
        name = "REGISTRY";
        value = env.registry.url or "172.17.0.6:5001";
      }
    ];
    resources = {
      requests = {
        cpu = "2";
        memory = "4Gi";
      };
      limits = {
        cpu = "8";
        memory = "16Gi";
      };
    };
    volumeMounts = [
      {
        name = "nix-store";
        mountPath = "/nix";
      }
      {
        name = "workspace";
        mountPath = "/workspace";
      }
      {
        name = "scripts";
        mountPath = "/scripts";
        readOnly = true;
      }
    ];
  };

  volumes = [
    {
      name = "workspace";
      persistentVolumeClaim = {
        claimName = "nix-workspace";
      };
    }
    {
      name = "scripts";
      configMap = {
        name = "nix-builder-scripts";
        defaultMode = 493;
      };
    }
  ];

  volumeClaims = [
    {
      name = "nix-store";
      spec = {
        accessModes = [ "ReadWriteOnce" ];
        storageClassName = env.storage.rwo;
        resources = {
          requests = {
            storage = "50Gi";
          };
        };
      };
    }
  ];

in
[
  # Namespace
  (lib.namespace {
    inherit name;
    labels = {
      "kubernetes.io/metadata.name" = "nix-builder";
      "app.kubernetes.io/part-of" = "opendesk";
    };
  })

  # Workspace PVC (CephFS, RWX)
  (lib.pvc {
    name = "nix-workspace";
    size = "20Gi";
    storageClass = env.storage.rwx;
    accessModes = [ "ReadWriteMany" ];
    inherit namespace;
    inherit labels;
  })

  # ConfigMap with build scripts
  (lib.configMap {
    name = "nix-builder-scripts";
    inherit namespace labels;
    data = buildScripts;
  })

  # StatefulSet
  (lib.statefulset {
    inherit
      name
      namespace
      labels
      volumes
      volumeClaims
      ;
    image = "nixos/nix";
    tag = "2.35.2";
    port = null;
    probes = false;
    replicas = 1;
    inherit (nixContainer) command;
    inherit (nixContainer) env;
    inherit (nixContainer) resources;
    securityContext = {
      allowPrivilegeEscalation = false;
      runAsNonRoot = false;
      readOnlyRootFilesystem = false;
      capabilities = {
        drop = [ ];
      };
    };
    podSecurityContext = {
      runAsNonRoot = false;
      fsGroup = 0;
      fsGroupChangePolicy = "OnRootMismatch";
    };
    nodeSelector = {
      "node-role.kubernetes.io/control-plane" = "true";
    };
    tolerations = [
      {
        key = "node-role.kubernetes.io/master";
        operator = "Exists";
        effect = "NoSchedule";
      }
    ];
  })

  # Network Policies
  (lib.networkPolicy {
    name = "default-deny-ingress";
    inherit namespace;
    podSelector = {
      matchLabels = {
        app = "nix-builder";
      };
    };
    policyTypes = [ "Ingress" ];
    ingress = [ ];
  })

  (lib.networkPolicy {
    name = "allow-same-namespace";
    inherit namespace;
    podSelector = {
      matchLabels = {
        app = "nix-builder";
      };
    };
    policyTypes = [ "Ingress" ];
    ingress = [
      {
        from = [ { podSelector = { }; } ];
      }
    ];
  })
]
