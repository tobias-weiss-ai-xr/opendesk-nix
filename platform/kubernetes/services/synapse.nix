# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Matrix Synapse — Matrix homeserver
# Uses shared Galera cluster for database (instead of embedded SQLite)
# Image: docker.io/matrixdotorg/synapse:latest

{
  lib,
  env ? import ../environments/scs/default.nix { inherit lib; },
  ...
}:

let
  name = "synapse";
  image = "docker.io/matrixdotorg/synapse";
  tag = "v1.158.0";
  port = 8008;

  labels = lib.mkLabels { inherit name; } // {
    "app.kubernetes.io/component" = "messaging";
    "app.kubernetes.io/managed-by" = "nix";
  };

  db = env.database;

  resources = {
    requests = {
      cpu = "250m";
      memory = "512Mi";
    };
    limits = {
      cpu = "1";
      memory = "2Gi";
    };
  };

  securityContext = {
    allowPrivilegeEscalation = false;
    runAsNonRoot = true;
    runAsUser = 991;
    runAsGroup = 991;
    readOnlyRootFilesystem = false;
    capabilities = {
      drop = [ "ALL" ];
    };
    seccompProfile = {
      type = "RuntimeDefault";
    };
  };

  podSecurityContext = {
    runAsNonRoot = true;
    runAsUser = 991;
    fsGroup = 991;
    fsGroupChangePolicy = "OnRootMismatch";
  };

  livenessProbe = lib.mkProbe {
    type = "http";
    inherit port;
    path = "/health";
    initialDelaySeconds = 60;
    periodSeconds = 15;
    failureThreshold = 5;
  };

  readinessProbe = lib.mkProbe {
    type = "http";
    inherit port;
    path = "/health";
    initialDelaySeconds = 15;
    periodSeconds = 5;
    failureThreshold = 3;
  };

  # Synapse homeserver.yaml configuration
  homeserverConfig = ''
    server_name: "${env.hosts.matrix}"
    pid_file: /data/homeserver.pid
    listeners:
      - port: 8008
        tls: false
        type: http
        x_forwarded: true
        bind_addresses: ['0.0.0.0']
        resources:
          - names: [client, federation]
            compress: false
    database:
      name: sqlite3
      args:
        database: /data/homeserver.db
    macaroon_secret_key: "__SYNAPSE_MACAROON_SECRET__"
    # OIDC SSO via Keycloak realm `opendesk` (client opendesk-matrix, created
    # by the keycloak-bootstrap Job). The client secret is rendered at startup
    # by the init-config initContainer from the sealed synapse-oidc Secret.
    oidc_config:
      enable: true
      discovery_method: "oidc"
      issuer: "https://${env.hosts.keycloak}/realms/${env.keycloak.realm}"
      client_id: "opendesk-matrix"
      client_secret: "__SYNAPSE_OIDC_CLIENT_SECRET__"
      scopes: ["openid", "profile", "email"]
      user_mapping_provider:
        config:
          localpart_template: "{{ user.preferred_username }}"
          display_name_template: "{{ user.preferred_username }}"
    log_config: "/data/log.config"
    media_store_path: "/data/media"
    uploads_path: "/data/uploads"
    signing_key_path: "/data/signing.key"
    trusted_key_servers:
      - server_name: "matrix.org"
    url_preview_enabled: false
    enable_registration: false
    max_upload_size: 50M
    report_stats: false
  '';

  logConfig = ''
    version: 1
    formatters:
      precise:
        format: '%(asctime)s - %(name)s - %(levelname)s - %(request)s - %(message)s'
    handlers:
      console:
        class: logging.StreamHandler
        formatter: precise
    loggers:
      synapse:
        level: INFO
      synapse.storage:
        level: INFO
    root:
      level: INFO
    disable_existing_loggers: false
  '';

  containerEnv = [
    {
      name = "SYNAPSE_SERVER_NAME";
      value = env.hosts.matrix;
    }
    {
      name = "SYNAPSE_REPORT_STATS";
      value = "no";
    }
    {
      name = "SYNAPSE_CONFIG_PATH";
      value = "/config/homeserver.yaml";
    }
  ];

in
[
  (lib.deployment {
    inherit
      name
      image
      tag
      port
      resources
      labels
      ;
    env = containerEnv;
    inherit securityContext;
    inherit podSecurityContext;
    liveness = livenessProbe;
    readiness = readinessProbe;
    inherit (env) namespace;
    replicas = env.replicas.default;
    # RWO PVC (synapse-data, ceph-rbd): RollingUpdate can Multi-Attach the volume
    # across nodes during a rollout. Recreate terminates the old pod first so the
    # new pod can exclusively own the ReadWriteOnce volume.
    strategyType = "Recreate";

    volumeMounts = [
      {
        name = "config";
        mountPath = "/config/homeserver.yaml";
        subPath = "homeserver.yaml";
        readOnly = true;
      }
      {
        name = "log-config";
        mountPath = "/data/log.config";
        subPath = "log.config";
        readOnly = true;
      }
      {
        name = "data";
        mountPath = "/data";
      }
    ];

    initContainers = [
      {
        name = "init-config";
        image = "${image}:${tag}";
        command = [
          "/bin/sh"
          "-c"
          ''sed -e "s|__SYNAPSE_MACAROON_SECRET__|$(cat /mnt/secrets/macaroon-secret-key)|g" -e "s|__SYNAPSE_OIDC_CLIENT_SECRET__|$(cat /mnt/secrets-oidc/oidc-client-secret)|g" /mnt/config/homeserver.yaml > /config/homeserver.yaml''
        ];
        volumeMounts = [
          {
            name = "secrets";
            mountPath = "/mnt/secrets";
            readOnly = true;
          }
          {
            name = "secrets-oidc";
            mountPath = "/mnt/secrets-oidc";
            readOnly = true;
          }
          {
            name = "config-src";
            mountPath = "/mnt/config";
            readOnly = true;
          }
          {
            name = "config";
            mountPath = "/config";
          }
        ];
      }
    ];

    volumes = [
      {
        name = "config";
        emptyDir = { };
      }
      {
        name = "config-src";
        configMap = {
          name = "${name}-config";
          items = [
            {
              key = "homeserver.yaml";
              path = "homeserver.yaml";
            }
          ];
        };
      }
      {
        name = "secrets";
        secret = {
          secretName = "${name}-macaroon";
        };
      }
      {
        name = "secrets-oidc";
        secret = {
          secretName = "${name}-oidc";
        };
      }
      {
        name = "log-config";
        configMap = {
          name = "${name}-config";
          items = [
            {
              key = "log.config";
              path = "log.config";
            }
          ];
        };
      }
      {
        name = "data";
        persistentVolumeClaim = {
          claimName = "${name}-data";
        };
      }
    ];

    annotations = {
      "checksum/config" = "synapse-config-v3";
    };
  })

  (lib.service {
    inherit name port labels;
    inherit (env) namespace;
  })

  (lib.ingressWithCert {
    inherit name;
    host = env.hosts.matrix;
    inherit port;
    inherit (env.ingress) className;
    tlsSecretName = env.tls.secretName;
    annotations = env.ingress.annotations // {
      "haproxy-ingress.github.io/timeout-server" = "600s";
    };
    inherit (env) namespace;
  })

  (lib.configMap {
    name = "${name}-config";
    inherit (env) namespace;
    inherit labels;
    data = {
      "homeserver.yaml" = homeserverConfig;
      "log.config" = logConfig;
    };
  })

  (lib.pvc {
    name = "${name}-data";
    size = "10Gi";
    storageClass = env.storage.rwo;
    accessModes = [ "ReadWriteOnce" ];
    inherit (env) namespace;
    inherit labels;
  })

  (lib.secret {
    name = "${name}-db";
    inherit (env) namespace;
    inherit labels;
    stringData = {
      "db-password" = db.synapse.password;
    };
  })

  # Macaroon signing key Secret — sealed at build time. Rendered into
  # homeserver.yaml by the init-config initContainer (no cleartext in the
  # ConfigMap). Value unchanged (behavior-preserving).
  (lib.secret {
    name = "${name}-macaroon";
    inherit (env) namespace;
    inherit labels;
    stringData = {
      "macaroon-secret-key" = "opendesk-synapse-macaroon-secret-change-me";
    };
  })

  # OIDC client secret for the Keycloak `opendesk-matrix` client — sealed at
  # build time. Rendered into homeserver.yaml oidc_config by the init-config
  # initContainer (see plan/2026-08-15-intercom-oidc-plan.md §5).
  (lib.secret {
    name = "${name}-oidc";
    inherit (env) namespace;
    inherit labels;
    stringData = {
      "oidc-client-secret" = "synapse-oidc-client-secret-change-me";
    };
  })
]
