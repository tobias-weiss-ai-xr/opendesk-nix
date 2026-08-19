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
  secrets ? {},
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

  # Secrets from SOPS-encrypted store (with fallback to current values for
  # backward compatibility). To rotate: add the key to secrets/scs.enc.json
  # and remove the fallback. See platform/nix/secrets.nix.
  cfgSecrets = secrets.opencloud or {};

  # OpenCloud config — generated via `opencloud init --insecure yes`
  # Secrets are externalized via __PLACEHOLDER__ tokens and replaced at
  # build time from the SOPS-encrypted store (see cfgSecrets above).
  opencloudConfig = ''
    token_manager:
      jwt_secret: __JWT_SECRET__
    machine_auth_api_key: __MACHINE_AUTH_API_KEY__
    system_user_api_key: __SYSTEM_USER_API_KEY__
    transfer_secret: __TRANSFER_SECRET__
    url_signing_secret: __URL_SIGNING_SECRET__
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
          bind_password: __LDAP_BIND_PASSWORD__
      service_account:
        service_account_id: 140f97b5-a094-4656-a5b4-59765eb00593
        service_account_secret: __SERVICE_ACCOUNT_SECRET__
    idp:
      ldap:
        bind_password: __IDP_LDAP_BIND_PASSWORD__
    idm:
      service_user_passwords:
        admin_password: __ADMIN_PASSWORD__
        idm_password: __IDM_PASSWORD__
        reva_password: __REVA_PASSWORD__
        idp_password: __IDP_PASSWORD__
    collaboration:
      wopi:
        secret: __WOPI_SECRET__
      app:
        insecure: true
    proxy:
      oidc:
        insecure: true
      insecure_backends: true
      service_account:
        service_account_id: 140f97b5-a094-4656-a5b4-59765eb00593
        service_account_secret: __SERVICE_ACCOUNT_SECRET__
    frontend:
      app_handler:
        insecure: true
      archiver:
        insecure: true
      service_account:
        service_account_id: 140f97b5-a094-4656-a5b4-59765eb00593
        service_account_secret: __SERVICE_ACCOUNT_SECRET__
      ocdav:
        insecure: true
    auth_basic:
      auth_providers:
        ldap:
          bind_password: __REVA_PASSWORD__
    auth_bearer:
      auth_providers:
        oidc:
          insecure: true
    users:
      drivers:
        ldap:
          bind_password: __REVA_PASSWORD__
    groups:
      drivers:
        ldap:
          bind_password: __REVA_PASSWORD__
    ocm:
      service_account:
        service_account_id: 140f97b5-a094-4656-a5b4-59765eb00593
        service_account_secret: __SERVICE_ACCOUNT_SECRET__
    thumbnails:
      thumbnail:
        transfer_secret: __THUMBNAILS_TRANSFER_SECRET__
        webdav_allow_insecure: true
        cs3_allow_insecure: true
    search:
      events:
        tls_insecure: true
      service_account:
        service_account_id: 140f97b5-a094-4656-a5b4-59765eb00593
        service_account_secret: __SERVICE_ACCOUNT_SECRET__
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
        service_account_secret: __SERVICE_ACCOUNT_SECRET__
    storage_users:
      events:
        tls_insecure: true
      mount_id: cc6a315d-5262-488e-a9f0-1cca1463a8bc
      service_account:
        service_account_id: 140f97b5-a094-4656-a5b4-59765eb00593
        service_account_secret: __SERVICE_ACCOUNT_SECRET__
    notifications:
      notifications:
        events:
          tls_insecure: true
      service_account:
        service_account_id: 140f97b5-a094-4656-a5b4-59765eb00593
        service_account_secret: __SERVICE_ACCOUNT_SECRET__
    nats:
      nats:
        tls_skip_verify_client_cert: true
    gateway:
      storage_registry:
        storage_users_mount_id: cc6a315d-5262-488e-a9f0-1cca1463a8bc
    userlog:
      service_account:
        service_account_id: 140f97b5-a094-4656-a5b4-59765eb00593
        service_account_secret: __SERVICE_ACCOUNT_SECRET__
    auth_service:
      service_account:
        service_account_id: 140f97b5-a094-4656-a5b4-59765eb00593
        service_account_secret: __SERVICE_ACCOUNT_SECRET__
    clientlog:
      service_account:
        service_account_id: 140f97b5-a094-4656-a5b4-59765eb00593
        service_account_secret: __SERVICE_ACCOUNT_SECRET__
    activitylog:
      service_account:
        service_account_id: 140f97b5-a094-4656-a5b4-59765eb00593
        service_account_secret: __SERVICE_ACCOUNT_SECRET__
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
      valueFrom = {
        secretKeyRef = {
          name = "opendesk-opencloud-db";
          key = "oidc-client-secret";
        };
      };
    }
    {
      name = "OC_LOG_LEVEL";
      value = "info";
    }
    # OpenCloud 7.x gateway (proxy) defaults to 0.0.0.0:9200 with a generated
    # self-signed TLS cert; the Service/Ingress expect plain HTTP on 8080.
    {
      name = "PROXY_HTTP_ADDR";
      value = "0.0.0.0:8080";
    }
    {
      name = "PROXY_TLS";
      value = "false";
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
    # RWO PVC (opendesk-opencloud-data, ceph-rbd): RollingUpdate can Multi-Attach
    # the volume across nodes during a rollout. Recreate terminates the old pod
    # first so the new pod can exclusively own the ReadWriteOnce volume.
    strategyType = "Recreate";

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
      "opencloud.yaml" = builtins.replaceStrings
        [
          "__SERVICE_ACCOUNT_SECRET__"
          "__JWT_SECRET__"
          "__MACHINE_AUTH_API_KEY__"
          "__SYSTEM_USER_API_KEY__"
          "__TRANSFER_SECRET__"
          "__URL_SIGNING_SECRET__"
          "__LDAP_BIND_PASSWORD__"
          "__IDP_LDAP_BIND_PASSWORD__"
          "__ADMIN_PASSWORD__"
          "__IDM_PASSWORD__"
          "__REVA_PASSWORD__"
          "__IDP_PASSWORD__"
          "__WOPI_SECRET__"
          "__THUMBNAILS_TRANSFER_SECRET__"
        ]
        [
          cfgSecrets.service_account_secret or "__CHANGE_ME__"
          cfgSecrets.jwt_secret or "CIU$waQwS+2%.@xDqY!Dbq!Ry.C!dXjX"
          cfgSecrets.machine_auth_api_key or "1=W3EAf5#v4oG4Gjn2SL%btSFZ.9R3nV"
          cfgSecrets.system_user_api_key or "mGn9+jkGijzA*r6ePdBQgHu7Q5ZuEItU"
          cfgSecrets.transfer_secret or "6pG*e-z#oszAI=c@az=G$hAD-6LVwMOs"
          cfgSecrets.url_signing_secret or "B*wR*fbqz6ZWipcjcTZEfHKhRxG-U&8p"
          cfgSecrets.ldap_bind_password or "H@S^M57vsVro6ElM+d!YH8rRW&F6*8Sn"
          cfgSecrets.idp_ldap_bind_password or "KYZhAv2ytqjZkHP*+ND2CLk96G-p%=s."
          cfgSecrets.admin_password or "admin"
          cfgSecrets.idm_password or "H@S^M57vsVro6ElM+d!YH8rRW&F6*8Sn"
          cfgSecrets.reva_password or "*%HWwspN1rGKgJjP1oDs6nHxhaS43Zru"
          cfgSecrets.idp_password or "KYZhAv2ytqjZkHP*+ND2CLk96G-p%=s."
          cfgSecrets.wopi_secret or "=u*@HT7agxou9mZ9a.XhUtI^3sfrt3A*"
          cfgSecrets.thumbnails_transfer_secret or "71C&8-4ny&q4Xfk+fx.gOafD2B&NTGGc"
        ]
        opencloudConfig;
    };
  })

  (lib.secret {
    name = "${name}-db";
    namespace = env.namespaceEdu;
    inherit labels;
    stringData = {
      "oidc-client-secret" = cfgSecrets.oidc_client_secret or "opencloud-secret-change-me";
    };
  })
]
