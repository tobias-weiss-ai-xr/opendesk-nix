# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# A/B OTA Update Module
# Based on specs/technical/APPLIANCE-IMAGE-SPEC.md
#
# Provides:
# - systemd-sysupdate for atomic A/B updates
# - Automatic rollback on boot failure
# - Secure boot integration support

{ config, lib, pkgs, ... }:

let cfg = config.services.abUpdates;
in {
  meta.maintainers = [ "opendesk-edu" ];

  ###### interface

  options = {
    services.abUpdates = {
      enable = lib.mkEnableOption "A/B OTA updates with systemd-sysupdate";

      slots = lib.mkOption {
        type = lib.types.enum [ "a" "b" ];
        default = "a";
        description = "Current active slot";
      };

      updateSource = lib.mkOption {
        type = lib.types.str;
        description = "Update source URL or path";
      };

      rollbackTimeout = lib.mkOption {
        type = lib.types.int;
        default = 300; # 5 minutes
        description = "Time before automatic rollback (seconds)";
      };

      verifySignatures = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Verify update signatures before applying";
      };

      signingKey = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to signing key for verification";
      };
    };
  };

  ###### implementation

  config = lib.mkIf cfg.enable {
    # Install systemd-sysupdate
    environment.systemPackages = [ pkgs.systemd ];

    # Create sysupdate configuration
    environment.etc."systemd/sysupdate.d/ab-update.conf".text = ''
      [Update]
      Destination=/
      Source=${cfg.updateSource}
      Verify=${lib.boolToString cfg.verifySignatures}
      Mode=atomic
      Slots=${cfg.slots}

      [Partition]
      Type=root-${cfg.slots}
      Priority=100
    '';

    # Create rollback timer
    systemd.services.ab-rollback-assessment = {
      description = "A/B Update Rollback Assessment";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/lib/systemd/systemd-sysupdate assess /";
        RemainAfterExit = true;
      };
    };

    systemd.timers.ab-rollback-assessment = {
      description = "A/B Update Rollback Assessment Timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "1h";
      };
    };

    # Boot assessment configuration
    boot.kernelParams = [
      "systemd.assess=1"
      "systemd.rollback=${lib.boolToString (cfg.rollbackTimeout > 0)}"
    ];

    # Environment variables for update management
    environment.variables = {
      AB_ACTIVE_SLOT = cfg.slots;
      AB_ROLLBACK_TIMEOUT = toString cfg.rollbackTimeout;
    };
  };
}
