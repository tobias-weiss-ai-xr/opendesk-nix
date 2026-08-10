# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Element Web — Matrix web client
# Image: docker.io/vectorim/element-web:latest

{ lib, env ? import ../environments/scs/default.nix { inherit lib; }, ... }:

let
  name = "element";
  image = "docker.io/vectorim/element-web";
  tag = "latest";
  port = 80;

  labels = lib.mkLabels { inherit name; } // {
    "app.kubernetes.io/component" = "messaging";
    "app.kubernetes.io/managed-by" = "nix";
  };

  resources = {
    requests = { cpu = "100m"; memory = "128Mi"; };
    limits = { cpu = "500m"; memory = "512Mi"; };
  };

  securityContext = {
    allowPrivilegeEscalation = false;
    runAsNonRoot = true;
    runAsUser = 1000;
    runAsGroup = 1000;
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
    path = "/";
    initialDelaySeconds = 10;
    periodSeconds = 10;
    failureThreshold = 3;
  };

  readinessProbe = lib.mkProbe {
    type = "http";
    inherit port;
    path = "/";
    initialDelaySeconds = 5;
    periodSeconds = 5;
    failureThreshold = 3;
  };

  elementConfig = ''
    {
      "default_server_config": {
        "m.homeserver": {
          "base_url": "https://${env.hosts.matrix}",
          "server_name": "${env.hosts.matrix}"
        }
      },
      "brand": "openDesk Edu Chat",
      "disable_guests": false,
      "disable_3pid_login": false,
      "default_country_code": "DE",
      "show_labs_settings": true,
      "integrations_ui_url": "",
      "integrations_rest_url": "",
      "integrations_widgets_urls": []
    }
  '';

in [
  (lib.deployment {
    inherit name image tag port resources labels;
    securityContext = securityContext;
    podSecurityContext = podSecurityContext;
    liveness = livenessProbe;
    readiness = readinessProbe;
    namespace = env.namespace;
    replicas = env.replicas.default;

    volumeMounts = [
      { name = "config"; mountPath = "/app/config.json"; subPath = "config.json"; readOnly = true; }
    ];

    volumes = [
      { name = "config"; configMap = { name = "${name}-config"; items = [{ key = "config.json"; path = "config.json"; }]; }; }
    ];

    annotations = {
      "checksum/config" = "element-config-v1";
    };
  })

  (lib.service {
    inherit name port labels;
    namespace = env.namespace;
  })

  (lib.ingressWithCert {
    inherit name;
    host = env.hosts.element;
    port = port;
    className = env.ingress.className;
    tlsSecretName = env.tls.secretName;
    namespace = env.namespace;
  })

  (lib.configMap {
    name = "${name}-config";
    namespace = env.namespace;
    labels = labels;
    data = {
      "config.json" = elementConfig;
    };
  })
]
