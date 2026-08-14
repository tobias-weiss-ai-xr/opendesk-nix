# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# SCS K3s Cluster Deployment — All manifests generated via Nix
# Builds YAML manifests for all openDesk services targeting the SCS K3s cluster.
#
# Usage:
#   nix build .#scs-manifests
#   kubectl apply -f result/

{ pkgs, lib, k8s, ... }:

let
  # Merge pkgs.lib with k8s builders so service files get both
  k8sLib = lib // k8s;

  # Import the SCS environment
  env = import ../environments/scs/default.nix { inherit lib; };

  # Import all service definitions (k8sLib provides both lib.* and k8s.* functions)
  galera = import ../services/galera.nix {
    lib = k8sLib;
    inherit env;
  };
  keycloak = import ../services/keycloak.nix {
    lib = k8sLib;
    inherit env;
  };
  synapse = import ../services/synapse.nix {
    lib = k8sLib;
    inherit env;
  };
  element = import ../services/element.nix {
    lib = k8sLib;
    inherit env;
  };
  sogo = import ../services/sogo.nix {
    lib = k8sLib;
    inherit env;
  };
  stalwart = import ../services/stalwart.nix {
    lib = k8sLib;
    inherit env;
  };
  opencloud = import ../services/opencloud.nix {
    lib = k8sLib;
    inherit env;
  };

  # Namespace definitions
  opendeskNamespace = k8s.namespace {
    name = "opendesk";
    labels = {
      "istio-injection" = "disabled";
      "pod-security.kubernetes.io/enforce" = "privileged";
    };
  };

  opendeskEduNamespace = k8s.namespace {
    name = "opendesk-edu";
    labels = {
      "istio-injection" = "disabled";
      "pod-security.kubernetes.io/enforce" = "privileged";
    };
  };

  # Nix builder (builds Nix container images inside the cluster)
  nixBuilder = import ../services/nix-builder.nix {
    lib = k8sLib;
    inherit env;
  };

  # Collect all manifests
  allManifests = [
    # Namespaces
    opendeskNamespace
    opendeskEduNamespace
  ]
  # Galera cluster (universal SQL database)
    ++ galera
    # Core services (opendesk namespace)
    ++ keycloak ++ synapse ++ element
    # Edu services (opendesk-edu namespace)
    ++ sogo ++ stalwart ++ opencloud
    # Nix builder (nix-builder namespace)
    ++ nixBuilder;

  # Convert manifests to YAML

  # Build a single YAML file with all manifests
  allYaml = pkgs.writeText "scs-manifests.yaml" (builtins.concatStringsSep ''

    ---
  '' (map (m: builtins.toJSON m) allManifests));

  # Build a directory with individual YAML files
  manifestDir = pkgs.runCommand "scs-manifests" { } ''
    mkdir -p $out

    # Namespaces
    cat > $out/00-namespace-opendesk.yaml << 'EOF'
    ${builtins.toJSON opendeskNamespace}
    EOF

    cat > $out/00-namespace-opendesk-edu.yaml << 'EOF'
    ${builtins.toJSON opendeskEduNamespace}
    EOF

    # Galera
    ${builtins.concatStringsSep "\n" (map (m: ''
      cat >> $out/10-galera.yaml << 'YAMLEOF'
      ---
      ${builtins.toJSON m}
      YAMLEOF
    '') galera)}

    # Keycloak
    ${builtins.concatStringsSep "\n" (map (m: ''
      cat >> $out/20-keycloak.yaml << 'YAMLEOF'
      ---
      ${builtins.toJSON m}
      YAMLEOF
    '') keycloak)}

    # Synapse
    ${builtins.concatStringsSep "\n" (map (m: ''
      cat >> $out/30-synapse.yaml << 'YAMLEOF'
      ---
      ${builtins.toJSON m}
      YAMLEOF
    '') synapse)}

    # Element
    ${builtins.concatStringsSep "\n" (map (m: ''
      cat >> $out/31-element.yaml << 'YAMLEOF'
      ---
      ${builtins.toJSON m}
      YAMLEOF
    '') element)}

    # SOGo
    ${builtins.concatStringsSep "\n" (map (m: ''
      cat >> $out/40-sogo.yaml << 'YAMLEOF'
      ---
      ${builtins.toJSON m}
      YAMLEOF
    '') sogo)}

    # Stalwart
    ${builtins.concatStringsSep "\n" (map (m: ''
      cat >> $out/41-stalwart.yaml << 'YAMLEOF'
      ---
      ${builtins.toJSON m}
      YAMLEOF
    '') stalwart)}

    # OpenCloud
    ${builtins.concatStringsSep "\n" (map (m: ''
      cat >> $out/42-opencloud.yaml << 'YAMLEOF'
      ---
      ${builtins.toJSON m}
      YAMLEOF
    '') opencloud)}

    # Also write a combined file
    cp ${allYaml} $out/all-manifests.yaml
  '';

in {
  inherit env allManifests allYaml manifestDir;

  # Individual services
  inherit galera keycloak synapse element sogo stalwart opencloud nixBuilder;

  # Namespaces
  inherit opendeskNamespace opendeskEduNamespace;
}
