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
    description = "memcached service for openDesk";
    serviceType = "web";
    component = "backend";
  };
 name = "memcached"; image = "ghcr.io/opendesk-edu/memcached"; tag = "latest";

  # Security configuration
  containerSecurity = security.mkContainerSecurityContext { profile = "cache"; };
  podSecurity = security.mkPodSecurityContext { user = 1000; group = 1000; fsGroup = 1000; };

  # Probe configuration
  livenessProbe = lib.mkProbe {
    type = "tcp";
    port = 11211;
    initialDelaySeconds = 30;
    periodSeconds = 10;
    timeoutSeconds = 5;
  };
  readinessProbe = lib.mkProbe {
    type = "tcp";
    port = 11211;
    initialDelaySeconds = 5;
    periodSeconds = 5;
    timeoutSeconds = 3;
  };

  # Resource configuration
  resources = {
    requests = { cpu = "100m"; memory = "256Mi"; };
    limits = { cpu = "500m"; memory = "512Mi"; };
  };


in
 [ (lib.deployment { inherit name image tag; port = 11211; }) (lib.service { inherit name; port = 11211; }) ]