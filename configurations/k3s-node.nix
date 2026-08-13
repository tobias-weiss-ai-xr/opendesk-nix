# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# NixOS K3s Node Configuration
# Based on specs/technical/APPLIANCE-IMAGE-SPEC.md
#
# Complete NixOS configuration for K3s cluster nodes with:
# - K3s Kubernetes
# - Ceph CSI storage
# - HAProxy ingress
# - Binary cache support

{ config, lib, ... }:

let cfg = config.services.k3s;
in {
  meta.maintainers = [ "opendesk-edu" ];

  ###### interface

  options = {
    services.k3s = {
      enable = lib.mkEnableOption "K3s Kubernetes";

      role = lib.mkOption {
        type = lib.types.enum [ "server" "agent" ];
        default = "server";
        description = "K3s node role";
      };

      clusterToken = lib.mkOption {
        type = lib.types.str;
        description = "Cluster join token";
      };

      extraOptions = lib.mkOption {
        type = lib.types.attrs;
        default = { };
        description = "Additional K3s command-line options";
      };
    };

    services.ceph = {
      enable = lib.mkEnableOption "Ceph CSI";

      monEndpoints = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "Ceph monitor endpoints";
      };
    };

    services.haproxy = {
      enable = lib.mkEnableOption "HAProxy ingress";

      listeners = lib.mkOption {
        type = lib.types.attrs;
        description = "HAProxy listener configurations";
      };
    };
  };

  ###### implementation

  config = lib.mkIf cfg.enable {
    # Import binary cache client
    imports = [ ./../modules/binary-cache-client.nix ];

    # K3s configuration
    services.k3s = {
      enable = true;
      role = cfg.role;
      clusterToken = cfg.clusterToken;
      extraFlags =
        lib.mapAttrsToList (name: value: "--${name}=${value}") cfg.extraOptions;
    };

    # Ceph CSI configuration
    services.ceph = lib.mkIf cfg.ceph.enable {
      enable = true;
      monEndpoints = cfg.ceph.monEndpoints;
    };

    # HAProxy ingress configuration
    services.haproxy = lib.mkIf cfg.haproxy.enable {
      enable = true;
      listenAddresses = [
        {
          addr = "0.0.0.0";
          port = 80;
        }
        {
          addr = "0.0.0.0";
          port = 443;
        }
      ];
    };

    # Network configuration
    networking.firewall = {
      enable = true;
      allowedTCPPorts = [
        6443 # K3s API server
        80 # HTTP
        443 # HTTPS
        10250 # Kubelet
      ];
      allowedUDPPorts = [
        8472 # Flannel
        10267 # K3s egress selector
      ];
    };

    # Security hardening
    boot.kernelParams = [
      "ipv6.disable=1"
      "net.ipv4.ip_forward=1"
      "net.ipv4.conf.all.forwarding=1"
    ];

    # Nix configuration
    nix.settings = {
      trusted-users = [ "root" "k3s" ];
      builders-use-substitutes = true;
    };
  };
}
