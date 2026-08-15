# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Stalwart — Mail Server (SMTP/IMAP/JMAP)
# Image: docker.io/stalwartlabs/stalwart:latest

{
  lib,
  env ? import ../environments/scs/default.nix { inherit lib; },
  ...
}:

let
  name = "stalwart";
  image = "docker.io/stalwartlabs/stalwart";
  tag = "v0.16.16";
  port = 8080;

  labels = lib.mkLabels { inherit name; } // {
    "app.kubernetes.io/component" = "mail";
    "app.kubernetes.io/managed-by" = "nix";
  };

  resources = {
    requests = {
      cpu = "200m";
      memory = "512Mi";
    };
    limits = {
      cpu = "1";
      memory = "1Gi";
    };
  };

  securityContext = {
    allowPrivilegeEscalation = false;
    runAsNonRoot = false;
    readOnlyRootFilesystem = false;
    capabilities = {
      drop = [ ];
    };
    seccompProfile = {
      type = "RuntimeDefault";
    };
  };

  podSecurityContext = {
    runAsNonRoot = false;
    fsGroup = 0;
    fsGroupChangePolicy = "OnRootMismatch";
  };

  livenessProbe = lib.mkProbe {
    type = "tcp";
    inherit port;
    initialDelaySeconds = 30;
    periodSeconds = 10;
    failureThreshold = 5;
  };

  readinessProbe = lib.mkProbe {
    type = "tcp";
    inherit port;
    initialDelaySeconds = 5;
    periodSeconds = 5;
    failureThreshold = 3;
  };

  stalwartConfig = ''
    [server]
    hostname = "${env.hosts.stalwart}"
    listen_addr = "0.0.0.0:${toString port}"
    protocol = "http"

    [server.listener.smtp]
    bind = "[::]:25"
    protocol = "smtp"

    [server.listener.submission]
    bind = "[::]:587"
    protocol = "submission"

    [server.listener.submissions]
    bind = "[::]:465"
    protocol = "submissions"
    tls.implicit = true

    [server.listener.imap]
    bind = "[::]:143"
    protocol = "imap"

    [server.listener.imaptls]
    bind = "[::]:993"
    protocol = "imap"
    tls.implicit = true

    [storage]
    type = "sqlite"
    path = "/data/stalwart"

    [storage.data]
    type = "sqlite"
    path = "/data/stalwart/data.db"

    [storage.blob]
    type = "sqlite"
    path = "/data/stalwart/blob.db"

    [storage.fts]
    type = "sqlite"
    path = "/data/stalwart/fts.db"

    [storage.lookup]
    type = "sqlite"
    path = "/data/stalwart/lookup.db"

    [authentication.fallback]
    type = "password"
    [authentication.fallback.password]
    secret = "__STALWART_FALLBACK_PASSWORD__"

    [tracer]
    level = "info"
    prefix = "stalwart"
  '';

  containerEnv = [
    {
      name = "STALWART_PORT";
      value = toString port;
    }
    {
      name = "STALWART_HOSTNAME";
      value = env.hosts.stalwart;
    }
    {
      name = "STALWART_CONFIG";
      value = "/etc/stalwart/config.toml";
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
    command = [ "stalwart" ];
    cmdArgs = [
      "-c"
      "/etc/stalwart/config.toml"
    ];
    env = containerEnv;
    inherit securityContext;
    inherit podSecurityContext;
    liveness = livenessProbe;
    readiness = readinessProbe;
    namespace = env.namespaceEdu;
    replicas = env.replicas.default;
    # RWO PVC (stalwart-data, ceph-rbd): RollingUpdate can Multi-Attach the volume
    # across nodes during a rollout. Recreate terminates the old pod first so the
    # new pod can exclusively own the ReadWriteOnce volume.
    strategyType = "Recreate";

    ports = [
      {
        containerPort = 8080;
        name = "http";
        protocol = "TCP";
      }
      {
        containerPort = 25;
        name = "smtp";
        protocol = "TCP";
      }
      {
        containerPort = 587;
        name = "submission";
        protocol = "TCP";
      }
      {
        containerPort = 465;
        name = "submissions";
        protocol = "TCP";
      }
      {
        containerPort = 143;
        name = "imap";
        protocol = "TCP";
      }
      {
        containerPort = 993;
        name = "imaptls";
        protocol = "TCP";
      }
    ];

    volumeMounts = [
      {
        name = "config";
        mountPath = "/etc/stalwart/config.toml";
        subPath = "config.toml";
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
          ''sed "s|__STALWART_FALLBACK_PASSWORD__|$(cat /mnt/secrets/fallback-password)|g" /mnt/config/config.toml > /etc/stalwart/config.toml''
        ];
        volumeMounts = [
          {
            name = "secrets";
            mountPath = "/mnt/secrets";
            readOnly = true;
          }
          {
            name = "config-src";
            mountPath = "/mnt/config";
            readOnly = true;
          }
          {
            name = "config";
            mountPath = "/etc/stalwart";
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
              key = "config.toml";
              path = "config.toml";
            }
          ];
        };
      }
      {
        name = "secrets";
        secret = {
          secretName = "${name}-admin";
        };
      }
      {
        name = "data";
        persistentVolumeClaim = {
          claimName = "${name}-data";
        };
      }
    ];
  })

  (lib.service {
    inherit name port labels;
    namespace = env.namespaceEdu;
    ports = [
      {
        port = 8080;
        targetPort = 8080;
        protocol = "TCP";
        name = "http";
      }
      {
        port = 25;
        targetPort = 25;
        protocol = "TCP";
        name = "smtp";
      }
      {
        port = 587;
        targetPort = 587;
        protocol = "TCP";
        name = "submission";
      }
      {
        port = 465;
        targetPort = 465;
        protocol = "TCP";
        name = "submissions";
      }
      {
        port = 143;
        targetPort = 143;
        protocol = "TCP";
        name = "imap";
      }
      {
        port = 993;
        targetPort = 993;
        protocol = "TCP";
        name = "imaptls";
      }
    ];
  })

  (lib.ingressWithCert {
    inherit name;
    host = env.hosts.stalwart;
    inherit port;
    inherit (env.ingress) className;
    tlsSecretName = env.tls.secretName;
    namespace = env.namespaceEdu;
  })

  (lib.configMap {
    name = "${name}-config";
    namespace = env.namespaceEdu;
    inherit labels;
    data = {
      "config.toml" = stalwartConfig;
    };
  })

  (lib.pvc {
    name = "${name}-data";
    size = "10Gi";
    storageClass = env.storage.rwo;
    accessModes = [ "ReadWriteOnce" ];
    namespace = env.namespaceEdu;
    inherit labels;
  })

  # Fallback/admin password Secret — sealed at build time. Rendered into
  # config.toml by the init-config initContainer (no cleartext in the
  # ConfigMap). Value unchanged (behavior-preserving).
  (lib.secret {
    name = "${name}-admin";
    namespace = env.namespaceEdu;
    inherit labels;
    stringData = {
      "fallback-password" = "stalwart-admin-change-me";
    };
  })
]
