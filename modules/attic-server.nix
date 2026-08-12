# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Attic binary cache server module
# Based on specs/technical/BINARY-CACHE-SPEC.md
#
# See: ~/git/nix-best-practices/docs/05-binary-cache.md

{ config, lib, pkgs, ... }:

let
  cfg = config.services.attic-server;
in {
  meta.maintainers = [ "opendesk-edu" ];

  ###### interface

  options = {
    services.attic-server = {
      enable = lib.mkEnableOption "Attic binary cache server";

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.attic;
        description = "Attic package to use";
      };

      listenAddress = lib.mkOption {
        type = lib.types.str;
        default = "0.0.0.0";
        description = "Address to listen on";
      };

      listenPort = lib.mkOption {
        type = lib.types.port;
        default = 8080;
        description = "Port to listen on";
      };

      cacheDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/attic";
        description = "Local cache directory";
      };

      maxCacheSize = lib.mkOption {
        type = lib.types.size;
        default = 500 * 1024 * 1024 * 1024; # 500GB
        description = "Maximum cache size in bytes";
      };

      signingKey = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Ed25519 signing key path (generated if null)";
      };

      storageBackend = lib.mkOption {
        type = lib.types.enum ["local" "s3" "ceph"];
        default = "local";
        description = "Storage backend type";
      };

      s3Endpoint = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "S3/CEPH RGW endpoint URL";
      };

      s3Bucket = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "S3 bucket name";
      };

      s3AccessKeyId = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "S3 access key ID";
      };

      s3SecretKey = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "S3 secret access key";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Open firewall port for Attic server";
      };

      firewallPort = lib.mkOption {
        type = lib.types.port;
        default = 8080;
        description = "Firewall port to open";
      };

      enableMetrics = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Prometheus metrics endpoint";
      };

      metricsPort = lib.mkOption {
        type = lib.types.port;
        default = 9090;
        description = "Metrics endpoint port";
      };
    };
  };

  ###### implementation

  config = lib.mkIf cfg.enable {
    # Create attic user and group
    users.users.attic = {
      isSystemUser = true;
      group = "attic";
      home = cfg.cacheDir;
    };

    users.groups.attic = {};

    # Create cache directory
    systemd.tmpfiles.rules = [
      "d ${cfg.cacheDir} 0755 attic attic -"
      "d ${cfg.cacheDir}/cache 0755 attic attic -"
      "d ${cfg.cacheDir}/keys 0700 attic attic -"
    ];

    # Generate signing key if not provided
    environment.etc."attic/signing.key".source =
      lib.mkIf (cfg.signingKey == null)
        (pkgs.runCommand "attic-signing-key" {
          buildInputs = [ pkgs.attic ];
        } ''
          mkdir -p $out
          ATTIC_KEY_FILE=$out/signing.key ${pkgs.attic}/bin/attic key generate
          chmod 600 $out/signing.key
        '');

    # Attic server systemd service
    systemd.services.attic-server = {
      description = "Attic Binary Cache Server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = "attic";
        Group = "attic";
        Restart = "always";
        RestartSec = 10;

        ExecStart = ''
          ${cfg.package}/bin/attic server \
            --listen ${cfg.listenAddress}:${toString cfg.listenPort} \
            --cache-dir ${cfg.cacheDir} \
            ${lib.optionalString (cfg.storageBackend == "s3" || cfg.storageBackend == "ceph") ''
              --storage s3 \
              --s3-endpoint ${cfg.s3Endpoint} \
              --s3-bucket ${cfg.s3Bucket} \
              --s3-access-key-id ${cfg.s3AccessKeyId} \
              --s3-secret-key ${cfg.s3SecretKey}
            ''}
        '';

        # Security hardening
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        MemoryDenyWriteExecute = true;
      };
    };

    # Open firewall if requested
    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.firewallPort ];
    };

    # Prometheus metrics endpoint
    services.prometheus.exporters.custom = lib.mkIf cfg.enableMetrics {
      enable = true;
      name = "attic-metrics";
      port = cfg.metricsPort;
      script = "${cfg.package}/bin/attic metrics";
    };

    # Nix configuration for server
    nix.settings = {
      trusted-users = [ "root" "attic" ];
      # Allow Attic to upload builds
      builders-use-substitutes = true;
    };

    # Logging
    systemd.services.attic-server.serviceConfig.LogTarget = "journal";
    systemd.services.attic-server.serviceConfig.StandardOutput = "journal";
    systemd.services.attic-server.serviceConfig.StandardError = "journal";
  };
}
