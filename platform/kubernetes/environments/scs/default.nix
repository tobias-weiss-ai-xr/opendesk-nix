# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# SCS K3s Cluster Environment Configuration
# Target: SCS K3s cluster (clrz14-06/07/08)
# Storage: Ceph CSI (ceph-rbd for RWO, ceph-cephfs for RWX)
# Ingress: HAProxy
# Registry: Local at 172.26.24.6:5001 (air-gapped, containerd mirror)

{ lib, ... }:

{
  # Cluster identity
  name = "scs";
  namespace = "opendesk";
  namespaceEdu = "opendesk-edu";

  # Ingress configuration
  ingress = {
    className = "haproxy";
    domain = "home.opendesk-edu.org";
    annotations = {
      "haproxy-ingress.github.io/ssl-redirect" = "true";
      "haproxy-ingress.github.io/timeout-server" = "300s";
    };
  };

  # TLS configuration
  tls = {
    enabled = true;
    secretName = "opendesk-certificates-tls";
    issuer = "self-signed";
  };

  # Storage classes (Ceph CSI on SCS cluster)
  storage = {
    rwo = "ceph-rbd";       # ReadWriteOnce (block)
    rwx = "ceph-cephfs";    # ReadWriteMany (shared)
    defaultClass = "ceph-rbd";
  };

  # Image registry (local, air-gapped)
  # containerd auto-mirrors docker.io, quay.io, ghcr.io → localhost:5001
  # Use original image names (e.g. docker.io/matrixdotorg/synapse) — do NOT prefix with registry
  registry = {
    url = "172.26.24.6:5001";
    insecure = true;
    mirror = true;
    # Original image names are used; containerd redirects to local registry
    useOriginalNames = true;
  };

  # Database (Galera cluster)
  database = {
    type = "galera";
    host = "galera-headless";
    port = 3306;
    # Each service gets its own database within the shared Galera cluster
    rootPassword = "ChangeMeGalera123!";
    # Service databases
    keycloak = {
      name = "keycloak";
      user = "keycloak";
      password = "keycloak-db-password-change-me";
    };
    synapse = {
      name = "synapse";
      user = "synapse";
      password = "synapse-db-password-change-me";
    };
    sogo = {
      name = "sogo";
      user = "sogo";
      password = "sogo-db-password-change-me";
    };
    opencloud = {
      name = "opencloud";
      user = "opencloud";
      password = "opencloud-db-password-change-me";
    };
  };

  # Networking
  networking = {
    proxy = "";
    dns = [ "8.8.8.8" "8.8.4.4" ];
    noProxy = [ "127.0.0.1" "10.0.0.0/8" "172.16.0.0/12" "172.26.24.0/24" "192.168.0.0/16" ];
  };

  # Resource profiles
  resources = {
    small = { cpu = "100m"; memory = "128Mi"; };
    medium = { cpu = "250m"; memory = "512Mi"; };
    large = { cpu = "500m"; memory = "1Gi"; };
    database = { cpu = "500m"; memory = "1Gi"; };
  };

  # Replica counts
  replicas = {
    min = 1;
    max = 3;
    default = 1;
    galera = 1;
  };

  # Monitoring
  monitoring = {
    enabled = false;
    prometheus = false;
    grafana = false;
  };

  # Security
  security = {
    podSecurityAdmission = "baseline";
    networkPolicies = true;
    readOnlyRootFilesystem = false;
  };

  # Keycloak / OIDC
  keycloak = {
    host = "id.home.opendesk-edu.org";
    realm = "opendesk";
    url = "https://id.home.opendesk-edu.org";
    internalUrl = "http://keycloak.opendesk.svc.cluster.local:8080";
  };

  # Service hosts
  hosts = {
    keycloak = "id.home.opendesk-edu.org";
    matrix = "matrix.home.opendesk-edu.org";
    element = "chat.home.opendesk-edu.org";
    sogo = "mail.home.opendesk-edu.org";
    stalwart = "mail.home.opendesk-edu.org";
    opencloud = "cloud.home.opendesk-edu.org";
  };
}
