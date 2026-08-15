# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# SCS K3s Cluster Deployment — All manifests generated via Nix
# Builds YAML manifests for all openDesk services targeting the SCS K3s cluster.
#
# Usage:
#   nix build .#scs-manifests
#   kubectl apply -f result/

{
  pkgs,
  lib,
  k8s,
  ...
}:

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
  # Decrypt the per-environment sops+age secrets store. Requires SOPS_AGE_KEY in
  # the build environment (CI secret) or ~/.config/sops/age/keys.txt. Falls back
  # to an empty attrset when the key is absent so evaluation (nix flake check)
  # still passes; real secrets materialize only at deploy time. See
  # platform/nix/secrets.nix and scripts/secrets/rotate.sh.
  opencloudSecrets = (import ../../nix/secrets.nix { inherit pkgs; }) ../secrets/scs.enc.json;
  opencloud = import ../services/opencloud.nix {
    lib = k8sLib;
    inherit env;
    secrets = opencloudSecrets;
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

  # Security operators (SCS K3s cluster hardening)
  trivyOperator = import ./trivy-operator.nix {
    lib = k8sLib;
    inherit env;
  };
  kyverno = import ./kyverno.nix {
    lib = k8sLib;
    inherit env;
  };
  kyvernoPolicies = import ./kyverno-policies.nix {
    lib = k8sLib;
  };
  sealedSecrets = import ./sealed-secrets.nix {
    lib = k8sLib;
    inherit env;
  };
  falco = import ./falco.nix {
    lib = k8sLib;
    inherit env;
  };
  cosignPolicies = import ./cosign-policies.nix {
    lib = k8sLib;
    inherit env;
  };

  # Nix builder (builds Nix container images inside the cluster)
  nixBuilder = import ../services/nix-builder.nix {
    lib = k8sLib;
    inherit env;
  };

  # Collect all manifests
  allManifests =
    [
      # Namespaces
      opendeskNamespace
      opendeskEduNamespace
    ]
    # Galera cluster (universal SQL database)
    ++ galera
    # Core services (opendesk namespace)
    ++ keycloak
    ++ synapse
    ++ element
    # Edu services (opendesk-edu namespace)
    ++ sogo
    ++ stalwart
    ++ opencloud
    # Nix builder (nix-builder namespace)
    ++ nixBuilder
    # Security operators (separate namespaces)
    ++ trivyOperator
    ++ kyverno
    ++ kyvernoPolicies
    ++ sealedSecrets
    ++ falco
    ++ cosignPolicies;

  # ---------------------------------------------------------------------------
  # Sealed Secrets — encrypt service Secrets at build time
  # ---------------------------------------------------------------------------
  # Each Secret resource is sealed with the sealed-secrets controller's public
  # key (committed at ../sealed-secrets-pub.pem) using `kubeseal`. The resulting
  # SealedSecret is what gets written to the manifests, so the committed/deployed
  # artifact never contains cleartext. The controller (running in kube-system)
  # decrypts SealedSecrets into real Secrets at apply time.
  #
  # Public key only — safe to commit. The private key lives only in the cluster
  # (the sealed-secrets controller key secret) and is never exported.
  sealedSecretsCert = ../sealed-secrets-pub.pem;

  sealSecret = m:
    let
      secretFile = pkgs.writeText "${m.metadata.name}-secret.json" (builtins.toJSON m);
    in
    pkgs.runCommand "${m.metadata.name}-sealed.json" {
      nativeBuildInputs = [ pkgs.kubeseal ];
    } ''
      kubeseal --cert ${sealedSecretsCert} -n ${m.metadata.namespace or "default"} --name ${m.metadata.name} -o yaml < ${secretFile} > $out
    '';

  # Serialize a resource to YAML. Secrets become SealedSecrets; everything else
  # is emitted verbatim.
  serialize = m:
    if (m.kind or "") == "Secret"
    then builtins.readFile (sealSecret m)
    else builtins.toJSON m;

  # Convert manifests to YAML

  # Build a single YAML file with all manifests
  allYaml = pkgs.writeText "scs-manifests.yaml" (
    builtins.concatStringsSep ''

      ---
    '' (map (m: serialize m) allManifests)
  );

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
    ${builtins.concatStringsSep "\n" (
      map (m: ''
        cat >> $out/10-galera.yaml << 'YAMLEOF'
        ---
        ${serialize m}
        YAMLEOF
      '') galera
    )}

    # Keycloak
    ${builtins.concatStringsSep "\n" (
      map (m: ''
        cat >> $out/20-keycloak.yaml << 'YAMLEOF'
        ---
        ${serialize m}
        YAMLEOF
      '') keycloak
    )}

    # Synapse
    ${builtins.concatStringsSep "\n" (
      map (m: ''
        cat >> $out/30-synapse.yaml << 'YAMLEOF'
        ---
        ${serialize m}
        YAMLEOF
      '') synapse
    )}

    # Element
    ${builtins.concatStringsSep "\n" (
      map (m: ''
        cat >> $out/31-element.yaml << 'YAMLEOF'
        ---
        ${serialize m}
        YAMLEOF
      '') element
    )}

    # SOGo
    ${builtins.concatStringsSep "\n" (
      map (m: ''
        cat >> $out/40-sogo.yaml << 'YAMLEOF'
        ---
        ${serialize m}
        YAMLEOF
      '') sogo
    )}

    # Stalwart
    ${builtins.concatStringsSep "\n" (
      map (m: ''
        cat >> $out/41-stalwart.yaml << 'YAMLEOF'
        ---
        ${serialize m}
        YAMLEOF
      '') stalwart
    )}

    # OpenCloud
    ${builtins.concatStringsSep "\n" (
      map (m: ''
        cat >> $out/42-opencloud.yaml << 'YAMLEOF'
        ---
        ${serialize m}
        YAMLEOF
      '') opencloud
    )}

    # Also write a combined file
    cp ${allYaml} $out/all-manifests.yaml

    # Security operators
    ${builtins.concatStringsSep "\n" (
      map (m: ''
        cat >> $out/50-trivy-operator.yaml << 'YAMLEOF'
        ---
        ${serialize m}
        YAMLEOF
      '') trivyOperator
    )}

    ${builtins.concatStringsSep "\n" (
      map (m: ''
        cat >> $out/51-kyverno.yaml << 'YAMLEOF'
        ---
        ${serialize m}
        YAMLEOF
      '') kyverno
    )}

    ${builtins.concatStringsSep "\n" (
      map (m: ''
        cat >> $out/52-kyverno-policies.yaml << 'YAMLEOF'
        ---
        ${serialize m}
        YAMLEOF
      '') kyvernoPolicies
    )}

    ${builtins.concatStringsSep "\n" (
      map (m: ''
        cat >> $out/53-sealed-secrets.yaml << 'YAMLEOF'
        ---
        ${serialize m}
        YAMLEOF
      '') sealedSecrets
    )}

    ${builtins.concatStringsSep "\n" (
      map (m: ''
        cat >> $out/54-falco.yaml << 'YAMLEOF'
        ---
        ${serialize m}
        YAMLEOF
      '') falco
    )}

    ${builtins.concatStringsSep "\n" (
      map (m: ''
        cat >> $out/55-cosign-policies.yaml << 'YAMLEOF'
        ---
        ${serialize m}
        YAMLEOF
      '') cosignPolicies
    )}
  '';

in
{
  inherit
    env
    allManifests
    allYaml
    manifestDir
    serialize
    ;

  # Individual services
  inherit
    galera
    keycloak
    synapse
    element
    sogo
    stalwart
    opencloud
    nixBuilder
    ;

  # Namespaces
  inherit opendeskNamespace opendeskEduNamespace;

  # Security operators
  inherit
    trivyOperator
    kyverno
    kyvernoPolicies
    sealedSecrets
    falco
    cosignPolicies
    ;
}
