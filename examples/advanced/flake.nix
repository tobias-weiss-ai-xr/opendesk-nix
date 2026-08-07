# Advanced Example: Multi-Service Stack
#
# This example shows how to deploy a complete groupware stack with:
# - MariaDB (database)
# - SOGo (groupware)
# - Stalwart (mail server)
# - Ingress for external access
#
# Usage:
#   nix build .#packages.x86_64-linux.groupware-stack
#   kubectl apply -k result/

{
  description = "Advanced openDesk Service Deployment - Groupware Stack";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Import openDesk Edu libraries
        lib = {
          k8s = import ../../lib/k8s.nix { inherit pkgs lib; };
          security = import ../../lib/security.nix { inherit pkgs lib; };
          operators = import ../../lib/operators.nix { inherit pkgs pkgs lib; };
        };

        # ====================================================================
        # Namespace
        # ====================================================================

        namespace = {
          apiVersion = "v1";
          kind = "Namespace";
          metadata = {
            name = "groupware";
            labels = {
              "app.kubernetes.io/part-of" = "opendesk-edu";
              "app.kubernetes.io/component" = "groupware";
            };
          };
        };

        # ====================================================================
        # MariaDB Deployment
        # ====================================================================

        mariadbDeployment = {
          apiVersion = "apps/v1";
          kind = "Deployment";
          metadata = {
            name = "mariadb";
            namespace = "groupware";
            labels = {
              app = "mariadb";
              "app.kubernetes.io/name" = "mariadb";
              "app.kubernetes.io/component" = "database";
            };
          };
          spec = {
            replicas = 1;
            selector.matchLabels.app = "mariadb";
            template = {
              metadata.labels = {
                app = "mariadb";
                "app.kubernetes.io/name" = "mariadb";
              };
              spec = {
                containers = [
                  {
                    name = "mariadb";
                    image = "mariadb:11.4.4";
                    ports = [ { name = "mysql"; containerPort = 3306; } ];
                    env = [
                      { name = "MYSQL_ROOT_PASSWORD"; valueFrom = { secretKeyRef = { name = "mariadb-credentials"; key = "root-password"; }; }; }
                      { name = "MYSQL_DATABASE"; value = "sogo"; }
                      { name = "MYSQL_USER"; value = "sogo"; }
                      { name = "MYSQL_PASSWORD"; valueFrom = { secretKeyRef = { name = "mariadb-credentials"; key = "sogo-password"; }; }; }
                    ];
                    resources = {
                      requests = { memory = "512Mi"; cpu = "250m"; };
                      limits = { memory = "1Gi"; cpu = "1000m"; };
                    };
                    securityContext = {
                      runAsNonRoot = true;
                      runAsUser = 999;
                    };
                    livenessProbe = {
                      tcpSocket.port = 3306;
                      initialDelaySeconds = 30;
                      periodSeconds = 10;
                    };
                    readinessProbe = {
                      tcpSocket.port = 3306;
                      initialDelaySeconds = 5;
                      periodSeconds = 5;
                    };
                  }
                ];
              };
            };
          };
        };

        mariadbService = {
          apiVersion = "v1";
          kind = "Service";
          metadata = {
            name = "mariadb";
            namespace = "groupware";
            labels = {
              app = "mariadb";
              "app.kubernetes.io/name" = "mariadb";
            };
          };
          spec = {
            selector.app = "mariadb";
            type = "ClusterIP";
            ports = [ { name = "mysql"; port = 3306; targetPort = 3306; } ];
          };
        };

        mariadbPVC = {
          apiVersion = "v1";
          kind = "PersistentVolumeClaim";
          metadata = {
            name = "mariadb-data";
            namespace = "groupware";
          };
          spec = {
            accessModes = [ "ReadWriteOnce" ];
            resources.requests.storage = "10Gi";
            storageClassName = "standard";
          };
        };

        mariadbSecret = {
          apiVersion = "v1";
          kind = "Secret";
          metadata = {
            name = "mariadb-credentials";
            namespace = "groupware";
          };
          type = "Opaque";
          stringData = {
            "root-password" = "change-me-in-production";
            "sogo-password" = "change-me-in-production";
          };
        };

        # ====================================================================
        # Stalwart Mail Server
        # ====================================================================

        stalwartDeployment = {
          apiVersion = "apps/v1";
          kind = "Deployment";
          metadata = {
            name = "stalwart";
            namespace = "groupware";
            labels = {
              app = "stalwart";
              "app.kubernetes.io/name" = "stalwart";
              "app.kubernetes.io/component" = "mail";
            };
          };
          spec = {
            replicas = 1;
            selector.matchLabels.app = "stalwart";
            template = {
              metadata.labels = {
                app = "stalwart";
                "app.kubernetes.io/name" = "stalwart";
              };
              spec = {
                containers = [
                  {
                    name = "stalwart";
                    image = "stalwart/stalwart:latest";
                    ports = [
                      { name = "smtp"; containerPort = 8025; }
                      { name = "imap"; containerPort = 8143; }
                      { name = "jmap"; containerPort = 8080; }
                    ];
                    env = [
                      { name = "DB_TYPE"; value = "sqlite"; }
                      { name = "JWT_SECRET"; valueFrom = { secretKeyRef = { name = "stalwart-secrets"; key = "jwt-secret"; }; }; }
                    ];
                    resources = {
                      requests = { memory = "256Mi"; cpu = "100m"; };
                      limits = { memory = "512Mi"; cpu = "500m"; };
                    };
                    securityContext = {
                      runAsNonRoot = true;
                      runAsUser = 1000;
                    };
                  }
                ];
              };
            };
          };
        };

        stalwartService = {
          apiVersion = "v1";
          kind = "Service";
          metadata = {
            name = "stalwart";
            namespace = "groupware";
          };
          spec = {
            selector.app = "stalwart";
            type = "ClusterIP";
            ports = [
              { name = "smtp"; port = 25; targetPort = 8025; }
              { name = "imap"; port = 143; targetPort = 8143; }
              { name = "jmap"; port = 8080; targetPort = 8080; }
            ];
          };
        };

        stalwartSecret = {
          apiVersion = "v1";
          kind = "Secret";
          metadata = {
            name = "stalwart-secrets";
            namespace = "groupware";
          };
          type = "Opaque";
          stringData = {
            "jwt-secret" = "change-me-in-production";
          };
        };

        # ====================================================================
        # SOGo Groupware
        # ====================================================================

        sogoDeployment = {
          apiVersion = "apps/v1";
          kind = "Deployment";
          metadata = {
            name = "sogo";
            namespace = "groupware";
            labels = {
              app = "sogo";
              "app.kubernetes.io/name" = "sogo";
              "app.kubernetes.io/component" = "groupware";
            };
          };
          spec = {
            replicas = 2;
            selector.matchLabels.app = "sogo";
            template = {
              metadata.labels = {
                app = "sogo";
                "app.kubernetes.io/name" = "sogo";
              };
              spec = {
                containers = [
                  {
                    name = "sogo";
                    image = "registry.opencode.de/umr/opendesk-edu/opendesk-nix/sogo6:latest";
                    ports = [ { name = "http"; containerPort = 20000; } ];
                    env = [
                      { name = "SOGoMysqlHost"; value = "mariadb"; }
                      { name = "SOGoMysqlDBName"; value = "sogo"; }
                      { name = "SOGoMysqlUser"; value = "sogo"; }
                      { name = "SOGoMysqlPassword"; valueFrom = { secretKeyRef = { name = "mariadb-credentials"; key = "sogo-password"; }; }; }
                      { name = "SOGoFirstDayOfWeek"; value = "1"; }
                    ];
                    resources = {
                      requests = { memory = "512Mi"; cpu = "250m"; };
                      limits = { memory = "1Gi"; cpu = "1000m"; };
                    };
                    securityContext = {
                      runAsNonRoot = true;
                      runAsUser = 1000;
                    };
                    livenessProbe = {
                      httpGet = { path = "/SOGo/soap"; port = 20000; };
                      initialDelaySeconds = 30;
                      periodSeconds = 10;
                    };
                    readinessProbe = {
                      httpGet = { path = "/SOGo/soap"; port = 20000; };
                      initialDelaySeconds = 10;
                      periodSeconds = 5;
                    };
                  }
                ];
              };
            };
          };
        };

        sogoService = {
          apiVersion = "v1";
          kind = "Service";
          metadata = {
            name = "sogo";
            namespace = "groupware";
          };
          spec = {
            selector.app = "sogo";
            type = "ClusterIP";
            ports = [ { name = "http"; port = 80; targetPort = 20000; } ];
          };
        };

        # ====================================================================
        # Ingress
        # ====================================================================

        ingress = {
          apiVersion = "networking.k8s.io/v1";
          kind = "Ingress";
          metadata = {
            name = "groupware-ingress";
            namespace = "groupware";
            annotations = {
              "kubernetes.io/ingress.class" = "nginx";
              "nginx.ingress.kubernetes.io/ssl-redirect" = "true";
            };
          };
          spec = {
            tls = [
              {
                hosts = [ "groupware.example.org" ];
                secretName = "groupware-tls";
              }
            ];
            rules = [
              {
                host = "groupware.example.org";
                http = {
                  paths = [
                    {
                      path = "/SOGo";
                      pathType = "Prefix";
                      backend = {
                        service.name = "sogo";
                        service.port.number = 80;
                      };
                    }
                  ];
                };
              }
            ];
          };
        };

        # ====================================================================
        # Network Policies
        # ====================================================================

        networkPolicy = {
          apiVersion = "networking.k8s.io/v1";
          kind = "NetworkPolicy";
          metadata = {
            name = "groupware-network-policy";
            namespace = "groupware";
          };
          spec = {
            podSelector = {};
            policyTypes = [ "Ingress" "Egress" ];
            ingress = [
              {
                from = [
                  { namespaceSelector = { matchLabels.name = "ingress-nginx"; } };
                ];
                ports = [
                  { protocol = "TCP"; port = 20000; }  # SOGo
                  { protocol = "TCP"; port = 8025; }   # SMTP
                  { protocol = "TCP"; port = 8143; }   # IMAP
                ];
              }
            ];
            egress = [
              {
                to = [
                  { podSelector = { matchLabels.app = "mariadb"; } };
                ];
                ports = [ { protocol = "TCP"; port = 3306; } ];
              }
              {
                to = [ { namespaceSelector = {}; } ];
                ports = [ { protocol = "UDP"; port = 53; } ];  # DNS
              }
            ];
          };
        };

        # ====================================================================
        # Combined Manifest
        # ====================================================================

        allManifests = pkgs.writeText "groupware-stack.yaml" ''
          ---
          ${builtins.toJSON namespace}
          ---
          ${builtins.toJSON mariadbSecret}
          ---
          ${builtins.toJSON stalwartSecret}
          ---
          ${builtins.toJSON mariadbPVC}
          ---
          ${builtins.toJSON mariadbDeployment}
          ---
          ${builtins.toJSON mariadbService}
          ---
          ${builtins.toJSON stalwartDeployment}
          ---
          ${builtins.toJSON stalwartService}
          ---
          ${builtins.toJSON sogoDeployment}
          ---
          ${builtins.toJSON sogoService}
          ---
          ${builtins.toJSON ingress}
          ---
          ${builtins.toJSON networkPolicy}
        '';

      in {
        packages = {
          # Combined groupware stack
          groupware-stack = allManifests;

          # Individual components
          mariadb = mariadbDeployment;
          stalwart = stalwartDeployment;
          sogo = sogoDeployment;
        };

        default = self.packages.${system}.groupware-stack;

        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.kubectl
            pkgs.kubernetes-helm
            pkgs.yq
            pkgs.kubectx
          ];

          shellHook = ''
            echo "openDesk Edu - Advanced Example"
            echo "================================"
            echo ""
            echo "Groupware Stack Components:"
            echo "  - MariaDB (database)"
            echo "  - Stalwart (mail server)"
            echo "  - SOGo (groupware)"
            echo ""
            echo "Deploy to cluster:"
            echo "  nix build .#groupware-stack"
            echo "  kubectl apply -f result/"
            echo ""
            echo "Verify deployment:"
            echo "  kubectl get pods -n groupware"
            echo "  kubectl get svc -n groupware"
            echo ""
          '';
        };
      });
}
