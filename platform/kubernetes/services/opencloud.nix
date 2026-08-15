# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# OpenCloud — File storage & collaboration (OpenCloud/oCIS)
# Uses embedded storage (NATS, filesystem) — no external database needed.
# Config is generated via `opencloud init` and mounted as a Secret.
# Image: docker.io/opencloudeu/opencloud:7.2.2
# Pinned to a stable release tag. Using :latest caused recurrent BoltDB/Bleve
# corruption (search service) on every image pull / pod restart — see incident 2026-08-15.

{
  lib,
  env ? import ../environments/scs/default.nix { inherit lib; },
  ...
}:

let
  name = "opendesk-opencloud";
  image = "docker.io/opencloudeu/opencloud";
  # Pinned: :latest pulled shifting builds that re-corrupted the BoltDB/Bleve
  # stores on restart. 7.2.2 is the version verified running on the SCS cluster.
  tag = "7.2.2";
  port = 8080;

  labels = lib.mkLabels { inherit name; } // {
    "app.kubernetes.io/component" = "collaboration";
    "app.kubernetes.io/managed-by" = "nix";
  };

  resources = {
    requests = {
      cpu = "500m";
      memory = "1Gi";
    };
    limits = {
      cpu = "2";
      memory = "2Gi";
    };
  };

  securityContext = {
    allowPrivilegeEscalation = false;
    runAsNonRoot = true;
    runAsUser = 1000;
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
    fsGroup = 1000;
    fsGroupChangePolicy = "OnRootMismatch";
  };

  livenessProbe = lib.mkProbe {
    type = "http";
    inherit port;
    path = "/healthz";
    initialDelaySeconds = 60;
    periodSeconds = 15;
    failureThreshold = 5;
  };

  readinessProbe = lib.mkProbe {
    type = "http";
    inherit port;
    path = "/healthz";
    initialDelaySeconds = 15;
    periodSeconds = 5;
    failureThreshold = 3;
  };

  # OpenCloud config — generated via `opencloud init --insecure yes`
  # Contains all required secrets (jwt, transfer, machine_auth, system_user, etc.)
  opencloudConfig = ''
    token_manager:
      jwt_secret: CIU$waQwS+2%.@xDqY!Dbq!Ry.C!dXjX
    machine_auth_api_key: 1=W3EAf5#v4oG4Gjn2SL%btSFZ.9R3nV
    system_user_api_key: mGn9+jkGijzA*r6ePdBQgHu7Q5ZuEItU
    transfer_secret: 6pG*e-z#oszAI=c@az=G$hAD-6LVwMOs
    url_signing_secret: B*wR*fbqz6ZWipcjcTZEfHKhRxG-U&8p
    system_user_id: 1ff0f5e2-b069-4c6d-aee7-11a73460e236
    admin_user_id: ecae464e-8b00-4479-93d8-8bb1f3987997
    graph:
      application:
        id: e9520ad4-62f1-4306-b500-8520594f0834
      events:
        tls_insecure: true
      spaces:
        insecure: true
      identity:
        ldap:
          bind_password: H@S^M57vsVro6ElM+d!YH8rRW&F6*8Sn
      service_account:
        service_account_id: 140f97b5-a094-4656-a5b4-59765eb00593
        service_account_secret: ibMpTTl6iynMxnn0P%sS*-^u*QOD20Db
    idp:
      ldap:
        bind_password: KYZhAv2ytqjZkHP*+ND2CLk96G-p%=s.
    idm:
      service_user_passwords:
        admin_password: admin
        idm_password: H@S^M57vsVro6ElM+d!YH8rRW&F6*8Sn
        reva_password: '*%HWwspN1rGKgJjP1oDs6nHxhaS43Zru'
        idp_password: KYZhAv2ytqjZkHP*+ND2CLk96G-p%=s.
    collaboration:
      wopi:
        secret: =u*@HT7agxou9mZ9a.XhUtI^3sfrt3A*
      app:
        insecure: true
    proxy:
      oidc:
        insecure: true
      insecure_backends: true
      service_account:
        service_account_id: 140f97b5-a094-4656-a5b4-59765eb00593
        service_account_secret: ibMpTTl6iynMxnn0P%sS*-^u*QOD20Db
    frontend:
      app_handler:
        insecure: true
      archiver:
        insecure: true
      service_account:
        service_account_id: 140f97b5-a094-4656-a5b4-59765eb00593
        service_account_secret: ibMpTTl6iynMxnn0P%sS*-^u*QOD20Db
      ocdav:
        insecure: true
    auth_basic:
      auth_providers:
        ldap:
          bind_password: '*%HWwspN1rGKgJjP1oDs6nHxhaS43Zru'
    auth_bearer:
      auth_providers:
        oidc:
          insecure: true
    users:
      drivers:
        ldap:
          bind_password: '*%HWwspN1rGKgJjP1oDs6nHxhaS43Zru'
    groups:
      drivers:
        ldap:
          bind_password: '*%HWwspN1rGKgJjP1oDs6nHxhaS43Zru'
    ocm:
      service_account:
        service_account_id: 140f97b5-a094-4656-a5b4-59765eb00593
        service_account_secret: ibMpTTl6iynMxnn0P%sS*-^u*QOD20Db
    thumbnails:
      thumbnail:
        transfer_secret: 71C&8-4ny&q4Xfk+fx.gOafD2B&NTGGc
        webdav_allow_insecure: true
        cs3_allow_insecure: true
    search:
      events:
        tls_insecure: true
      service_account:
        service_account_id: 140f97b5-a094-4656-a5b4-59765eb00593
        service_account_secret: ibMpTTl6iynMxnn0P%sS*-^u*QOD20Db
    audit:
      events:
        tls_insecure: true
    settings:
      service_account_ids:
      - 140f97b5-a094-4656-a5b4-59765eb00593
    sharing:
      events:
        tls_insecure: true
      service_account:
        service_account_id: 140f97b5-a094-4656-a5b4-59765eb00593
        service_account_secret: ibMpTTl6iynMxnn0P%sS*-^u*QOD20Db
    storage_users:
      events:
        tls_insecure: true
      mount_id: cc6a315d-5262-488e-a9f0-1cca1463a8bc
      service_account:
        service_account_id: 140f97b5-a094-4656-a5b4-59765eb00593
        service_account_secret: ibMpTTl6iynMxnn0P%sS*-^u*QOD20Db
    notifications:
      notifications:
        events:
          tls_insecure: true
      service_account:
        service_account_id: 140f97b5-a094-4656-a5b4-59765eb00593
        service_account_secret: ibMpTTl6iynMxnn0P%sS*-^u*QOD20Db
    nats:
      nats:
        tls_skip_verify_client_cert: true
    gateway:
      storage_registry:
        storage_users_mount_id: cc6a315d-5262-488e-a9f0-1cca1463a8bc
    userlog:
      service_account:
        service_account_id: 140f97b5-a094-4656-a5b4-59765eb00593
        service_account_secret: ibMpTTl6iynMxnn0P%sS*-^u*QOD20Db
    auth_service:
      service_account:
        service_account_id: 140f97b5-a094-4656-a5b4-59765eb00593
        service_account_secret: ibMpTTl6iynMxnn0P%sS*-^u*QOD20Db
    clientlog:
      service_account:
        service_account_id: 140f97b5-a094-4656-a5b4-59765eb00593
        service_account_secret: ibMpTTl6iynMxnn0P%sS*-^u*QOD20Db
    activitylog:
      service_account:
        service_account_id: 140f97b5-a094-4656-a5b4-59765eb00593
        service_account_secret: ibMpTTl6iynMxnn0P%sS*-^u*QOD20Db
  '';

  containerEnv = [
    {
      name = "OC_URL";
      value = "https://${env.hosts.opencloud}";
    }
    {
      name = "OC_INSECURE";
      value = "false";
    }
    {
      name = "OIDC_ISSUER";
      value = "https://${env.hosts.keycloak}/realms/${env.keycloak.realm}";
    }
    {
      name = "OIDC_CLIENT_ID";
      value = "opendesk-opencloud";
    }
    {
      name = "OIDC_CLIENT_SECRET";
      value = "opencloud-secret-change-me";
    }
    {
      name = "OC_LOG_LEVEL";
      value = "info";
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
    namespace = env.namespaceEdu;
    replicas = env.replicas.default;

    volumeMounts = [
      {
        name = "data";
        mountPath = "/var/lib/opencloud";
      }
      {
        name = "config";
        mountPath = "/etc/opencloud";
        readOnly = true;
      }
    ];

    volumes = [
      {
        name = "data";
        persistentVolumeClaim = {
          claimName = "${name}-data";
        };
      }
      {
        name = "config";
        secret = {
          secretName = "${name}-config";
        };
      }
    ];
  })

  (lib.service {
    inherit name port labels;
    namespace = env.namespaceEdu;
  })

  (lib.ingressWithCert {
    inherit name;
    host = env.hosts.opencloud;
    inherit port;
    inherit (env.ingress) className;
    tlsSecretName = env.tls.secretName;
    annotations = env.ingress.annotations // {
      "haproxy-ingress.github.io/proxy-body-size" = "100M";
      "haproxy-ingress.github.io/timeout-server" = "600s";
      "haproxy-ingress.github.io/timeout-client" = "600s";
    };
    namespace = env.namespaceEdu;
  })

  # PVC storage fix (incident 2026-08-15): switched RWX(ceph-cephfs) -> RWO(ceph-rbd).
  # A single-replica workload on a multi-writer filesystem invited the recurrent
  # BoltDB/Bleve corruption in the search service. NOTE: storageClassName and
  # accessModes are IMMUTABLE on a bound PVC, so to apply this change delete the
  # existing PVC and let it be recreated (OpenCloud regenerates idm/search/nats/
  # storage on startup):
  #   kubectl -n opendesk-edu delete pvc opendesk-opencloud-data
  (lib.pvc {
    name = "${name}-data";
    size = "50Gi";
    storageClass = env.storage.rwo;
    accessModes = [ "ReadWriteOnce" ];
    namespace = env.namespaceEdu;
    inherit labels;
  })

  (lib.secret {
    name = "${name}-config";
    namespace = env.namespaceEdu;
    inherit labels;
    stringData = {
      "opencloud.yaml" = opencloudConfig;
    };
  })

  (lib.secret {
    name = "${name}-db";
    namespace = env.namespaceEdu;
    inherit labels;
    stringData = {
      "oidc-client-secret" = "opencloud-secret-change-me";
    };
  })
]
