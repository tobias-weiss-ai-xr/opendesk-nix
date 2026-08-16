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
      enabled: true
      discovery_method: "oidc"
      issuer: "https://${env.hosts.keycloak}/realms/${env.keycloak.realm}"
      client_id: "opendesk-matrix"
      client_secret: "__SYNAPSE_OIDC_CLIENT_SECRET__"
      scopes: ["openid", "profile", "email"]
      user_mapping_provider:
        config:
          # The Intercom-Service impersonates users via the appservice login
          # as opendesk_useruuid (USER_UNIQUE_MAPPER=opendesk_useruuid) — the
          # OIDC-created mxids MUST use the same localpart or the appservice
          # login 404s ("No row found (users)"). Upstream openDesk ties both
          # via the same toggle (useImmutableIdentifierForLocalpart).
          localpart_template: "{{ user.opendesk_useruuid }}"
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
    # Application services (plan/2026-08-16-matrix-appservice-plan.md): the
    # Intercom-Service is registered as an appservice so it can fetch
    # per-user tokens via m.login.application_service. The registration file
    # is rendered at startup by the init-config initContainer from the sealed
    # synapse-appservice Secret (token placeholders in the template).
    app_service_config_files:
      - /config/appservice/intercom.yaml
  '';

  # Appservice registration for the Intercom-Service — templated with the
  # as/hs tokens; rendered to /config/appservice/intercom.yaml at startup by
  # the init-config initContainer from the mounted synapse-appservice Secret.
  # `url` is explicit null: Synapse requires the key (string or null) even for
  # login-only appservices, and the ICS never receives pushes. Non-exclusive
  # catch-all user namespace so the AS may log in as any user (ghost users
  # created on demand; real OIDC users take precedence).
  appserviceConfig = ''
    id: intercom
    hs_token: "__MATRIX_HS_TOKEN__"
    as_token: "__MATRIX_AS_TOKEN__"
    sender_localpart: intercom
    # Synapse requires the url key (string or explicit null) even for
    # login-only appservices — explicit null: the ICS never receives pushes.
    url:
    namespaces:
      users:
        - exclusive: false
          regex: "@.*"
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
    # Trust the cluster's self-signed wildcard cert (CN=home.opendesk-edu.org)
    # for the OIDC discovery fetch against https://id.home.opendesk-edu.org —
    # without it the OIDC provider silently fails to load at startup (no
    # m.login.sso flow). Same bundle the ICS uses via NODE_EXTRA_CA_CERTS.
    {
      name = "SSL_CERT_FILE";
      value = "/etc/ssl/certs/cluster-ca-bundle.crt";
    }
    {
      name = "REQUESTS_CA_BUNDLE";
      value = "/etc/ssl/certs/cluster-ca-bundle.crt";
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
        # Full /config mount (read-only): the init-config initContainer
        # renders homeserver.yaml + appservice/intercom.yaml into the shared
        # emptyDir; the main container reads both from here. (SubPath mounts
        # of individual files proved fragile; full mount is reliable.)
        name = "config";
        mountPath = "/config";
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
      {
        name = "cluster-ca";
        mountPath = "/etc/ssl/certs/cluster-ca-bundle.crt";
        subPath = "cluster-ca-bundle.crt";
        readOnly = true;
      }
    ];

    initContainers = [
      {
        name = "init-config";
        image = "${image}:${tag}";
        command = [
          "/bin/sh"
          "-c"
          ''
            mkdir -p /config/appservice
            sed -e "s|__SYNAPSE_MACAROON_SECRET__|$(cat /mnt/secrets/macaroon-secret-key)|g" \
                -e "s|__SYNAPSE_OIDC_CLIENT_SECRET__|$(cat /mnt/secrets-oidc/oidc-client-secret)|g" \
                /mnt/config/homeserver.yaml > /config/homeserver.yaml
            sed -e "s|__MATRIX_AS_TOKEN__|$(cat /mnt/secrets-appservice/matrix-as-token)|g" \
                -e "s|__MATRIX_HS_TOKEN__|$(cat /mnt/secrets-appservice/matrix-hs-token)|g" \
                /mnt/config/intercom.yaml > /config/appservice/intercom.yaml
          ''
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
            name = "secrets-appservice";
            mountPath = "/mnt/secrets-appservice";
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
        # Cluster self-signed wildcard bundle (public certs) — the OIDC
        # discovery fetch must trust https://id.home.opendesk-edu.org.
        name = "cluster-ca";
        configMap = {
          name = "cluster-ca";
          items = [
            {
              key = "cluster-ca-bundle.crt";
              path = "cluster-ca-bundle.crt";
            }
          ];
        };
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
            {
              # ConfigMap keys cannot contain "/" (k8s validation), so the
              # template is stored under a dash key and projected at a FLAT
              # path (no subdirectory — subdirectory projections proved
              # unreliable on this kubelet; the init-config initContainer
              # writes the rendered file to /config/appservice/ itself).
              key = "appservice-intercom.yaml";
              path = "intercom.yaml";
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
        name = "secrets-appservice";
        secret = {
          secretName = "${name}-appservice";
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
      "checksum/config" = "synapse-config-v5";
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
      "appservice-intercom.yaml" = appserviceConfig;
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

  # Appservice tokens for the Intercom-Service registration (see
  # plan/2026-08-16-matrix-appservice-plan.md) — sealed at build time,
  # real values applied out-of-band by the operator: matrix-as-token = the
  # token the ICS presents (intercom Secret key matrix-as-token);
  # matrix-hs-token = newly generated. Rendered into
  # appservice/intercom.yaml by the init-config initContainer.
  (lib.secret {
    name = "${name}-appservice";
    inherit (env) namespace;
    inherit labels;
    stringData = {
      "matrix-as-token" = "opendesk-synapse-appservice-as-token-change-me";
      "matrix-hs-token" = "opendesk-synapse-appservice-hs-token-change-me";
    };
  })

  # Cluster self-signed wildcard CA bundle (PUBLIC certs — ConfigMap, never a
  # Secret). Synapse must trust it for the OIDC discovery fetch; the ICS uses
  # the same bundle via NODE_EXTRA_CA_CERTS. Same content as the out-of-band
  # cluster-ca ConfigMap in opendesk-edu.
  (lib.configMap {
    name = "cluster-ca";
    inherit (env) namespace;
    inherit labels;
    data = {
      "cluster-ca-bundle.crt" = builtins.readFile ../cluster-ca-bundle.crt;
    };
  })
]
