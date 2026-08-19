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
    description = "kibana service for openDesk";
    serviceType = "web";
    component = "backend";
  };

  name = "kibana";
  tag = "8.13.0";
  namespace = "logging";
  port = 5601;


  # Security configuration
  containerSecurity = security.mkContainerSecurityContext { profile = "monitoring"; };
  podSecurity = security.mkPodSecurityContext { user = 1000; group = 1000; fsGroup = 1000; };

  # Probe configuration
  livenessProbe = lib.mkProbe {
    type = "tcp";
    port = 5601;
    initialDelaySeconds = 30;
    periodSeconds = 10;
    timeoutSeconds = 5;
  };
  readinessProbe = lib.mkProbe {
    type = "tcp";
    port = 5601;
    initialDelaySeconds = 5;
    periodSeconds = 5;
    timeoutSeconds = 3;
  };


in

[
  # Kibana Deployment
  (lib.deployment {
    inherit name;
    image = "docker.elastic.co/kibana/kibana:8.13.0";
    labels = { app = name; };
    selector = { app = name; };
    inherit namespace;
    ports = [ { name = "http"; containerPort = port; } ];
    resources = { 
      limits = { cpu = "1"; memory = "1Gi"; }; 
      requests = { cpu = "500m"; memory = "512Mi"; }; 
    };
  })

  # Kibana Service
  (lib.service {
    inherit name;
    inherit port;
    selector = { app = name; };
    inherit namespace;
  })

  # Kibana Ingress with TLS
  (lib.ingressWithCert {
    inherit name;
    inherit namespace;
    host = "kibana.opendesk.internal";
    inherit port;
    serviceName = name;
  })
]