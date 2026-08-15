# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Redis — session store for the Intercom-Service (ICS) on SCS.
#
# Ephemeral by design (NO persistent volume): ICS sessions are stateless
# cookies + Redis; losing Redis only logs users out, matching the openDesk
# reference deployment (shared Redis, no persistence for ICS).
#
# Password auth: REDIS_PASSWORD from the sealed `redis` Secret (key `password`)
# passed as `redis-server --requirepass $(REDIS_PASSWORD)` (kubelet expands
# $(ENV) in container args).

{
  lib,
  env ? import ../environments/scs/default.nix { inherit lib; },
  ...
}:

let
  name = "redis";
  image = "docker.io/redis";
  tag = "7.4-alpine";
  port = 6379;

  labels = lib.mkLabels { inherit name; } // {
    "app.kubernetes.io/component" = "session-store";
    "app.kubernetes.io/managed-by" = "nix";
  };

  resources = {
    requests = {
      cpu = "100m";
      memory = "128Mi";
    };
    limits = {
      cpu = "500m";
      memory = "512Mi";
    };
  };

  securityContext = {
    allowPrivilegeEscalation = false;
    runAsNonRoot = true;
    runAsUser = 1000;
    runAsGroup = 1000;
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
    runAsUser = 1000;
    runAsGroup = 1000;
    fsGroup = 1000;
    fsGroupChangePolicy = "OnRootMismatch";
  };

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
    env = [
      {
        name = "REDIS_PASSWORD";
        valueFrom = {
          secretKeyRef = {
            name = "redis";
            key = "password";
          };
        };
      }
    ];
    cmdArgs = [
      "redis-server"
      "--requirepass"
      "$(REDIS_PASSWORD)"
    ];
    inherit securityContext;
    inherit podSecurityContext;
    # /data must be a k8s-managed emptyDir: the redis image's anonymous volume
    # was unwritable (MISCONF RDB save errors broke the ICS session store).
    volumes = [
      {
        name = "data";
        emptyDir = { };
      }
    ];
    volumeMounts = [
      {
        name = "data";
        mountPath = "/data";
      }
    ];
    namespace = env.namespaceEdu;
    # Single replica, no PVC — Recreate keeps the deployment simple and avoids
    # any volume Multi-Attach concerns if persistence is added later.
    strategyType = "Recreate";
  })

  (lib.service {
    inherit name port labels;
    namespace = env.namespaceEdu;
  })

  # Redis password — sealed at build time (scs/default.nix `serialize`).
  (lib.secret {
    name = "redis";
    namespace = env.namespaceEdu;
    inherit labels;
    stringData = {
      "password" = "redis-password-change-me";
    };
  })
]
