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
    macaroon_secret_key: "opendesk-synapse-macaroon-secret-change-me"
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
    ];

    volumes = [
      {
        name = "config";
        configMap = {
          name = "${name}-config";
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
      "checksum/config" = "synapse-config-v1";
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
]
