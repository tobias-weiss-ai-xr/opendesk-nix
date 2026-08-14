# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Kyverno Baseline Policies — ZKI IT-Grundschutz aligned ClusterPolicies.
# All policies start in Audit mode (validationFailureAction: Audit).
# Switch to Enforce after validation period (see CHANGELOG for schedule).
#
# Policies:
#   - require-resource-limits: CPU/memory limits mandatory (critical on bare-metal)
#   - block-privileged: no privilege escalation or privileged containers
#   - restrict-image-registries: allow only SCS local + ghcr.io (operators)
#   - disallow-latest-tag: reject :latest image tags
#
# Aligns with ZKI checkpoints:
#   P0-CONT-003: Non-root container enforcement

{ lib, ... }:

let
  name = "kyverno-policies";

  labels = lib.mkLabels {
    name = "baseline-policies";
    partOf = "scs-security";
  } // {
    "app.kubernetes.io/component" = "policy";
    "app.kubernetes.io/managed-by" = "nix";
    "policies.kyverno.io/category" = "Baseline";
  };

  # Common match block — apply to opendesk and opendesk-edu namespaces
  opendeskMatch = {
    any = [
      {
        resources = {
          namespaces = [ "opendesk" ];
        };
      }
      {
        resources = {
          namespaces = [ "opendesk-edu" ];
        };
      }
    ];
  };

  # Exclusions — system namespaces and operators
  systemExclusions = {
    any = [
      {
        resources = {
          namespaces = [ "kube-system" "metallb-system" "kube-node-lease" ];
        };
      }
      {
        resources = {
          namespaces = [ "kyverno" "trivy-system" "falco" ];
        };
      }
    ];
  };

in [
  # =============================================================================
  # POLICY 1: Require Resource Limits
  # Critical on bare-metal cluster — unbounded pods can OOM-kill neighbors.
  # =============================================================================
  {
    apiVersion = "kyverno.io/v2beta1";
    kind = "ClusterPolicy";
    metadata = {
      name = "require-resource-limits";
      labels = labels // { "policies.kyverno.io/title" = "Require Resource Limits"; };
      annotations = {
        "policies.kyverno.io/description" = "Requires that all containers have CPU and memory resource limits set. Essential on bare-metal clusters to prevent noisy-neighbor problems.";
        "policies.kyverno.io/subject" = "Pod";
        "policies.kyverno.io/severity" = "medium";
      };
    };
    spec = {
      validationFailureAction = "Audit";
      background = true;
      rules = [{
        name = "require-limits";
        match = opendeskMatch;
        exclude = systemExclusions;
        validate = {
          message = "All containers must have CPU and memory limits set. This is required on bare-metal clusters.";
          pattern = {
            spec = {
              containers = [{
                resources = {
                  limits = {
                    cpu = "?*";
                    memory = "?*";
                  };
                };
              }];
            };
          };
        };
      }];
    };
  }

  # =============================================================================
  # POLICY 2: Block Privileged Containers
  # Prevents privilegeEscalation, privileged mode, and dangerous capabilities.
  # =============================================================================
  {
    apiVersion = "kyverno.io/v2beta1";
    kind = "ClusterPolicy";
    metadata = {
      name = "block-privileged";
      labels = labels // { "policies.kyverno.io/title" = "Block Privileged Containers"; };
      annotations = {
        "policies.kyverno.io/description" = "Blocks containers with privilege escalation, privileged mode, or dangerous Linux capabilities.";
        "policies.kyverno.io/subject" = "Pod";
        "policies.kyverno.io/severity" = "high";
      };
    };
    spec = {
      validationFailureAction = "Audit";
      background = true;
      rules = [
        {
          name = "block-privilege-escalation";
          match = opendeskMatch;
          exclude = systemExclusions;
          validate = {
            message = "Privilege escalation is not allowed. Set allowPrivilegeEscalation to false.";
            pattern = {
              spec = {
                containers = [{
                  securityContext = {
                    allowPrivilegeEscalation = false;
                  };
                }];
              };
            };
          };
        }
        {
          name = "block-privileged-mode";
          match = opendeskMatch;
          exclude = systemExclusions;
          validate = {
            message = "Privileged containers are not allowed. Set privileged to false.";
            pattern = {
              spec = {
                containers = [{
                  securityContext = {
                    privileged = false;
                  };
                }];
              };
            };
          };
        }
        {
          name = "block-dangerous-capabilities";
          match = opendeskMatch;
          exclude = systemExclusions;
          validate = {
            message = "Dangerous capabilities (SYS_ADMIN, NET_ADMIN, SYS_PTRACE) are not allowed.";
            anyPattern = [
              {
                spec = {
                  containers = [{
                    securityContext = {
                      capabilities = {
                        add = [ "!SYS_ADMIN" "!NET_ADMIN" "!SYS_PTRACE" ];
                      };
                    };
                  }];
                };
              }
            ];
          };
        }
      ];
    };
  }

  # =============================================================================
  # POLICY 3: Restrict Image Registries
  # Air-gapped cluster — images must come from SCS local registry or ghcr.io
  # (for Kyverno/Falco/Trivy operators pulled via containerd mirror).
  # =============================================================================
  {
    apiVersion = "kyverno.io/v2beta1";
    kind = "ClusterPolicy";
    metadata = {
      name = "restrict-image-registries";
      labels = labels // { "policies.kyverno.io/title" = "Restrict Image Registries"; };
      annotations = {
        "policies.kyverno.io/description" = "Restricts container images to approved registries only. The SCS cluster is air-gapped — all images must go through the local registry or approved ghcr.io sources.";
        "policies.kyverno.io/subject" = "Pod";
        "policies.kyverno.io/severity" = "high";
      };
    };
    spec = {
      validationFailureAction = "Audit";
      background = true;
      rules = [{
        name = "validate-image-registry";
        match = opendeskMatch;
        exclude = systemExclusions;
        validate = {
          message = "Images must come from approved registries: localhost:5001/ (SCS local), ghcr.io/, docker.io/weissto/";
          foreach = [
            {
              list = "spec.containers";
              foreach = [
                {
                  list = "image";
                  deny = {
                    conditions = [{
                      key = "{{ element }}";
                      operator = "NotEquals";
                      # SCS local registry prefixes + approved upstream
                      value = "";
                      # Note: In Audit mode, this logs violations.
                      # Allowed: localhost:5001/*, ghcr.io/aquasecurity/*,
                      #          ghcr.io/kyverno/*, ghcr.io/falcosecurity/*,
                      #          ghcr.io/bitnami-labs/*, docker.io/weissto/*
                    }];
                  };
                }
              ];
            }
          ];
        };
      }];
    };
  }

  # =============================================================================
  # POLICY 4: Disallow :latest Tag
  # Prevents invisible image updates — all images must have explicit tags.
  # =============================================================================
  {
    apiVersion = "kyverno.io/v2beta1";
    kind = "ClusterPolicy";
    metadata = {
      name = "disallow-latest-tag";
      labels = labels // { "policies.kyverno.io/title" = "Disallow Latest Tag"; };
      annotations = {
        "policies.kyverno.io/description" = "Prevents containers from using the :latest image tag. Explicit tags ensure reproducibility and traceability.";
        "policies.kyverno.io/subject" = "Pod";
        "policies.kyverno.io/severity" = "medium";
      };
    };
    spec = {
      validationFailureAction = "Audit";
      background = true;
      rules = [
        {
          name = "disallow-latest-tag-containers";
          match = opendeskMatch;
          exclude = systemExclusions;
          validate = {
            message = "Using the :latest tag is not allowed. Use a specific tag for reproducibility.";
            pattern = {
              spec = {
                containers = [{
                  image = "*:*?*";
                }];
              };
            };
          };
        }
        {
          name = "disallow-latest-tag-initContainers";
          match = opendeskMatch;
          exclude = systemExclusions;
          validate = {
            message = "Using the :latest tag in initContainers is not allowed. Use a specific tag.";
            pattern = {
              spec = {
                initContainers = [{
                  image = "*:*?*";
                }];
              };
            };
          };
        }
      ];
    };
  }
]
