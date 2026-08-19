# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors

{ 
  lib,
  security ? import ../../nix/security.nix { inherit pkgs lib; },
  registry ? import ../../nix/registry.nix { inherit pkgs lib; },
  types ? import ../../nix/types.nix { inherit lib; },
  sbom ? import ../../nix/sbom.nix { inherit pkgs; },
  pkgs ? import <nixpkgs> { },
  env ? import ../environments/hrz/default.nix { lib = lib; },
}:

let

  # OCI Labels (OpenSpec Compliance - FR-IMAGE-007)
  ociLabels = lib.mkOCILabels {
    name = name;
    version = tag;
    description = "kube-prometheus-stack service for openDesk";
    serviceType = "web";
    component = "backend";
  };

  name = "kube-prometheus-stack";
  namespace = "opendesk";
  port = 9090;
  tag = "v2.51.0";


  # Security configuration
  containerSecurity = security.mkContainerSecurityContext { profile = "monitoring"; };
  podSecurity = security.mkPodSecurityContext { user = 1000; group = 1000; fsGroup = 1000; };

  # Probe configuration
  livenessProbe = lib.mkProbe {
    type = "tcp";
    port = 9090;
    initialDelaySeconds = 30;
    periodSeconds = 10;
    timeoutSeconds = 5;
  };
  readinessProbe = lib.mkProbe {
    type = "tcp";
    port = 9090;
    initialDelaySeconds = 5;
    periodSeconds = 5;
    timeoutSeconds = 3;
  };


in

[
  (lib.statefulset {
    name = name;
    image = "quay.io/prometheus/prometheus:v2.51.0";
    labels = { app = name; };
    selector = { app = name; };
    namespace = namespace;
    ports = [ { name = "http"; containerPort = port; } ];
    volumeClaims = [ { name = "data"; spec = { accessModes = [ "ReadWriteOnce" ]; resources = { requests = { storage = "10Gi"; }; }; }; } ];
    resources = { limits = { cpu = "1"; memory = "2Gi"; }; };
  })

  (lib.service {
    inherit name namespace port;
    selector = { app = name; };
  })
]