# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors

{ 
  lib,
  security ? import ../../nix/security.nix { inherit pkgs lib; },
  registry ? import ../../nix/registry.nix { inherit pkgs lib; },
  types ? import ../../nix/types.nix { inherit lib; },
  sbom ? import ../../nix/sbom.nix { inherit pkgs; },
  pkgs ? import <nixpkgs> { },
  env ? import ../environments/hrz/default.nix { inherit lib; },
}:

let

  # OCI Labels (OpenSpec Compliance - FR-IMAGE-007)
  ociLabels = lib.mkOCILabels {
    inherit name;
    version = tag;
    description = "filebeat service for openDesk";
    serviceType = "web";
    component = "backend";
  };

  name = "filebeat";
  tag = "8.13.0";
  namespace = "logging";

  # Probe configuration
  livenessProbe = lib.mkProbe {
    type = "tcp";
    port = 80;
    initialDelaySeconds = 30;
    periodSeconds = 10;
    timeoutSeconds = 5;
  };
  readinessProbe = lib.mkProbe {
    type = "tcp";
    port = 80;
    initialDelaySeconds = 5;
    periodSeconds = 5;
    timeoutSeconds = 3;
  };


in

[
  # Filebeat DaemonSet - runs on ALL nodes including masters
  (lib.daemonSet {
    inherit name;
    image = "docker.elastic.co/beats/filebeat:8.13.0";
    labels = { app = name; };
    selector = { app = name; };
    inherit namespace;
    resources = { 
      limits = { cpu = "100m"; memory = "200Mi"; }; 
      requests = { cpu = "100m"; memory = "100Mi"; }; 
    };
    tolerations = [
      { key = "node-role.kubernetes.io/master"; operator = "Exists"; effect = "NoSchedule"; }
      { key = "node-role.kubernetes.io/control-plane"; operator = "Exists"; effect = "NoSchedule"; }
    ];
    securityContext = { runAsUser = 0; };
    serviceAccountName = name;
  })

  # Filebeat Service Account
  (lib.serviceAccount {
    inherit name;
    inherit namespace;
  })

  # Note: Filebeat config is managed separately via configMap in production
  # This Nix module represents the DaemonSet deployment for collecting logs
  # from all nodes and sending to Elasticsearch
]