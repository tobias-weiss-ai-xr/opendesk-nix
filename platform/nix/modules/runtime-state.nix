# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Declarative Runtime State Module
# Based on ~/git/nix-best-practices patterns
#
# Manages runtime state for services declaratively:
# - Keycloak users and realms
# - Grafana dashboards and datasources
# - Prometheus alert rules
# - Kyverno policies

{ config, lib, pkgs, ... }:

let cfg = config.services.runtimeState;
in {
  meta.maintainers = [ "opendesk-edu" ];

  ###### interface

  options = {
    services.runtimeState = {
      enable = lib.mkEnableOption "Declarative runtime state management";

      keycloak = {
        enable = lib.mkEnableOption "Declarative Keycloak configuration";

        realm = lib.mkOption {
          type = lib.types.str;
          default = "opendesk";
          description = "Keycloak realm name";
        };

        users = lib.mkOption {
          type = lib.types.attrs;
          default = { };
          description = "User definitions";
        };

        clients = lib.mkOption {
          type = lib.types.attrs;
          default = { };
          description = "Client definitions";
        };
      };

      grafana = {
        enable = lib.mkEnableOption "Declarative Grafana configuration";

        dashboards = lib.mkOption {
          type = lib.types.attrs;
          default = { };
          description = "Dashboard definitions";
        };

        datasources = lib.mkOption {
          type = lib.types.attrs;
          default = { };
          description = "Datasource definitions";
        };

        alertRules = lib.mkOption {
          type = lib.types.attrs;
          default = { };
          description = "Alert rule definitions";
        };
      };

      prometheus = {
        enable = lib.mkEnableOption "Declarative Prometheus configuration";

        scrapeConfigs = lib.mkOption {
          type = lib.types.attrs;
          default = { };
          description = "Scrape configuration definitions";
        };

        alertRules = lib.mkOption {
          type = lib.types.attrs;
          default = { };
          description = "Alert rule definitions";
        };
      };

      kyverno = {
        enable = lib.mkEnableOption "Declarative Kyverno policy management";

        policies = lib.mkOption {
          type = lib.types.attrs;
          default = { };
          description = "Kyverno policy definitions";
        };
      };

      stateDir = lib.mkOption {
        type = lib.types.path;
        default = /var/lib/opendesk-state;
        description = "Directory for runtime state";
      };

      syncInterval = lib.mkOption {
        type = lib.types.int;
        default = 300; # 5 minutes
        description = "State sync interval (seconds)";
      };
    };
  };

  ###### implementation

  config = lib.mkIf cfg.enable {
    # Create state directory
    environment.etc."opendesk-state".source = cfg.stateDir;

    # Keycloak declarative configuration
    services.keycloak = lib.mkIf cfg.keycloak.enable {
      enable = true;

      httpAddress = "0.0.0.0";
      httpPort = 8080;

      extraConfig = {
        "keycloak.profile.feature.upload_scripts=enabled" = true;
        "keycloak.profile.feature.admin_fine_grained_authz=enabled" = true;
      };
    };

    # Generate Keycloak realm configuration
    environment.etc."keycloak/realm.json".text = lib.generators.toPretty { } {
      realm = cfg.keycloak.realm;
      enabled = true;

      users = lib.mapAttrsToList (name: user: {
        username = name;
        enabled = true;
        emailVerified = user.emailVerified or true;
        email = user.email or "";
        firstName = user.firstName or "";
        lastName = user.lastName or "";
        roles = user.roles or [ ];
        groups = user.groups or [ ];
      }) cfg.keycloak.users;

      clients = lib.mapAttrsToList (name: client: {
        clientId = name;
        enabled = true;
        publicClient = client.public or false;
        redirectUris = client.redirectUris or [ ];
        webOrigins = client.webOrigins or [ "*" ];
      }) cfg.keycloak.clients;
    };

    # Grafana declarative configuration
    services.grafana = lib.mkIf cfg.grafana.enable {
      enable = true;

      settings = {
        server = {
          http_addr = "0.0.0.0";
          http_port = 3000;
        };

        security = {
          admin_user = "admin";
          admin_password_file = "/var/lib/grafana/admin-password";
        };
      };

      provision = {
        enable = true;

        datasources = lib.mapAttrsToList (name: ds: {
          name = name;
          type = ds.type;
          url = ds.url;
          access = "proxy";
          isDefault = ds.default or false;
        }) cfg.grafana.datasources;

        dashboards = lib.mapAttrsToList (name: dashboard: {
          title = dashboard.title or name;
          path = dashboard.path;
        }) cfg.grafana.dashboards;
      };
    };

    # Prometheus declarative configuration
    services.prometheus = lib.mkIf cfg.prometheus.enable {
      enable = true;

      globalConfig = {
        scrape_interval = "15s";
        evaluation_interval = "15s";
      };

      scrapeConfigs = lib.mapAttrsToList (name: sc: {
        job_name = name;
        static_configs = [{ targets = sc.targets or [ ]; }];
        scrape_interval = sc.interval or "15s";
      }) cfg.prometheus.scrapeConfigs;

      alertingConfig = lib.mapAttrsToList (_name: rule: {
        alert = rule.alert;
        expr = rule.expr;
        for = rule.for or "5m";
        labels = rule.labels or { };
        annotations = rule.annotations or { };
      }) cfg.prometheus.alertRules;
    };

    # Kyverno policy management
    services.kyverno = lib.mkIf cfg.kyverno.enable { enable = true; };

    # Generate Kyverno policies
    environment.etc."kyverno/policies".source =
      pkgs.runCommand "kyverno-policies" { buildInputs = [ pkgs.yq ]; } ''
        mkdir -p $out
        ${pkgs.writeScript "generate-policies" ''
          #!/usr/bin/env bash
          set -eu
          for policy in ${toString (lib.attrNames cfg.kyverno.policies)}; do
            yq eval '.' <<< '${
              builtins.toJSON cfg.kyverno.policies.${policy}
            }' > "$out/${policy}.yaml"
          done
        ''}
      '';

    # State sync timer
    systemd.services.opendesk-state-sync = {
      description = "OpenDesk Runtime State Sync";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };

      script = ''
        # Sync Keycloak realm
        if [ -f /etc/keycloak/realm.json ]; then
          curl -s -X POST http://localhost:8080/realms/master/protocol/openid-connect/token \
            -d "grant_type=client_credentials" \
            -d "client_id=admin-cli" \
            -d "client_secret=$(cat /var/lib/keycloak/admin-secret)" \
            -o /tmp/token.json
          
          TOKEN=$(jq -r .access_token /tmp/token.json)
          curl -s -X PUT http://localhost:8080/admin/realms/${cfg.keycloak.realm} \
            -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type: application/json" \
            -d @/etc/keycloak/realm.json
        fi

        # Sync Grafana
        if [ -f /etc/grafana/provisioning ]; then
          systemctl reload grafana-server
        fi

        # Sync Prometheus
        if [ -f /etc/prometheus/prometheus.yml ]; then
          curl -X POST http://localhost:9090/-/reload
        fi

        # Sync Kyverno
        if [ -f /etc/kyverno/policies ]; then
          kubectl apply -f /etc/kyverno/policies
        fi
      '';
    };

    systemd.timers.opendesk-state-sync = {
      description = "OpenDesk State Sync Timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "${toString cfg.syncInterval}s";
      };
    };
  };
}
