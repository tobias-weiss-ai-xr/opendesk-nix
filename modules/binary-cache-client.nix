# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Binary cache client configuration module
# Based on specs/technical/BINARY-CACHE-SPEC.md
#
# Configures Nix to use Attic or other binary caches as substituters

{ config, lib, pkgs, ... }:

let
  cfg = config.nix.binaryCache;
in {
  meta.maintainers = [ "opendesk-edu" ];

  ###### interface

  options = {
    nix.binaryCache = {
      enable = lib.mkEnableOption "Use binary cache for Nix builds";

      url = lib.mkOption {
        type = lib.types.str;
        default = "https://cache.nixos.org";
        description = "Binary cache URL";
      };

      publicKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "List of binary cache public keys";
      };

      priority = lib.mkOption {
        type = lib.types.int;
        default = 40;
        description = "Priority (lower = higher priority)";
      };

      trusted = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Mark as trusted substituter";
      };
    };
  };

  ###### implementation

  config = lib.mkIf cfg.enable {
    nix.settings = {
      substituters = lib.mkOrder cfg.priority [ cfg.url ];
      
      trusted-public-keys = lib.mkIf (cfg.publicKeys != [ ])
        cfg.publicKeys;
      
      # Prefer binary cache over building
      builders-use-substitutes = true;
      
      # Retry substituters on failure
      connect-timeout = 10;
      max-jobs = lib.mkDefault (builtins.length config.nix.builders);
    };
  };
}
