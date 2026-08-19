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
    description = "promtail service for openDesk";
    serviceType = "web";
    component = "backend";
  };

  name = "promtail";
  tag = "2.10.0";
  namespace = "opendesk";
  port = 3101;

  # Probe configuration
  livenessProbe = lib.mkProbe {
    type = "tcp";
    port = 3101;
    initialDelaySeconds = 30;
    periodSeconds = 10;
    timeoutSeconds = 5;
  };
  readinessProbe = lib.mkProbe {
    type = "tcp";
    port = 3101;
    initialDelaySeconds = 5;
    periodSeconds = 5;
    timeoutSeconds = 3;
  };


in

[
  # Promtail DaemonSet - runs on ALL nodes including masters
  (lib.daemonSet {
    inherit name;
    image = "docker.io/grafana/promtail:2.10.0";
    labels = { app = name; };
    selector = { app = name; };
    inherit namespace;
    ports = [ { name = "http-metrics"; containerPort = port; } ];
    resources = { 
      limits = { cpu = "200m"; memory = "200Mi"; }; 
      requests = { cpu = "100m"; memory = "100Mi"; }; 
    };
    tolerations = [
      { key = "node-role.kubernetes.io/master"; operator = "Exists"; effect = "NoSchedule"; }
      { key = "node-role.kubernetes.io/control-plane"; operator = "Exists"; effect = "NoSchedule"; }
    ];
    securityContext = { runAsUser = 0; };
  })

  # Promtail Service
  (lib.service {
    inherit name;
    inherit port;
    selector = { app = name; };
    inherit namespace;
  })
]