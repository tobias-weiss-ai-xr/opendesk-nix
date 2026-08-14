# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Remote Builders Module
# Based on ~/git/nix-best-practices patterns
#
# Enables distributed builds across SCS cluster nodes
#
# Features:
# - Multiple remote builder configurations
# - SSH key-based authentication
# - Build parallelization
# - Automatic node health checking

{ config, lib, ... }:

let
  cfg = config.nix.remoteBuilders;
in
{
  meta.maintainers = [ "opendesk-edu" ];

  ###### interface

  options = {
    nix.remoteBuilders = {
      enable = lib.mkEnableOption "Remote builders for distributed builds";

      nodes = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              name = lib.mkOption {
                type = lib.types.str;
                description = "Builder node name";
              };

              endpoint = lib.mkOption {
                type = lib.types.str;
                description = "SSH endpoint (user@host)";
              };

              sshKey = lib.mkOption {
                type = lib.types.path;
                description = "Path to SSH private key";
              };

              system = lib.mkOption {
                type = lib.types.enum [
                  "x86_64-linux"
                  "aarch64-linux"
                ];
                default = "x86_64-linux";
                description = "Target system type";
              };

              maxJobs = lib.mkOption {
                type = lib.types.int;
                default = 4;
                description = "Maximum parallel jobs on this node";
              };

              speedFactor = lib.mkOption {
                type = lib.types.int;
                default = 1;
                description = "Relative build speed (higher = faster)";
              };

              supportedFeatures = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [
                  "kvm"
                  "bigparallel"
                ];
                description = "Special build features";
              };
            };
          }
        );
        default = [ ];
        description = "List of remote builder nodes";
      };

      buildTimeout = lib.mkOption {
        type = lib.types.int;
        default = 3600; # 1 hour
        description = "Maximum build time per derivation (seconds)";
      };

      connectTimeout = lib.mkOption {
        type = lib.types.int;
        default = 30;
        description = "SSH connection timeout (seconds)";
      };
    };
  };

  ###### implementation

  config = lib.mkIf cfg.enable {
    # Configure Nix to use remote builders
    nix.settings = {
      builders =
        lib.mapAttrsToList
          (
            _name: value:
            "${value.endpoint} ${value.system} ${toString value.speedFactor} ${toString value.maxJobs} ${lib.concatStringsSep "," value.supportedFeatures}"
          )
          (
            lib.listToAttrs (
              lib.mapIndexed (i: node: {
                name = "builder-${toString i}";
                value = node;
              }) cfg.nodes
            )
          );

      builders-use-substitutes = true;
      connect-timeout = cfg.connectTimeout;
      build-timeout = cfg.buildTimeout;
    };

    # SSH configuration for builder nodes
    environment.etc."ssh/ssh_config".text = ''
      Host nix-builder-*
          IdentityFile /etc/nix/builders/ssh-key
          IdentitiesOnly yes
          StrictHostKeyChecking accept-new
          ServerAliveInterval 60
          ServerAliveCountMax 3
          ConnectTimeout ${toString cfg.connectTimeout}
    '';

    # Create builders directory
    environment.etc."nix/builders".mode = "0755";

    # systemd service for health monitoring
    systemd.services.nix-builder-health = {
      description = "Nix Remote Builder Health Check";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };

      script = ''
        for node in $(nix show-config | grep -o 'nix-builder-[0-9]*'); do
          if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$node" "exit 0"; then
            echo "Warning: Builder $node is unreachable" >&2
          fi
        done
      '';
    };

    systemd.timers.nix-builder-health = {
      description = "Nix Builder Health Check Timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "15min";
      };
    };
  };
}
