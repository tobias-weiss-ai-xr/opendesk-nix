# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# NixOS K3s Node Configuration
# Based on specs/technical/APPLIANCE-IMAGE-SPEC.md
#
# Complete NixOS configuration for K3s cluster nodes with:
# - K3s Kubernetes (uses nixpkgs' services.k3s module)
# - Ceph CSI storage
# - HAProxy ingress (uses nixpkgs' services.haproxy module)
# - Binary cache support
#
# Custom options are namespaced under `opendesk.k3s-node.*` to avoid
# conflicting with nixpkgs' own services.k3s/services.haproxy modules.

{
  config,
  lib,
  ...
}:

let
  cfg = config.opendesk.k3s-node;
in
{
  meta.maintainers = [ "opendesk-edu" ];

  # Import binary cache client
  imports = [ ./../modules/binary-cache-client.nix ];

  ###### interface

  options.opendesk.k3s-node = {
    enable = lib.mkEnableOption "openDesk K3s node";

    role = lib.mkOption {
      type = lib.types.enum [
        "server"
        "agent"
      ];
      default = "server";
      description = "K3s node role (server or agent).";
    };

    clusterTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a file containing the cluster join token.
        Prefer this over an inline token: nixpkgs warns that an inline
        token is exposed unencrypted in the world-readable Nix store.
      '';
    };

    extraOptions = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        "disable" = "traefik";
      };
      description = "Additional K3s command-line options (mapped to --name=value).";
    };

    cephCsi = {
      enable = lib.mkEnableOption "Ceph CSI node configuration";

      monEndpoints = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Ceph monitor endpoints (host:port list).";
      };
    };

    haproxyIngress = {
      enable = lib.mkEnableOption "HAProxy ingress listeners";

      config = lib.mkOption {
        type = lib.types.lines;
        default = ''
          global
            log stdout format raw local0
            maxconn 4096

          defaults
            log global
            mode http
            option httplog
            option dontlognull
            timeout connect 5000
            timeout client  50000
            timeout server  50000

          frontend http
            bind *:80
            default_backend k3s_http

          frontend https
            bind *:443 ssl crt /etc/ssl/opendesk/ingress.pem
            http-request set-header X-Forwarded-Proto https
            default_backend k3s_https

          backend k3s_http
            server k3s-traefik 127.0.0.1:8080 check

          backend k3s_https
            server k3s-tls 127.0.0.1:8443 check
        '';
        description = "HAProxy configuration text (see nixpkgs services.haproxy.config).";
      };
    };
  };

  ###### implementation

  config = lib.mkIf cfg.enable {
    # K3s configuration (nixpkgs' services.k3s module)
    services.k3s =
      {
        enable = true;
        inherit (cfg) role;
        extraFlags = lib.mapAttrsToList (name: value: "--${name}=${value}") cfg.extraOptions;
      }
      // lib.optionalAttrs (cfg.clusterTokenFile != null) {
        inherit (cfg) clusterTokenFile;
      };

    # Ceph CSI: write /etc/ceph/ceph.conf so CSI pods on this node can reach monitors
    environment.etc."ceph/ceph.conf" = lib.mkIf cfg.cephCsi.enable {
      text = lib.concatStringsSep "\n" ([
        "[global]"
        "mon_host = ${lib.concatStringsSep "," cfg.cephCsi.monEndpoints}"
      ]);
    };

    # HAProxy ingress configuration (nixpkgs' services.haproxy module)
    services.haproxy = lib.mkIf cfg.haproxyIngress.enable {
      enable = true;
      config = cfg.haproxyIngress.config;
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
      trusted-users = [
        "root"
        "k3s"
      ];
      builders-use-substitutes = true;
    };
  };
}
