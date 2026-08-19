# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
# SPDX-License-Identifier: Apache-2.0

{ lib, pkgs, docks, ... }:

let
  inherit (lib)
    mkOption
    types
    mkDefault
    genAttrs
    mapAttrs
    ;

in
{
  options.services.argunix = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable argunix Nix-native CI";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage (builtins.fetchGit {
        url = "https://codeberg.org/tfc/argunix";
        ref = "refs/tags/v0.0.1-dev";
        sha256 = "0000000000000000000000000000000000000000000000000000";
      }) {};
      description = "argunix package";
    };

    version = mkOption {
      type = types.str;
      default = "0.0.1-dev";
      description = "argunix version";
    };

    externalUrl = mkOption {
      type = types.str;
      default = "https://ci.opendesk.example.com";
      description = "External URL for argunix web interface";
    };

    listen = mkOption {
      type = types.str;
      default = "0.0.0.0:8080";
      description = "Listen address and port";
    };

    database = {
      type = mkOption {
        type = types.enum [ "sqlite" "postgresql" ];
        default = "sqlite";
        description = "Database type";
      };

      path = mkOption {
        type = types.path;
        default = "/var/lib/argunix/argunix.sqlite";
        description = "SQLite database path";
      };
    };

    nats = {
      url = mkOption {
        type = types.str;
        default = "nats://localhost:4222";
        description = "NATS server URL";
      };
    };

    builderEnrollment = {
      enabled = mkOption {
        type = types.bool;
        default = true;
        description = "Enable builder enrollment";
      };

      listen = mkOption {
        type = types.str;
        default = "0.0.0.0:45678";
        description = "Builder enrollment listen address";
      };

      token = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Builder enrollment token";
      };
    };

    forges = mkOption {
      type = types.attrsOf (types.submodule { options = {
        kind = mkOption {
          type = types.enum [ "github" "gitlab" "forgejo" "gitea" "codeberg" ];
          description = "Forge kind";
        };
        web_url = mkOption {
          type = types.str;
          description = "Forge web URL";
        };
        token_path = mkOption {
          type = types.path;
          description = "Path to token file";
        };
        repos = mkOption {
          type = types.attrsOf (types.attrsOf types.any);
          default = {};
          description = "Repository configurations";
        };
      }; });
      default = {};
      description = "Forge configurations";
    };

    binaryCaches = mkOption {
      type = types.listOf (types.submodule { options = {
        push_url = mkOption {
          type = types.str;
          description = "Push URL for binary cache";
        };
        public_url = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Public URL for binary cache";
        };
        signing_key_path = mkOption {
          type = types.path;
          description = "Path to signing key";
        };
        public_key = mkOption {
          type = types.str;
          description = "Public key for cache";
        };
      }; });
      default = [];
      description = "Binary cache configurations";
    };

    nix = {
      store = mkOption {
        type = types.path;
        default = "/nix";
        description = "Nix store path";
      };

      conf_dir = mkOption {
        type = types.path;
        default = "/etc/nix";
        description = "Nix configuration directory";
      };

      daemon_socket = mkOption {
        type = types.path;
        default = "/nix/var/nix/daemon-socket/socket";
        description = "Nix daemon socket path";
      };

      trusted_users = mkOption {
        type = types.listOf types.str;
        default = [ "root" "argunix" "argunix-builder" ];
        description = "Trusted users for Nix";
      };
    };
  };
} // {
  config = lib.mkIf (lib.mkDefault true) {
    services.argunix = {
    };
  };
}
