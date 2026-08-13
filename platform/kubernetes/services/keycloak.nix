# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Keycloak — IAM/OIDC provider for openDesk
# Uses shared Galera cluster for database (instead of embedded H2)
# Image: quay.io/keycloak/keycloak:26.0

{ lib, env ? import ../environments/scs/default.nix { inherit lib; }, ... }:

let
  name = "keycloak";
  image = "quay.io/keycloak/keycloak";
  tag = "26.0";
  port = 8080;

  labels = lib.mkLabels { inherit name; } // {
    "app.kubernetes.io/component" = "identity";
    "app.kubernetes.io/managed-by" = "nix";
  };

  db = env.database;

  resources = {
    requests = {
      cpu = "500m";
      memory = "1Gi";
    };
    limits = {
      cpu = "2";
      memory = "3Gi";
    };
  };

  securityContext = {
    allowPrivilegeEscalation = false;
    runAsNonRoot = true;
    runAsUser = 1000;
    readOnlyRootFilesystem = false;
    capabilities = { drop = [ "ALL" ]; };
    seccompProfile = { type = "RuntimeDefault"; };
  };

  podSecurityContext = {
    runAsNonRoot = true;
    runAsUser = 1000;
    fsGroup = 1000;
    fsGroupChangePolicy = "OnRootMismatch";
  };

  livenessProbe = lib.mkProbe {
    type = "http";
    inherit port;
    path = "/health/ready";
    initialDelaySeconds = 60;
    periodSeconds = 10;
    failureThreshold = 6;
  };

  readinessProbe = lib.mkProbe {
    type = "http";
    inherit port;
    path = "/health/ready";
    initialDelaySeconds = 15;
    periodSeconds = 5;
    failureThreshold = 3;
  };

  containerEnv = [
    {
      name = "KC_BOOTSTRAP_ADMIN_USERNAME";
      value = "admin";
    }
    {
      name = "KC_BOOTSTRAP_ADMIN_PASSWORD";
      value = "admin";
    }
    {
      name = "KC_HOSTNAME";
      value = env.hosts.keycloak;
    }
    {
      name = "KC_HTTP_ENABLED";
      value = "true";
    }
    {
      name = "KC_PROXY_HEADERS";
      value = "xforwarded";
    }
    {
      name = "KC_HOSTNAME_STRICT";
      value = "false";
    }
    {
      name = "KC_HOSTNAME_STRICT_HTTPS";
      value = "false";
    }
    {
      name = "KC_DB";
      value = "mariadb";
    }
    {
      name = "KC_DB_URL";
      value =
        "jdbc:mariadb://${db.host}:${toString db.port}/${db.keycloak.name}";
    }
    {
      name = "KC_DB_USERNAME";
      value = db.keycloak.user;
    }
    {
      name = "KC_DB_PASSWORD";
      value = db.keycloak.password;
    }
    {
      name = "KC_LOG_LEVEL";
      value = "INFO";
    }
    {
      name = "KC_FEATURES";
      value = "token-exchange,admin-fine-grained-authz";
    }
  ];

in [
  (lib.deployment {
    inherit name image tag port resources labels;
    env = containerEnv;
    securityContext = securityContext;
    podSecurityContext = podSecurityContext;
    liveness = livenessProbe;
    readiness = readinessProbe;
    namespace = env.namespace;
    replicas = env.replicas.default;

    command = [ "/opt/keycloak/bin/kc.sh" ];
    cmdArgs = [ "start" ];

    volumeMounts = [{
      name = "data";
      mountPath = "/opt/keycloak/data";
    }];

    volumes = [{
      name = "data";
      persistentVolumeClaim = { claimName = "${name}-data"; };
    }];
  })

  (lib.service {
    inherit name port labels;
    namespace = env.namespace;
  })

  (lib.ingressWithCert {
    inherit name;
    host = env.hosts.keycloak;
    port = port;
    className = env.ingress.className;
    tlsSecretName = env.tls.secretName;
    annotations = env.ingress.annotations // {
      "haproxy-ingress.github.io/timeout-server" = "300s";
    };
    namespace = env.namespace;
  })

  (lib.pvc {
    name = "${name}-data";
    size = "5Gi";
    storageClass = env.storage.rwo;
    accessModes = [ "ReadWriteOnce" ];
    namespace = env.namespace;
    labels = labels;
  })

  (lib.secret {
    name = "${name}-db";
    namespace = env.namespace;
    labels = labels;
    stringData = { "db-password" = db.keycloak.password; };
  })
]
