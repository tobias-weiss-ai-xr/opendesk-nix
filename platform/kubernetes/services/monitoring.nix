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
    description = "monitoring service for openDesk";
    serviceType = "web";
    component = "backend";
  };
 name = "opendesk-monitoring";
  namespace = "opendesk";
  image = "quay.io/prometheus/prometheus";
  tag = "v2.51.0";
  port = 9090;

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

[ (lib.deployment {
    inherit name;
    image = "${image}:${tag}";
    inherit port;
    labels = { app = name; };
    selector = { app = name; };
    inherit namespace;
    resources = { limits = { cpu = "500m"; memory = "512Mi"; }; };
  })
  (lib.service {
    inherit name;
    inherit port;
    selector = { app = name; };
    inherit namespace;
  })
  (lib.ingressWithCert {
    inherit name;
    inherit namespace;
    host = "monitoring.opendesk.internal";
    inherit port;
    serviceName = name;
  })
]