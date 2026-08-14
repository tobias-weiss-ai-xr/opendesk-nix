# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# SOGo — Groupware (Mail, Calendar, Contacts)
# Uses shared Galera cluster for database
# Image: docker.io/weissto/sogo:bookworm-5.12.9

{
  lib,
  env ? import ../environments/scs/default.nix { inherit lib; },
  ...
}:

let
  name = "sogo";
  image = "docker.io/weissto/sogo";
  tag = "bookworm-5.12.9";
  port = 20000;

  labels = lib.mkLabels { inherit name; } // {
    "app.kubernetes.io/component" = "groupware";
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
    type = "http";
    inherit port;
    path = "/SOGo/";
    initialDelaySeconds = 60;
    periodSeconds = 15;
    failureThreshold = 5;
  };

  readinessProbe = lib.mkProbe {
    type = "http";
    inherit port;
    path = "/SOGo/";
    initialDelaySeconds = 15;
    periodSeconds = 5;
    failureThreshold = 3;
  };

  sogoConfig = ''
    {
      WOPort = "0.0.0.0:${toString port}";
      WOListenQueueSize = 5;
      SxVMemLimit = 400;
      SOGoMemcachedHost = "memcached.opendesk.svc.cluster.local:11211";
      SOGoProfileURL = "mysql://${db.sogo.user}:${db.sogo.password}@${db.host}:${toString db.port}/${db.sogo.name}/sogo_user_profile";
      OCSAclURL = "mysql://${db.sogo.user}:${db.sogo.password}@${db.host}:${toString db.port}/${db.sogo.name}/sogo_acl";
      OCSFolderInfoURL = "mysql://${db.sogo.user}:${db.sogo.password}@${db.host}:${toString db.port}/${db.sogo.name}/sogo_folder_profile";
      OCSSessionsFolderURL = "mysql://${db.sogo.user}:${db.sogo.password}@${db.host}:${toString db.port}/${db.sogo.name}/sogo_sessions_folder";
      SOGoIMAPServer = "imaps://stalwart-stalwart.opendesk-edu.svc.cluster.local:993";
      SOGoSMTPServer = "smtp://stalwart-stalwart.opendesk-edu.svc.cluster.local:587";
      SOGoSieveServer = "sieve://stalwart-stalwart.opendesk-edu.svc.cluster.local:4190";
      SOGoMailDomain = "${env.ingress.domain}";
      SOGoLanguage = "English";
      SOGoTimeZone = "Europe/Berlin";
      SOGoFirstDayOfWeek = 1;
      SOGoFirstWeekOfYear = 1;
      SOGoSieveScriptsEnabled = YES;
      SOGoSieveFolderEncoding = "UTF-8";
      SOGoAppointmentSendEMailNotifications = NO;
      SOGoEnableEMailAlarms = YES;
      SOGoBusyFollowersEnabled = NO;
      SOGoUIAdditionalJSFiles = ();
      WOWorkersCount = 5;
      WOLogFile = "/var/log/sogo/sogo.log";
      SOGoDebugMessagesEnabled = NO;
      SOGoDefaultCalendar = "personal";
      SOGoDefaultLanguage = "English";
    }
  '';

  containerEnv = [
    {
      name = "DB_HOST";
      value = db.host;
    }
    {
      name = "DB_PORT";
      value = toString db.port;
    }
    {
      name = "DB_NAME";
      value = db.sogo.name;
    }
    {
      name = "DB_USER";
      value = db.sogo.user;
    }
    {
      name = "DB_PASSWORD";
      value = db.sogo.password;
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
        name = "config";
        mountPath = "/etc/sogo/sogo.conf";
        subPath = "sogo.conf";
        readOnly = true;
      }
      {
        name = "data";
        mountPath = "/var/spool/sogo";
      }
    ];

    volumes = [
      {
        name = "config";
        configMap = {
          name = "${name}-config";
          items = [
            {
              key = "sogo.conf";
              path = "sogo.conf";
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
  })

  (lib.ingressWithCert {
    inherit name;
    host = env.hosts.sogo;
    inherit port;
    inherit (env.ingress) className;
    tlsSecretName = env.tls.secretName;
    annotations = env.ingress.annotations // {
      "haproxy-ingress.github.io/proxy-body-size" = "50M";
      "haproxy-ingress.github.io/timeout-server" = "300s";
    };
    namespace = env.namespaceEdu;
  })

  (lib.configMap {
    name = "${name}-config";
    namespace = env.namespaceEdu;
    inherit labels;
    data = {
      "sogo.conf" = sogoConfig;
    };
  })

  (lib.pvc {
    name = "${name}-data";
    size = "5Gi";
    storageClass = env.storage.rwo;
    accessModes = [ "ReadWriteOnce" ];
    namespace = env.namespaceEdu;
    inherit labels;
  })
]
