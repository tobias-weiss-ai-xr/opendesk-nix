# Basic Example: Single Service Deployment
#
# This example shows how to deploy a single service (MariaDB) to Kubernetes
# using openDesk Edu libraries.
#
# Usage:
#   nix build .#packages.x86_64-linux.mariadb-deployment
#   kubectl apply -f result/

{
  description = "Basic openDesk Service Deployment - Single MariaDB";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Import openDesk Edu libraries

        # Simple function to create deployment
        mkDeployment = { name, image, ports, resources ? { } }: {
          apiVersion = "apps/v1";
          kind = "Deployment";
          metadata = {
            inherit name;
            labels = {
              app = name;
              "app.kubernetes.io/name" = name;
            };
          };
          spec = {
            replicas = 1;
            selector.matchLabels.app = name;
            template = {
              metadata.labels.app = name;
              spec = {
                containers = [{
                  inherit name image;
                  ports = map (p: { inherit (p) containerPort; }) ports;
                  resources = if resources != { } then {
                    requests = {
                      memory = resources.memory or "256Mi";
                      cpu = resources.cpu or "100m";
                    };
                    limits = {
                      memory = resources.memoryLimit or "512Mi";
                      cpu = resources.cpuLimit or "500m";
                    };
                  } else
                    { };
                  securityContext = {
                    runAsNonRoot = true;
                    runAsUser = 999;
                    readOnlyRootFilesystem = true;
                  };
                }];
              };
            };
          };
        };

        # Simple function to create service
        mkService = { name, ports }: {
          apiVersion = "v1";
          kind = "Service";
          metadata = {
            inherit name;
            labels = {
              app = name;
              "app.kubernetes.io/name" = name;
            };
          };
          spec = {
            selector.app = name;
            type = "ClusterIP";
            ports = map (p: {
              inherit (p) name port;
              targetPort = p.port;
            }) ports;
          };
        };

        # MariaDB configuration
        mariadb = {
          name = "mariadb";
          image = "mariadb:11.4.4";
          ports = [{
            name = "mysql";
            port = 3306;
          }];
          resources = {
            memory = "512Mi";
            cpu = "250m";
            memoryLimit = "1Gi";
            cpuLimit = "1000m";
          };
        };

        # Generate manifests
        mariadbDeployment = mkDeployment mariadb;
        mariadbService = mkService mariadb;

      in {
        packages = {
          # MariaDB deployment manifest
          mariadb-deployment = pkgs.writeText "mariadb-deployment.yaml"
            (builtins.toJSON mariadbDeployment);

          # MariaDB service manifest
          mariadb-service = pkgs.writeText "mariadb-service.yaml"
            (builtins.toJSON mariadbService);

          # Combined manifest
          mariadb-all = pkgs.writeText "mariadb-all.yaml" ''
            ---
            ${builtins.toJSON mariadbDeployment}
            ---
            ${builtins.toJSON mariadbService}
          '';
        };

        # Default package
        default = self.packages.${system}.mariadb-all;

        devShells.default = pkgs.mkShell {
          buildInputs = [ pkgs.kubectl pkgs.kubernetes-helm pkgs.yq ];

          shellHook = ''
            echo "openDesk Edu - Basic Example"
            echo "============================="
            echo ""
            echo "Available packages:"
            echo "  - mariadb-deployment: MariaDB Deployment manifest"
            echo "  - mariadb-service: MariaDB Service manifest"
            echo "  - mariadb-all: Combined manifest"
            echo ""
            echo "Deploy to cluster:"
            echo "  nix build .#mariadb-all"
            echo "  kubectl apply -f result/"
            echo ""
          '';
        };
      });
}
