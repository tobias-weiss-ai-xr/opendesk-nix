# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# SCS K3s Cluster Environment Configuration
# Target: SCS K3s cluster (clrz14-06/07/08)
# Storage: Ceph CSI (ceph-rbd for RWO, ceph-cephfs for RWX)
# Ingress: HAProxy
# Registry: Local at 172.26.24.6:5001 (air-gapped, containerd mirror)

_:

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
    rwo = "ceph-rbd"; # ReadWriteOnce (block)
    rwx = "ceph-cephfs"; # ReadWriteMany (shared)
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
    dns = [
      "8.8.8.8"
      "8.8.4.4"
    ];
    noProxy = [
      "127.0.0.1"
      "10.0.0.0/8"
      "172.16.0.0/12"
      "172.26.24.0/24"
      "192.168.0.0/16"
    ];
  };

  # Resource profiles
  resources = {
    small = {
      cpu = "100m";
      memory = "128Mi";
    };
    medium = {
      cpu = "250m";
      memory = "512Mi";
    };
    large = {
      cpu = "500m";
      memory = "1Gi";
    };
    database = {
      cpu = "500m";
      memory = "1Gi";
    };
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

    # Realm bootstrap model — pure DATA for the keycloak-bootstrap Job
    # (platform/kubernetes/services/keycloak-bootstrap.nix). The Job renders
    # this into an idempotent kcadm.sh script (get-or-create everywhere), so
    # the provisioning spec lives here as data, not in the script code.
    bootstrap = {
      # Admin user of the master realm (password: sealed keycloak-db secret,
      # key `admin-password`, mounted read-only at /mnt/secrets-admin).
      adminUser = "admin";

      # The `opendesk` realm (currently MISSING — only `master` exists).
      realm = {
        realm = "opendesk";
        enabled = true;
        sslRequired = "external";
      };

      # OpenLDAP user federation (see Appendix A: openldap.opendesk-edu,
      # base dc=opendesk-edu,dc=org, admin cn=admin / adminpassword).
      # Keycloak component config values are string arrays.
      ldap = {
        name = "openldap";
        providerId = "ldap";
        providerType = "org.keycloak.storage.UserStorageProvider";
        config = {
          vendor = [ "ldap" ];
          enabled = [ "true" ];
          usernameLDAPAttribute = [ "uid" ];
          rdnLDAPAttribute = [ "uid" ];
          uuidLDAPAttribute = [ "entryUUID" ];
          userObjectClasses = [ "inetOrgPerson, posixAccount" ];
          connectionUrl = [ "ldap://openldap.opendesk-edu.svc.cluster.local:389" ];
          usersDn = [ "ou=people,dc=opendesk-edu,dc=org" ];
          bindDn = [ "cn=admin,dc=opendesk-edu,dc=org" ];
          bindCredential = [ "adminpassword" ];
          authType = [ "simple" ];
          searchScope = [ "1" ];
          useTruststoreSpi = [ "ldapsOnly" ];
          connectionPooling = [ "false" ];
          importEnabled = [ "true" ];
          syncRegistrations = [ "false" ];
          editMode = [ "READ_ONLY" ];
          cachePolicy = [ "DEFAULT" ];
        };
      };

      # Protocol mappers attached to EVERY client (same for all).
      protocolMappers = [
        {
          name = "opendesk_username";
          protocolMapper = "oidc-usermodel-attribute-mapper";
          config = {
            "user.attribute" = "uid";
            "claim.name" = "opendesk_username";
            "id.token.claim" = "true";
            "access.token.claim" = "true";
            "userinfo.token.claim" = "true";
            "jsonType.label" = "String";
          };
        }
        {
          name = "opendesk_useruuid";
          protocolMapper = "oidc-usermodel-attribute-mapper";
          config = {
            "user.attribute" = "entryUUID";
            "claim.name" = "opendesk_useruuid";
            "id.token.claim" = "true";
            "access.token.claim" = "true";
            "userinfo.token.claim" = "true";
            "jsonType.label" = "String";
          };
        }
      ];

      # OIDC clients. `secretKey` is the key inside the sealed
      # `keycloak-clients` Secret (mounted at /mnt/secrets). The opencloud
      # value matches the existing sealed secret
      # opendesk-opencloud-db / oidc-client-secret ("opencloud-secret-change-me").
      clients = [
        {
          clientId = "opendesk-intercom";
          secretKey = "intercom-client-secret";
          redirectUris = [ "https://intercom.home.opendesk-edu.org/callback" ];
          attributes = {
            "use.refresh.tokens" = true;
            "backchannel.logout.session.required" = true;
            "standard.token.exchange.enabled" = true;
            "standard.token.exchange.enableRefreshRequestedTokenType" = "SAME_SESSION";
            "backchannel.logout.revoke.offline.tokens" = true;
            "backchannel.logout.url" = "https://intercom.home.opendesk-edu.org/backchannel-logout";
          };
          mappers = [
            {
              name = "intercom-audience";
              protocolMapper = "oidc-audience-mapper";
              config = {
                "included.client.audience" = "opendesk-intercom";
                "access.token.claim" = "true";
                "id.token.claim" = "false";
              };
            }
          ];
        }
        {
          clientId = "opendesk-opencloud";
          secretKey = "opencloud-client-secret";
          redirectUris = [ "https://cloud.home.opendesk-edu.org/*" ];
          attributes = {
            "use.refresh.tokens" = true;
            "standard.token.exchange.enabled" = true;
          };
        }
        {
          clientId = "opendesk-matrix";
          secretKey = "matrix-client-secret";
          redirectUris = [ "https://matrix.home.opendesk-edu.org/_synapse/client/oidc/callback" ];
          attributes = {
            "use.refresh.tokens" = true;
            "backchannel.logout.session.required" = true;
          };
        }
        {
          clientId = "opendesk-sogo";
          secretKey = "sogo-client-secret";
          redirectUris = [ "https://mail.home.opendesk-edu.org/SOGo/oidc/callback" ];
          attributes = {
            "use.refresh.tokens" = true;
          };
        }
      ];
    };
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
