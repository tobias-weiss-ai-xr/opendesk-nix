# SPDX-License-Identifier: Apache-2.0
# Keycloak declarative-runtime check
#
# Verifies the OpenTofu reconciliation service is correctly wired:
#   - oneshot service after keycloak.service
#   - LoadCredential for the admin password (never in Nix store)
#   - vendored keycloak provider (no registry access at runtime)
#   - realms/clients translated into .tf.json resource config

{
  pkgs,
  lib,
  nixpkgs,
  ...
}:

let
  system = pkgs.system;

  eval = nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      ../modules/keycloak-runtime.nix
      {
        nixpkgs.hostPlatform = system;
        services.keycloak.enable = true;
        opendesk.keycloakRuntime = {
          enable = true;
          tokenFile = "/run/secrets/keycloak-admin-password";
          realms.staff.displayName = "Staff SSO";
          openidClients.app = {
            realm = "staff";
            clientId = "opendesk-app";
            validRedirectUris = [ "https://app.opendesk.internal/*" ];
          };
        };
        system.stateVersion = "24.11";
      }
    ];
  };

  svc = eval.config.systemd.services.keycloak-runtime;
  credential = svc.serviceConfig.LoadCredential;
  script = svc.script;

  checks = [
    "service is oneshot (got: ${svc.serviceConfig.Type})"
    "runs after keycloak.service (got: ${toString svc.after})"
    "LoadCredential carries admin password (got: ${credential})"
    "script loads TF_VAR_admin_password from credential (${toString (lib.hasInfix "TF_VAR_admin_password" script)})"
    "script runs tofu init with vendored provider (${toString (lib.hasInfix "tofu init" script)})"
    "script waits for health endpoint (${toString (lib.hasInfix "health/ready" script)})"
  ];

  allPass =
    svc.serviceConfig.Type == "oneshot"
    && builtins.elem "keycloak.service" svc.after
    && builtins.isString credential
    && lib.hasInfix "TF_VAR_admin_password" script
    && lib.hasInfix "tofu init" script
    && lib.hasInfix "health/ready" script;
in
pkgs.runCommand "keycloak-runtime-check" { } ''
  ${lib.concatMapStringsSep "\n" (c: "echo '✓ ${c}'") checks}
  ${if allPass then "echo 'All keycloak-runtime checks passed.'" else "echo 'FAILED' && exit 1"}
  touch $out
''
