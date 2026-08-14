# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Keycloak Declarative Runtime State Module
# Based on ~/git/nix-best-practices/examples/declarative-runtime.nix
# and docs/20-runtime-state.md
#
# Manages Keycloak runtime state (realms, openid clients, roles) that
# NixOS modules cannot express, using OpenTofu reconciliation.
#
# Key decisions (from applicative-systems research):
#   - OpenTofu (MPL 2.0), not Terraform (BSL 1.1)
#   - .tf.json generated via builtins.toJSON (no HCL, no terranix)
#   - Vendored provider via pkgs.opentofu.withPlugins (no registry access
#     at runtime - critical for air-gapped SCS)
#   - systemd LoadCredential= for the admin token (never in Nix store)
#   - Run-once Type=oneshot with restartTriggers (no drift timer)
#   - Local tfstate (no remote backends)
#
# Usage:
#   imports = [ inputs.opendesk-nix.nixosModules.keycloak-runtime ];
#   opendesk.keycloakRuntime = {
#     enable = true;
#     baseUrl = "http://localhost:8080";
#     adminUser = "admin";
#     tokenFile = config.age.secrets.keycloak-admin-token.path;
#     realms.staff = { displayName = "Staff SSO"; enabled = true; };
#     openidClients.app = {
#       realm = "staff";
#       clientId = "opendesk-app";
#       validRedirectUris = [ "https://app.opendesk.internal/*" ];
#       webOrigins = [ "https://app.opendesk.internal" ];
#     };
#   };

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.opendesk.keycloakRuntime;

  # OpenTofu with the Keycloak provider vendored (air-gap friendly)
  tofu = pkgs.opentofu.withPlugins (_: [
    pkgs.terraform-providers.keycloak
  ]);

  # Generate the .tf.json file from Nix options
  tfConfigFile = pkgs.writeText "keycloak-runtime.tf.json" (
    builtins.toJSON {
      terraform = {
        required_providers.keycloak = {
          source = "mrparkers/keycloak";
        };
        backend.local.path = "terraform.tfstate";
      };

      provider.keycloak = {
        client_id = "admin-cli";
        url = cfg.baseUrl;
        username = cfg.adminUser;
        password = "\${var.admin_password}";
      };

      variable.admin_password = {
        type = "string";
        description = "Keycloak admin password (from systemd credential)";
      };

      resource = {
        keycloak_realm = lib.mapAttrs' (name: realm: {
          name = name;
          value = {
            realm = name;
            display_name = realm.displayName or name;
            enabled = realm.enabled or true;
          };
        }) cfg.realms;

        keycloak_openid_client = lib.mapAttrs' (name: client: {
          name = name;
          value = {
            realm_id = client.realm;
            client_id = client.clientId;
            enabled = client.enabled or true;
            access_type = client.accessType or "CONFIDENTIAL";
            valid_redirect_uris = client.validRedirectUris or [ ];
            web_origins = client.webOrigins or [ ];
            standard_flow_enabled = client.standardFlowEnabled or true;
            direct_access_grants_enabled = client.directAccessGrantsEnabled or false;
          };
        }) cfg.openidClients;
      };
    }
  );
in
{
  meta.maintainers = [ "opendesk-edu" ];

  options.opendesk.keycloakRuntime = {
    enable = lib.mkEnableOption "Declarative Keycloak runtime state (OpenTofu)";

    baseUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:8080";
      description = "Keycloak base URL (internal).";
    };

    healthUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:8080/health/ready";
      description = "Health endpoint used to wait for Keycloak readiness.";
    };

    adminUser = lib.mkOption {
      type = lib.types.str;
      default = "admin";
      description = "Keycloak admin username.";
    };

    tokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a file containing the admin password (loaded via systemd LoadCredential, never in the Nix store).";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/keycloak-runtime";
      description = "Directory for tfstate.";
    };

    realms = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            displayName = lib.mkOption {
              type = lib.types.str;
              default = "";
            };
            enabled = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
          };
        }
      );
      default = { };
      description = "Keycloak realms to reconcile.";
    };

    openidClients = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            realm = lib.mkOption { type = lib.types.str; };
            clientId = lib.mkOption { type = lib.types.str; };
            enabled = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
            accessType = lib.mkOption {
              type = lib.types.enum [
                "CONFIDENTIAL"
                "PUBLIC"
                "BEARER-ONLY"
              ];
              default = "CONFIDENTIAL";
            };
            validRedirectUris = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
            webOrigins = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
            standardFlowEnabled = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
            directAccessGrantsEnabled = lib.mkOption {
              type = lib.types.bool;
              default = false;
            };
          };
        }
      );
      default = { };
      description = "Keycloak OpenID clients to reconcile.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.tokenFile != null;
        message = "opendesk.keycloakRuntime.tokenFile must be set (path to admin password file).";
      }
    ];

    # Re-apply when the config changes
    systemd.services.keycloak-runtime = {
      description = "Declarative Keycloak runtime state reconciliation (OpenTofu)";
      after = [ "keycloak.service" ];
      requires = [ "keycloak.service" ];
      wantedBy = [ "multi-user.target" ];

      restartTriggers = [ tfConfigFile ];

      path = [
        tofu
        pkgs.curl
        pkgs.coreutils
      ];

      environment = {
        TF_IN_AUTOMATION = "1";
        TF_INPUT = "0";
      };

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "keycloak";
        Group = "keycloak";
        LoadCredential = "admin_password:${cfg.tokenFile}";
      };

      script = ''
        set -euo pipefail
        umask 077

        mkdir -p ${cfg.stateDir}
        cd ${cfg.stateDir}

        # Install the .tf.json config
        install -m 0600 ${tfConfigFile} ./main.tf.json

        # Wait for Keycloak to be healthy
        for _ in $(seq 1 90); do
          if curl -fsS -o /dev/null "${cfg.healthUrl}" 2>/dev/null; then
            break
          fi
          sleep 2
        done

        # Load the admin password from the systemd credential (never in Nix store)
        export TF_VAR_admin_password="$(cat "$CREDENTIALS_DIRECTORY/admin_password")"

        # Initialize (vendored provider, no registry access needed)
        ${tofu}/bin/tofu init -no-color

        # Apply the configuration
        ${tofu}/bin/tofu apply -auto-approve -input=false -no-color
      '';
    };
  };
}
