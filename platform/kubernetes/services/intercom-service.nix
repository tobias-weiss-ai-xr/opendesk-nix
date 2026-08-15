# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Intercom-Service (ICS) — browser OIDC broker for openDesk Edu on SCS.
#
# What it does (see plan/2026-08-15-intercom-oidc-plan.md §3 and
# docs/intercom-oidc.md):
#   * silent login   — passes OIDC tokens between apps without re-auth
#   * backchannel logout — coordinated SSO session termination (Keycloak →
#     ICS → apps)
#   * file-picker proxy `/oc/` → OpenCloud (Keycloak token exchange to the
#     `opendesk-opencloud` audience; user's token injected as Bearer)
#   * `/sogo/` CalDAV/CardDAV proxy (route present; enabled later)
#
# Image: ghcr.io/opendesk-edu/intercom-service:2.23.11 — the openDesk Edu fork
# of upstream ICS 2.23.11 (Node Alpine base + /oc/ + /sogo/ + /health; see
# docker/intercom-service/). The image is mirrored into the SCS cluster
# registry (containerd redirects ghcr.io → 172.17.0.6:5001).
#
# Config env mirrors the upstream chart's `ics.*` values (see
# helmfile/apps/nubus/values-intercom-service.yaml.gotmpl in the openDesk
# monorepo): ISSUER_BASE_URL, ORIGIN_REGEX, USER_UNIQUE_MAPPER=opendesk_useruuid,
# USERNAME_CLAIM=opendesk_username, CLIENT_ID=opendesk-intercom, OC_* (fork),
# MATRIX_*, REDIS_*. Secrets come from sealed Secrets via secretKeyRef.

{
  lib,
  env ? import ../environments/scs/default.nix { inherit lib; },
  ...
}:

let
  name = "intercom-service";
  image = "ghcr.io/opendesk-edu/intercom-service";
  tag = "2.23.11";
  port = 8080;

  labels = lib.mkLabels { inherit name; } // {
    "app.kubernetes.io/component" = "broker";
    "app.kubernetes.io/managed-by" = "nix";
  };

  resources = {
    requests = {
      cpu = "100m";
      memory = "256Mi";
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
    readOnlyRootFilesystem = true;
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

  livenessProbe = lib.mkProbe {
    type = "http";
    inherit port;
    path = "/health";
    initialDelaySeconds = 30;
    periodSeconds = 10;
    failureThreshold = 3;
  };

  readinessProbe = lib.mkProbe {
    type = "http";
    inherit port;
    path = "/health";
    initialDelaySeconds = 15;
    periodSeconds = 5;
    failureThreshold = 3;
  };

  # Non-secret ICS config (the fork reads these from env; see
  # docker/intercom-service/config/config.js).
  containerEnv = [
    {
      name = "PORT";
      value = toString port;
    }
    {
      name = "BASE_URL";
      value = "https://${env.hosts.intercom}";
    }
    {
      name = "ISSUER_BASE_URL";
      value = "https://${env.hosts.keycloak}/realms/${env.keycloak.realm}";
    }
    {
      name = "ORIGIN_REGEX";
      value = "^https://.*\\.${env.ingress.domain}$";
    }
    {
      name = "ENABLE_SESSION_COOKIE";
      value = "true";
    }
    {
      name = "SESSION_ROLLING_DURATION";
      value = "86400";
    }
    {
      name = "LOG_LEVEL";
      value = "INFO";
    }
    {
      name = "USER_UNIQUE_MAPPER";
      value = "opendesk_useruuid";
    }
    {
      name = "USERNAME_CLAIM";
      value = "opendesk_username";
    }
    {
      name = "CLIENT_ID";
      value = "opendesk-intercom";
    }
    # OpenCloud (fork /oc/ route) — primary file service.
    {
      name = "OC_ENABLED";
      value = "true";
    }
    {
      name = "OC_URL";
      value = "https://${env.hosts.opencloud}";
    }
    {
      name = "OC_AUDIENCE";
      value = "opendesk-opencloud";
    }
    # SOGo CalDAV/CardDAV proxy — route present in the fork, activation later.
    {
      name = "SOGO_ENABLED";
      value = "false";
    }
    # Nextcloud disabled — OpenCloud is our file service.
    {
      name = "NC_ENABLED";
      value = "false";
    }
    # Matrix integration (silent login + appservice secret).
    {
      name = "MATRIX_ENABLED";
      value = "true";
    }
    {
      name = "MATRIX_URL";
      value = "https://${env.hosts.matrix}";
    }
    {
      name = "MATRIX_SERVER_NAME";
      value = env.hosts.matrix;
    }
    # Redis session store.
    {
      name = "REDIS_HOST";
      value = "redis.${env.namespaceEdu}.svc.cluster.local";
    }
    {
      name = "REDIS_PORT";
      value = "6379";
    }
    {
      name = "REDIS_USER";
      value = "default";
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
    env = containerEnv
      # Secret env — sealed Secrets via secretKeyRef (never cleartext).
      ++ [
        {
          name = "SECRET";
          valueFrom = {
            secretKeyRef = {
              name = "intercom";
              key = "session-secret";
            };
          };
        }
        {
          # Same value as keycloak-clients/intercom-client-secret (the Keycloak
          # client secret the bootstrap Job creates) — duplicated into the
          # `intercom` Secret because a pod can only mount secrets from its own
          # namespace (opendesk-edu).
          name = "CLIENT_SECRET";
          valueFrom = {
            secretKeyRef = {
              name = "intercom";
              key = "client-secret";
            };
          };
        }
        {
          name = "MATRIX_AS_SECRET";
          valueFrom = {
            secretKeyRef = {
              name = "intercom";
              key = "matrix-as-token";
            };
          };
        }
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
    inherit securityContext;
    inherit podSecurityContext;
    liveness = livenessProbe;
    readiness = readinessProbe;
    namespace = env.namespaceEdu;
    # Single stateless replica — Recreate avoids any rollout overlap.
    strategyType = "Recreate";
  })

  (lib.service {
    inherit name port labels;
    namespace = env.namespaceEdu;
  })

  (lib.ingressWithCert {
    inherit name;
    host = env.hosts.intercom;
    inherit port;
    inherit (env.ingress) className;
    tlsSecretName = env.tls.secretName;
    annotations = env.ingress.annotations;
    namespace = env.namespaceEdu;
  })

  # ICS session/secret material — sealed at build time. `session-secret` MUST
  # be >= 32 chars (express-openid-connect requirement). `matrix-as-token` is
  # the Matrix application-service token the ICS presents to synapse.
  (lib.secret {
    name = "intercom";
    namespace = env.namespaceEdu;
    inherit labels;
    stringData = {
      "session-secret" = "intercom-session-secret-change-me-0123456789";
      "matrix-as-token" = "intercom-matrix-as-token-change-me-0123456789";
      "client-secret" = "intercom-client-secret-change-me";
    };
  })
]
