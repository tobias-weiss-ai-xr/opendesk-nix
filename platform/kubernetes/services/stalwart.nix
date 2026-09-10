# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Stalwart — Mail Server (SMTP/IMAP/JMAP)
# Image: ghcr.io/tobias-weiss-ai-xr/stalwart-rewrite (fork with automatic
# provisioning of default IMAP folders — Sent/Drafts/Trash/Junk — on first
# login; always-on, no config knob). Private GHCR package: the cluster pulls
# it through the zot pull-through cache (ghcr.io/tobias-weiss-ai-xr/* is
# whitelisted there), so the image stays private.
#
# Bootstrap is the 0.16.x JSON DataStore registry: config.json only seeds the
# SQLite registry; ALL server settings (listeners, OIDC directory, domains)
# live in the registry DB and are managed via the JMAP API
# (urn:stalwart:jmap) — the running deployment was configured that way.

{
  lib,
  env ? import ../environments/scs/default.nix { inherit lib; },
  ...
}:

let
  name = "stalwart";
  image = "ghcr.io/tobias-weiss-ai-xr/stalwart-rewrite";
  # CI publishes :latest and :sha — pin the sha so rollouts are reproducible.
  tag = "90c1b0e13eb67fc3b80418d232f897142ed5f849";
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

  # Seeds the registry on FIRST boot only (empty PVC). Existing deployments
  # keep their registry contents across restarts/upgrades.
  configJson = builtins.toJSON {
    "@type" = "Sqlite";
    path = "/data/stalwart.db";
  };

  containerEnv = [
    {
      name = "STALWART_PORT";
      value = toString port;
    }
    {
      name = "STALWART_HOSTNAME";
      value = env.hosts.stalwart;
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
      "--config"
      "/etc/stalwart/config.json"
    ];
    env = containerEnv;
    # Bootstrap-only: seeds the fallback recovery admin on first boot. The
    # live cluster uses a hand-managed value (kubectl-applied deployment) —
    # this placeholder is the repo convention (see galera/keycloak secrets);
    # re-seed after apply if the live value differs.
    envFrom = [
      {
        secretRef = {
          name = "${name}-admin";
        };
      }
    ];
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
      {
        containerPort = 995;
        name = "pop3";
        protocol = "TCP";
      }
      {
        containerPort = 4190;
        name = "sieve";
        protocol = "TCP";
      }
    ];

    volumeMounts = [
      {
        name = "config";
        mountPath = "/etc/stalwart/config.json";
        subPath = "config.json";
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
          items = [
            {
              key = "config.json";
              path = "config.json";
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
      {
        port = 995;
        targetPort = 995;
        protocol = "TCP";
        name = "pop3";
      }
      {
        port = 4190;
        targetPort = 4190;
        protocol = "TCP";
        name = "sieve";
      }
    ];
  })

  (lib.configMap {
    name = "${name}-config";
    namespace = env.namespaceEdu;
    inherit labels;
    data = {
      "config.json" = configJson;
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

  # Recovery admin bootstrap secret — envFrom into the container. Only read
  # when the registry is EMPTY (first boot); the live cluster carries a
  # hand-managed value. Repo convention placeholder (see galera/keycloak).
  (lib.secret {
    name = "${name}-admin";
    namespace = env.namespaceEdu;
    inherit labels;
    stringData = {
      "STALWART_RECOVERY_ADMIN" = env.stalwart.recoveryAdmin;
    };
  })
]
