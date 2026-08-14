# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Remote Builders Module - distributed Nix builds across the SCS cluster
#
# Declarative replacement for deploy/remote-builders/setup-builders.sh.
# Two sides:
#
# 1. On build CLIENT machines (dev machines, CI runners):
#      opendesk.remoteBuilders.enable = true;   # client side
#      opendesk.remoteBuilders.machines = [
#        { hostName = "builder-1.internal"; system = "x86_64-linux"; maxJobs = 4; }
#      ];
#
# 2. On BUILDER nodes (cluster nodes):
#      opendesk.remoteBuilders.builder.enable = true;
#
# Best practice from ~/git/nix-best-practices/examples/remote-builder.nix:
# remote builders + local binary cache means the air-gapped cluster nodes
# build store paths, dev machines consume them via the cache.

{ config, lib, ... }:

let
  cfg = config.opendesk.remoteBuilders;
in
{
  meta.maintainers = [ "opendesk-edu" ];

  options.opendesk.remoteBuilders = {
    enable = lib.mkEnableOption "Use remote Nix build machines";

    machines = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            hostName = lib.mkOption {
              type = lib.types.str;
              description = "Builder hostname (SSH-accessible).";
            };
            system = lib.mkOption {
              type = lib.types.str;
              default = "x86_64-linux";
              description = "Target system the builder builds for.";
            };
            maxJobs = lib.mkOption {
              type = lib.types.int;
              default = 4;
              description = "Maximum parallel jobs on the builder.";
            };
            speedFactor = lib.mkOption {
              type = lib.types.int;
              default = 1;
              description = "Relative speed of the builder (affects scheduling).";
            };
            supportedFeatures = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [
                "benchmark"
                "big-parallel"
              ];
              description = "Features the builder supports.";
            };
            mandatoryFeatures = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Features the builder must have.";
            };
            sshUser = lib.mkOption {
              type = lib.types.str;
              default = "nix-builder";
              description = "SSH user on the builder.";
            };
            sshKey = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = "SSH private key path for connecting to builders.";
            };
          };
        }
      );
      default = [ ];
      description = "Remote build machines.";
    };

    builder = {
      enable = lib.mkEnableOption "Serve as a remote Nix builder";

      maxJobs = lib.mkOption {
        type = lib.types.int;
        default = 4;
        description = "Maximum parallel build jobs on this builder.";
      };

      supportedFeatures = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "benchmark"
          "big-parallel"
        ];
        description = "Features this builder provides.";
      };

      nixUser = lib.mkOption {
        type = lib.types.str;
        default = "nix-builder";
        description = "System user used for remote builds.";
      };

      sshKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "SSH public keys authorized to connect as the builder user.";
      };
    };
  };

  config = lib.mkMerge [
    # ============ Client side: use remote builders ============
    (lib.mkIf cfg.enable {
      nix.buildMachines = map (m: {
        inherit (m)
          hostName
          system
          maxJobs
          speedFactor
          supportedFeatures
          mandatoryFeatures
          ;
        sshUser = m.sshUser;
        sshKey = if m.sshKey != null then toString m.sshKey else null;
      }) cfg.machines;

      nix.settings = {
        builders-use-substitutes = true;
        max-jobs = lib.mkDefault 0; # Don't build locally if remote builders exist
      };
    })

    # ============ Builder side: serve remote builds ============
    (lib.mkIf cfg.builder.enable {
      nix.settings.max-jobs = cfg.builder.maxJobs;
      nix.settings.sandbox = true;

      # Dedicated builder user
      users.users.${cfg.builder.nixUser} = {
        isSystemUser = true;
        createHome = true;
        home = "/home/${cfg.builder.nixUser}";
        group = "nixbld";
        openssh.authorizedKeys.keys = cfg.builder.sshKeys;
      };

      users.groups.nixbld = { };

      # Builder user must be trusted by Nix
      nix.settings.trusted-users = [ cfg.builder.nixUser ];
      nix.settings.allowed-users = [ cfg.builder.nixUser ];

      # SSH server for remote builders
      services.openssh.enable = true;
      services.openssh.settings.PasswordAuthentication = false;
    })
  ];
}
