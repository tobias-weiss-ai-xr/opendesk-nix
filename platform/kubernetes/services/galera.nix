# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Galera Cluster (MariaDB multi-master) — universal SQL database for all openDesk services.
# Deployed as a 3-node StatefulSet on the SCS K3s cluster.
# Each service (keycloak, synapse, sogo, opencloud) gets its own database within this cluster.
#
# Image: library/mariadb:11.4.4 (includes Galera wsrep provider)
# Storage: ceph-rbd (RWO, one PV per replica via volumeClaimTemplates)
# Topology: 3 replicas (one per K3s node: clrz14-06, clrz14-07, clrz14-08)

{ lib, env ? import ../environments/scs/default.nix { inherit lib; }, ... }:

let
  name = "galera";
  image = "docker.io/library/mariadb";
  tag = "11.4.4";
  port = 3306;

  replicas = env.replicas.galera or 3;
  storageClass = env.storage.rwo;
  storageSize = "20Gi";

  labels = lib.mkLabels { inherit name; } // {
    "app.kubernetes.io/component" = "database";
    "app.kubernetes.io/managed-by" = "nix";
  };

  # Galera configuration
  wsrepClusterName = "opendesk-galera";
  wsrepClusterAddress = "gcomm://galera-0.galera-headless." + env.namespace + ".svc.cluster.local:4567,galera-1.galera-headless." + env.namespace + ".svc.cluster.local:4567,galera-2.galera-headless." + env.namespace + ".svc.cluster.local:4567";

  # Database init SQL — creates databases and users for all services
  initSql = ''
    -- Galera cluster initialization
    -- Databases for all openDesk services
    CREATE DATABASE IF NOT EXISTS keycloak CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    CREATE DATABASE IF NOT EXISTS synapse CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    CREATE DATABASE IF NOT EXISTS sogo CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    CREATE DATABASE IF NOT EXISTS opencloud CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

    -- Service users
    CREATE USER IF NOT EXISTS 'keycloak'@'%' IDENTIFIED BY 'keycloak-db-password-change-me';
    GRANT ALL PRIVILEGES ON keycloak.* TO 'keycloak'@'%';

    CREATE USER IF NOT EXISTS 'synapse'@'%' IDENTIFIED BY 'synapse-db-password-change-me';
    GRANT ALL PRIVILEGES ON synapse.* TO 'synapse'@'%';

    CREATE USER IF NOT EXISTS 'sogo'@'%' IDENTIFIED BY 'sogo-db-password-change-me';
    GRANT ALL PRIVILEGES ON sogo.* TO 'sogo'@'%';

    CREATE USER IF NOT EXISTS 'opencloud'@'%' IDENTIFIED BY 'opencloud-db-password-change-me';
    GRANT ALL PRIVILEGES ON opencloud.* TO 'opencloud'@'%';

    FLUSH PRIVILEGES;
  '';

  # Galera my.cnf configuration
  galeraConfig = ''
    [mysqld]
    # Galera settings
    wsrep_on=ON
    wsrep_provider=/usr/lib/galera/libgalera_smm.so
    wsrep_cluster_name="opendesk-galera"
    wsrep_cluster_address="${wsrepClusterAddress}"
    wsrep_sst_method=rsync
    wsrep_sst_auth=root:ChangeMeGalera123!

    # Binlog
    binlog_format=ROW
    default_storage_engine=InnoDB
    innodb_autoinc_lock_mode=2
    innodb_flush_log_at_trx_commit=0
    innodb_buffer_pool_size=512M

    # Character set
    character-set-server=utf8mb4
    collation-server=utf8mb4_unicode_ci

    # Networking
    bind-address=0.0.0.0
    port=3306

    # Galera ports
    wsrep_provider_options="gmcast.listen_addr=tcp://0.0.0.0:4567;pc.recovery=TRUE"

    # SST (receive address set automatically by Galera)
    wsrep_sst_receive_address=AUTO

    # Logging
    log_error=stderr
    slow_query_log=OFF

    # Safety
    skip-name-resolve=ON
    max_connections=200
  '';

  # Bootstrap script — pod 0 bootstraps new cluster, others join
  bootstrapScript = ''
    #!/bin/bash
    set -e
    ORDINAL=$(hostname | rev | cut -d'-' -f1 | rev)
    echo "Galera pod ordinal: $ORDINAL"

    if [ "$ORDINAL" = "0" ]; then
      # Pod 0: check if we need to bootstrap a new cluster
      if [ ! -f /var/lib/mysql/grastate.dat ]; then
        # First boot: no grastate.dat, bootstrap new cluster with empty address
        echo "Bootstrap: galera-0 first boot, starting new cluster (gcomm://)"
        exec docker-entrypoint.sh mariadbd --wsrep-new-cluster --wsrep-cluster-address=gcomm://
      elif grep -q "safe_to_bootstrap: 1" /var/lib/mysql/grastate.dat; then
        # Cluster was stopped, this node is safe to bootstrap
        echo "Bootstrap: galera-0 starting new cluster (safe_to_bootstrap=1)"
        exec docker-entrypoint.sh mariadbd --wsrep-new-cluster --wsrep-cluster-address=gcomm://
      else
        # Normal start: join existing cluster
        echo "Galera-0: starting normally, joining cluster"
        exec docker-entrypoint.sh mariadbd
      fi
    else
      # Pod 1+: join existing cluster
      echo "Galera-$ORDINAL: joining cluster"
      exec docker-entrypoint.sh mariadbd
    fi
  '';

  # Security context for MariaDB (needs to run as root/mysql user)
  dbSecurityContext = {
    allowPrivilegeEscalation = false;
    runAsNonRoot = false;
    readOnlyRootFilesystem = false;
  };

  dbPodSecurityContext = {
    runAsNonRoot = false;
    fsGroup = 999;
    fsGroupChangePolicy = "OnRootMismatch";
  };

  resources = {
    requests = { cpu = "250m"; memory = "512Mi"; };
    limits = { cpu = "2"; memory = "4Gi"; };
  };

  livenessProbe = lib.mkProbe {
    type = "exec";
    path = "mariadb-admin ping -h localhost -u root -p'ChangeMeGalera123!' 2>/dev/null || exit 1";
    initialDelaySeconds = 180;
    periodSeconds = 15;
    failureThreshold = 10;
  };

  readinessProbe = lib.mkProbe {
    type = "exec";
    path = "mariadb -h localhost -u root -p'ChangeMeGalera123!' -e 'SELECT 1' 2>/dev/null || exit 1";
    initialDelaySeconds = 30;
    periodSeconds = 10;
    failureThreshold = 6;
  };

  # Pod anti-affinity: one Galera pod per node
  podAntiAffinity = {
    podAntiAffinity = {
      requiredDuringSchedulingIgnoredDuringExecution = [{
        labelSelector = {
          matchLabels = { app = name; };
        };
        topologyKey = "kubernetes.io/hostname";
      }];
    };
  };

in [
  # ===================================================================
  # StatefulSet (3 replicas, one per node)
  # ===================================================================
  (lib.statefulset {
    inherit name image tag port resources;
    replicas = replicas;
    securityContext = dbSecurityContext;
    podSecurityContext = dbPodSecurityContext;
    liveness = livenessProbe;
    readiness = readinessProbe;
    labels = labels;
    namespace = env.namespace;
    serviceName = "${name}-headless";
    affinity = podAntiAffinity;

    ports = [
      { containerPort = 3306; name = "mysql"; protocol = "TCP"; }
      { containerPort = 4567; name = "galera"; protocol = "TCP"; }
      { containerPort = 4568; name = "galera-sst"; protocol = "TCP"; }
      { containerPort = 4569; name = "galera-ist"; protocol = "TCP"; }
    ];

    env = [
      { name = "MYSQL_ROOT_PASSWORD"; value = "ChangeMeGalera123!"; }
      { name = "MARIADB_ROOT_PASSWORD"; value = "ChangeMeGalera123!"; }
      { name = "MARIADB_AUTO_UPGRADE"; value = "1"; }
    ];

    command = [ "/bin/bash" "/scripts/bootstrap.sh" ];

    volumeMounts = [
      { name = "data"; mountPath = "/var/lib/mysql"; }
      { name = "config"; mountPath = "/etc/mysql/conf.d"; readOnly = true; }
      { name = "initdb"; mountPath = "/docker-entrypoint-initdb.d"; readOnly = true; }
      { name = "scripts"; mountPath = "/scripts"; readOnly = true; }
    ];

    volumes = [
      { name = "config"; configMap = { name = "${name}-config"; }; }
      { name = "initdb"; configMap = { name = "${name}-initdb"; }; }
      { name = "scripts"; configMap = { name = "${name}-bootstrap"; defaultMode = 493; }; }
    ];

    # Per-pod PVC via volumeClaimTemplates
    volumeClaims = [{
      metadata = { name = "data"; };
      spec = {
        accessModes = [ "ReadWriteOnce" ];
        storageClassName = storageClass;
        resources = {
          requests = { storage = storageSize; };
        };
      };
    }];

    terminationGracePeriodSeconds = 300;
    podManagementPolicy = "OrderedReady";
  })

  # ===================================================================
  # Headless Service (for Galera cluster discovery)
  # ===================================================================
  (lib.headlessService {
    inherit name;
    port = 3306;
    labels = labels;
    namespace = env.namespace;
    ports = [
      { port = 3306; targetPort = 3306; protocol = "TCP"; name = "mysql"; }
      { port = 4567; targetPort = 4567; protocol = "TCP"; name = "galera"; }
      { port = 4568; targetPort = 4568; protocol = "TCP"; name = "galera-sst"; }
      { port = 4569; targetPort = 4569; protocol = "TCP"; name = "galera-ist"; }
    ];
  })

  # ===================================================================
  # Client Service (for applications to connect)
  # ===================================================================
  (lib.service {
    inherit name;
    port = 3306;
    labels = labels;
    namespace = env.namespace;
    type = "ClusterIP";
  })

  # ===================================================================
  # ConfigMap — Galera configuration
  # ===================================================================
  (lib.configMap {
    name = "${name}-config";
    namespace = env.namespace;
    labels = labels;
    data = {
      "galera.cnf" = galeraConfig;
    };
  })

  # ===================================================================
  # ConfigMap — Database initialization SQL
  # ===================================================================
  (lib.configMap {
    name = "${name}-initdb";
    namespace = env.namespace;
    labels = labels;
    data = {
      "01-init-databases.sql" = initSql;
    };
  })

  # ===================================================================
  # ConfigMap — Bootstrap script
  # ===================================================================
  (lib.configMap {
    name = "${name}-bootstrap";
    namespace = env.namespace;
    labels = labels;
    data = {
      "bootstrap.sh" = bootstrapScript;
    };
  })

  # ===================================================================
  # Secret — Galera credentials
  # ===================================================================
  (lib.secret {
    name = "${name}-secrets";
    namespace = env.namespace;
    labels = labels;
    stringData = {
      "mysql-root-password" = "ChangeMeGalera123!";
      "mariadb-root-password" = "ChangeMeGalera123!";
      "galera-cluster-name" = wsrepClusterName;
    };
  })

  # ===================================================================
  # PodDisruptionBudget (ensure quorum)
  # ===================================================================
  (lib.pdb {
    name = name;
    namespace = env.namespace;
    labels = labels;
    minAvailable = 2;
    selector = { app = name; };
  })

  # ===================================================================
  # NetworkPolicy — allow traffic from opendesk and opendesk-edu namespaces
  # ===================================================================
  (lib.networkPolicy {
    name = "${name}-allow-opendesk";
    namespace = env.namespace;
    labels = labels;
    podSelector = { app = name; };
    policyTypes = [ "Ingress" ];
    ingress = [{
      from = [
        { namespaceSelector = { matchLabels = { "kubernetes.io/metadata.name" = env.namespace; }; }; }
        { namespaceSelector = { matchLabels = { "kubernetes.io/metadata.name" = env.namespaceEdu; }; }; }
      ];
      ports = [
        { protocol = "TCP"; port = 3306; }
        { protocol = "TCP"; port = 4567; }
        { protocol = "TCP"; port = 4568; }
        { protocol = "TCP"; port = 4569; }
      ];
    }];
  })
]
