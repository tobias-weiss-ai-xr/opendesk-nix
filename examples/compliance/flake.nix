# Compliance Example: ZKI-IT-Grundschutz Setup
#
# This example demonstrates how to deploy Kyverno policies for
# ZKI-IT-Grundschutz compliance automation.
#
# Usage:
#   nix build .#packages.x86_64-linux.compliance-policies
#   kubectl apply -f result/

{
  description = "Compliance Example - ZKI-IT-Grundschutz Kyverno Policies";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # ====================================================================
        # Kyverno ClusterPolicies for ZKI Compliance
        # ====================================================================

        # INF.1.A10: Zugriffskontrolle - Require non-root containers
        requireNonRootPolicy = {
          apiVersion = "kyverno.io/v1";
          kind = "ClusterPolicy";
          metadata = {
            name = "require-non-root";
            labels = {
              "app.kubernetes.io/part-of" = "opendesk-edu";
              "compliance.zki.org/id" = "INF.1.A10";
            };
            annotations = {
              "policies.kyverno.io/title" = "Require Non-Root Containers";
              "policies.kyverno.io/category" = "ZKI Compliance";
              "policies.kyverno.io/description" =
                "Containers should run as non-root users to prevent privilege escalation.";
            };
          };
          spec = {
            validationFailureAction = "enforce";
            background = true;
            rules = [
              {
                name = "run-as-non-root";
                match = {
                  any = [
                    {
                      resources = {
                        kinds = [
                          "Pod"
                          "Deployment"
                          "StatefulSet"
                          "DaemonSet"
                        ];
                      };
                    }
                  ];
                };
                validate = {
                  message = "Containers must run as non-root user. Set securityContext.runAsNonRoot to true.";
                  pattern = {
                    spec = {
                      securityContext = {
                        runAsNonRoot = true;
                      };
                    };
                  };
                };
              }
            ];
          };
        };

        # INF.5.A1: Netzwerksicherheit - Require Network Policies
        requireNetworkPolicyPolicy = {
          apiVersion = "kyverno.io/v1";
          kind = "ClusterPolicy";
          metadata = {
            name = "require-network-policy";
            labels = {
              "app.kubernetes.io/part-of" = "opendesk-edu";
              "compliance.zki.org/id" = "INF.5.A1";
            };
            annotations = {
              "policies.kyverno.io/title" = "Require Network Policies";
              "policies.kyverno.io/category" = "ZKI Compliance";
              "policies.kyverno.io/description" =
                "All namespaces must have network policies defined for network segmentation.";
            };
          };
          spec = {
            validationFailureAction = "audit";
            background = true;
            rules = [
              {
                name = "check-network-policy";
                context = [
                  {
                    name = "namespace";
                    variable = {
                      jmesPath = "request.object.metadata.namespace";
                    };
                  }
                  {
                    name = "networkPolicies";
                    apiCall = {
                      urlPath = "/apis/networking.k8s.io/v1/namespaces/${namespace}/networkpolicies";
                    };
                  }
                ];
                preconditions = {
                  all = [
                    {
                      key = "{{request.operation}}";
                      operator = "NotEquals";
                      values = [ "DELETE" ];
                    }
                  ];
                };
                validate = {
                  message = "Namespace must have at least one network policy defined.";
                  pattern = {
                    spec = {
                      networkPolicyCount = "{{networkPolicies.items | length(@)}}";
                    };
                  };
                };
              }
            ];
          };
        };

        # INF.1.A15: Audit - Require Resource Labels
        requireLabelsPolicy = {
          apiVersion = "kyverno.io/v1";
          kind = "ClusterPolicy";
          metadata = {
            name = "require-resource-labels";
            labels = {
              "app.kubernetes.io/part-of" = "opendesk-edu";
              "compliance.zki.org/id" = "INF.1.A15";
            };
            annotations = {
              "policies.kyverno.io/title" = "Require Resource Labels";
              "policies.kyverno.io/category" = "ZKI Compliance";
              "policies.kyverno.io/description" =
                "All resources must have required labels for audit and tracking.";
            };
          };
          spec = {
            validationFailureAction = "enforce";
            background = true;
            rules = [
              {
                name = "check-app-label";
                match = {
                  any = [
                    {
                      resources = {
                        kinds = [
                          "Deployment"
                          "Service"
                          "ConfigMap"
                          "Secret"
                        ];
                      };
                    }
                  ];
                };
                validate = {
                  message = "Resource must have 'app' label for identification.";
                  pattern = {
                    metadata = {
                      labels = {
                        app = "?*";
                      };
                    };
                  };
                };
              }
              {
                name = "check-kubernetes-io-labels";
                match = {
                  any = [
                    {
                      resources = {
                        kinds = [
                          "Deployment"
                          "Service"
                        ];
                      };
                    }
                  ];
                };
                validate = {
                  message = "Resources must have 'app.kubernetes.io/name' label.";
                  pattern = {
                    metadata = {
                      labels = {
                        "app.kubernetes.io/name" = "?*";
                      };
                    };
                  };
                };
              }
            ];
          };
        };

        # APP.3.A1: Anwendungssicherheit - Require Resource Limits
        requireResourceLimitsPolicy = {
          apiVersion = "kyverno.io/v1";
          kind = "ClusterPolicy";
          metadata = {
            name = "require-resource-limits";
            labels = {
              "app.kubernetes.io/part-of" = "opendesk-edu";
              "compliance.zki.org/id" = "APP.3.A1";
            };
            annotations = {
              "policies.kyverno.io/title" = "Require Resource Limits";
              "policies.kyverno.io/category" = "ZKI Compliance";
              "policies.kyverno.io/description" =
                "All containers must have resource limits defined to prevent resource exhaustion.";
            };
          };
          spec = {
            validationFailureAction = "enforce";
            background = true;
            rules = [
              {
                name = "check-cpu-limits";
                match = {
                  any = [
                    {
                      resources = {
                        kinds = [
                          "Pod"
                          "Deployment"
                          "StatefulSet"
                          "DaemonSet"
                        ];
                      };
                    }
                  ];
                };
                validate = {
                  message = "Containers must have CPU limits defined.";
                  pattern = {
                    spec = {
                      containers = [
                        {
                          resources = {
                            limits = {
                              cpu = "?*";
                            };
                          };
                        }
                      ];
                    };
                  };
                };
              }
              {
                name = "check-memory-limits";
                match = {
                  any = [
                    {
                      resources = {
                        kinds = [
                          "Pod"
                          "Deployment"
                          "StatefulSet"
                          "DaemonSet"
                        ];
                      };
                    }
                  ];
                };
                validate = {
                  message = "Containers must have memory limits defined.";
                  pattern = {
                    spec = {
                      containers = [
                        {
                          resources = {
                            limits = {
                              memory = "?*";
                            };
                          };
                        }
                      ];
                    };
                  };
                };
              }
            ];
          };
        };

        # Supply Chain Security - Verify Image Signatures
        verifyImageSignaturesPolicy = {
          apiVersion = "kyverno.io/v1beta1";
          kind = "ClusterPolicy";
          metadata = {
            name = "verify-image-signatures";
            labels = {
              "app.kubernetes.io/part-of" = "opendesk-edu";
              "compliance.zki.org/id" = "SUPPLY-CHAIN-001";
            };
            annotations = {
              "policies.kyverno.io/title" = "Verify Image Signatures";
              "policies.kyverno.io/category" = "Supply Chain Security";
              "policies.kyverno.io/description" =
                "All container images must be signed and verified using Cosign.";
            };
          };
          spec = {
            validationFailureAction = "enforce";
            background = false;
            rules = [
              {
                name = "check-signatures";
                match = {
                  any = [
                    {
                      resources = {
                        kinds = [ "Pod" ];
                      };
                    }
                  ];
                };
                verifyImages = [
                  {
                    registry = "registry.opencode.de/umr/opendesk-edu/opendesk-nix/";
                    attestations = [ { predicateType = "https://slsa.dev/provenance/v0.2"; } ];
                    key = ''
                      -----BEGIN PUBLIC KEY-----
                      MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC...
                      -----END PUBLIC KEY-----'';
                  }
                ];
              }
            ];
          };
        };

        # Security Context - Require Read-Only Root Filesystem
        readOnlyRootFilesystemPolicy = {
          apiVersion = "kyverno.io/v1";
          kind = "ClusterPolicy";
          metadata = {
            name = "require-read-only-rootfs";
            labels = {
              "app.kubernetes.io/part-of" = "opendesk-edu";
              "compliance.zki.org/id" = "INF.1.A10";
            };
            annotations = {
              "policies.kyverno.io/title" = "Require Read-Only Root Filesystem";
              "policies.kyverno.io/category" = "ZKI Compliance";
              "policies.kyverno.io/description" =
                "Containers should use read-only root filesystem to prevent unauthorized modifications.";
            };
          };
          spec = {
            validationFailureAction = "enforce";
            background = true;
            rules = [
              {
                name = "read-only-rootfs";
                match = {
                  any = [
                    {
                      resources = {
                        kinds = [
                          "Pod"
                          "Deployment"
                          "StatefulSet"
                          "DaemonSet"
                        ];
                      };
                    }
                  ];
                };
                validate = {
                  message = "Containers must use read-only root filesystem. Set securityContext.readOnlyRootFilesystem to true.";
                  pattern = {
                    spec = {
                      securityContext = {
                        readOnlyRootFilesystem = true;
                      };
                    };
                  };
                };
              }
            ];
          };
        };

        # Drop All Capabilities
        dropCapabilitiesPolicy = {
          apiVersion = "kyverno.io/v1";
          kind = "ClusterPolicy";
          metadata = {
            name = "drop-all-capabilities";
            labels = {
              "app.kubernetes.io/part-of" = "opendesk-edu";
              "compliance.zki.org/id" = "INF.1.A10";
            };
            annotations = {
              "policies.kyverno.io/title" = "Drop All Capabilities";
              "policies.kyverno.io/category" = "ZKI Compliance";
              "policies.kyverno.io/description" =
                "Containers should drop all capabilities and only add required ones.";
            };
          };
          spec = {
            validationFailureAction = "enforce";
            background = true;
            rules = [
              {
                name = "drop-all";
                match = {
                  any = [
                    {
                      resources = {
                        kinds = [
                          "Pod"
                          "Deployment"
                          "StatefulSet"
                          "DaemonSet"
                        ];
                      };
                    }
                  ];
                };
                validate = {
                  message = "Containers must drop all capabilities. Add only required capabilities.";
                  pattern = {
                    spec = {
                      securityContext = {
                        capabilities = {
                          drop = [ "ALL" ];
                        };
                      };
                    };
                  };
                };
              }
            ];
          };
        };

        # ====================================================================
        # Compliance Scan Job
        # ====================================================================

        # ====================================================================
        # Combined Manifest
        # ====================================================================

        allPolicies = pkgs.writeText "compliance-policies.yaml" ''
          ---
          ${builtins.toJSON requireNonRootPolicy}
          ---
          ${builtins.toJSON requireNetworkPolicyPolicy}
          ---
          ${builtins.toJSON requireLabelsPolicy}
          ---
          ${builtins.toJSON requireResourceLimitsPolicy}
          ---
          ${builtins.toJSON verifyImageSignaturesPolicy}
          ---
          ${builtins.toJSON readOnlyRootFilesystemPolicy}
          ---
          ${builtins.toJSON dropCapabilitiesPolicy}
        '';

      in
      {
        packages = {
          # All compliance policies
          compliance-policies = allPolicies;

          # Individual policies
          require-non-root = requireNonRootPolicy;
          require-network-policy = requireNetworkPolicyPolicy;
          require-labels = requireLabelsPolicy;
          require-resource-limits = requireResourceLimitsPolicy;
          verify-image-signatures = verifyImageSignaturesPolicy;
          read-only-rootfs = readOnlyRootFilesystemPolicy;
          drop-capabilities = dropCapabilitiesPolicy;
        };

        default = self.packages.${system}.compliance-policies;

        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.kubectl
            pkgs.kyverno-cli
            pkgs.yq
          ];

          shellHook = ''
            echo "openDesk Edu - Compliance Example"
            echo "=================================="
            echo ""
            echo "ZKI-IT-Grundschutz Kyverno Policies:"
            echo "  - require-non-root: INF.1.A10 (Zugriffskontrolle)"
            echo "  - require-network-policy: INF.5.A1 (Netzwerksicherheit)"
            echo "  - require-labels: INF.1.A15 (Audit)"
            echo "  - require-resource-limits: APP.3.A1 (Anwendungssicherheit)"
            echo "  - verify-image-signatures: Supply Chain Security"
            echo "  - read-only-rootfs: INF.1.A10 (Zugriffskontrolle)"
            echo "  - drop-capabilities: INF.1.A10 (Zugriffskontrolle)"
            echo ""
            echo "Deploy policies:"
            echo "  nix build .#compliance-policies"
            echo "  kubectl apply -f result/"
            echo ""
            echo "Check policy status:"
            echo "  kubectl get clusterpolicies"
            echo "  kubectl get policyreports --all-namespaces"
            echo ""
          '';
        };
      }
    );
}
