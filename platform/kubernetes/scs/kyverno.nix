# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Kyverno — Kubernetes-native policy engine for the SCS K3s cluster.
# Generates K8s manifests for deploying Kyverno (v1.12.0) admission controller.
# All webhooks configured for HAProxy ingress compatibility.
#
# Aligns with ZKI checkpoints:
#   P0-CONT-002: Kyverno policy for image verification
#   P0-CONT-003: Non-root container enforcement

{
  lib,
  env ? import ../environments/scs/default.nix { inherit lib; },
  ...
}:

let
  name = "kyverno";
  namespace = "kyverno";
  image = "ghcr.io/kyverno/kyverno";
  tag = "v1.12.0";

  labels =
    lib.mkLabels {
      inherit name;
      partOf = "scs-security";
    }
    // {
      "app.kubernetes.io/component" = "policy-engine";
      "app.kubernetes.io/managed-by" = "nix";
    };

  resources = {
    requests = {
      cpu = "100m";
      memory = "256Mi";
    };
    limits = {
      cpu = "1000m";
      memory = "1Gi";
    };
  };

  # Namespaces to exclude from policy enforcement
  excludedNamespaces = "kube-system,metallb-system,kyverno,kube-node-lease";

in
[
  # Namespace
  (lib.namespace {
    name = namespace;
    labels = {
      "pod-security.kubernetes.io/enforce" = "restricted";
      "pod-security.kubernetes.io/audit" = "restricted";
      "pod-security.kubernetes.io/warn" = "restricted";
    };
  })

  # ServiceAccount
  (lib.serviceAccount {
    name = "${name}-admission-controller";
    inherit namespace;
    inherit labels;
    automountServiceAccountToken = true;
  })

  (lib.serviceAccount {
    name = "${name}-background-controller";
    inherit namespace;
    inherit labels;
    automountServiceAccountToken = true;
  })

  # ClusterRole — admission controller needs broad access for policy evaluation
  {
    apiVersion = "rbac.authorization.k8s.io/v1";
    kind = "ClusterRole";
    metadata = {
      name = "${name}-admission-controller";
      inherit labels;
    };
    rules = [
      # Core API resources
      {
        apiGroups = [ "" ];
        resources = [
          "pods"
          "pods/log"
          "services"
          "endpoints"
          "persistentvolumeclaims"
          "configmaps"
          "secrets"
          "serviceaccounts"
          "namespaces"
          "nodes"
          "resourcequotas"
          "limitranges"
        ];
        verbs = [
          "create"
          "update"
          "patch"
          "delete"
          "get"
          "list"
          "watch"
        ];
      }
      # Apps resources
      {
        apiGroups = [ "apps" ];
        resources = [
          "deployments"
          "daemonsets"
          "statefulsets"
          "replicasets"
        ];
        verbs = [
          "create"
          "update"
          "patch"
          "delete"
          "get"
          "list"
          "watch"
        ];
      }
      # Batch resources
      {
        apiGroups = [ "batch" ];
        resources = [
          "jobs"
          "cronjobs"
        ];
        verbs = [
          "create"
          "update"
          "patch"
          "delete"
          "get"
          "list"
          "watch"
        ];
      }
      # Networking resources
      {
        apiGroups = [ "networking.k8s.io" ];
        resources = [
          "networkpolicies"
          "ingresses"
        ];
        verbs = [
          "create"
          "update"
          "patch"
          "delete"
          "get"
          "list"
          "watch"
        ];
      }
      # RBAC resources
      {
        apiGroups = [ "rbac.authorization.k8s.io" ];
        resources = [
          "clusterroles"
          "clusterrolebindings"
          "roles"
          "rolebindings"
        ];
        verbs = [
          "create"
          "update"
          "patch"
          "delete"
          "get"
          "list"
          "watch"
        ];
      }
      # Kyverno CRDs
      {
        apiGroups = [ "kyverno.io" ];
        resources = [ "*" ];
        verbs = [
          "create"
          "update"
          "patch"
          "delete"
          "get"
          "list"
          "watch"
        ];
      }
      # Policy reports
      {
        apiGroups = [
          "wgpolicyk8s.io"
          "reports.kyverno.io"
        ];
        resources = [ "*" ];
        verbs = [
          "create"
          "update"
          "patch"
          "delete"
          "get"
          "list"
          "watch"
        ];
      }
      # Coordination (leases)
      {
        apiGroups = [ "coordination.k8s.io" ];
        resources = [ "leases" ];
        verbs = [
          "create"
          "update"
          "patch"
          "delete"
          "get"
          "list"
          "watch"
        ];
      }
      # Image related
      {
        apiGroups = [ "images.kyverno.io" ];
        resources = [ "*" ];
        verbs = [
          "create"
          "update"
          "patch"
          "delete"
          "get"
          "list"
          "watch"
        ];
      }
    ];
  }

  # ClusterRole — background controller (for generate/cleanup/mutate existing)
  {
    apiVersion = "rbac.authorization.k8s.io/v1";
    kind = "ClusterRole";
    metadata = {
      name = "${name}-background-controller";
      inherit labels;
    };
    rules = [
      {
        apiGroups = [ "" ];
        resources = [
          "pods"
          "services"
          "endpoints"
          "persistentvolumeclaims"
          "configmaps"
          "secrets"
          "serviceaccounts"
          "namespaces"
          "events"
        ];
        verbs = [
          "create"
          "update"
          "patch"
          "delete"
          "get"
          "list"
          "watch"
        ];
      }
      {
        apiGroups = [ "apps" ];
        resources = [
          "deployments"
          "daemonsets"
          "statefulsets"
          "replicasets"
        ];
        verbs = [
          "create"
          "update"
          "patch"
          "delete"
          "get"
          "list"
          "watch"
        ];
      }
      {
        apiGroups = [ "kyverno.io" ];
        resources = [ "*" ];
        verbs = [
          "create"
          "update"
          "patch"
          "delete"
          "get"
          "list"
          "watch"
        ];
      }
      {
        apiGroups = [
          "wgpolicyk8s.io"
          "reports.kyverno.io"
        ];
        resources = [ "*" ];
        verbs = [
          "create"
          "update"
          "patch"
          "delete"
          "get"
          "list"
          "watch"
        ];
      }
      {
        apiGroups = [ "coordination.k8s.io" ];
        resources = [ "leases" ];
        verbs = [
          "create"
          "update"
          "patch"
          "delete"
          "get"
          "list"
          "watch"
        ];
      }
    ];
  }

  # ClusterRoleBindings
  {
    apiVersion = "rbac.authorization.k8s.io/v1";
    kind = "ClusterRoleBinding";
    metadata = {
      name = "${name}-admission-controller";
      inherit labels;
    };
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io";
      kind = "ClusterRole";
      name = "${name}-admission-controller";
    };
    subjects = [
      {
        kind = "ServiceAccount";
        name = "${name}-admission-controller";
        inherit namespace;
      }
    ];
  }

  {
    apiVersion = "rbac.authorization.k8s.io/v1";
    kind = "ClusterRoleBinding";
    metadata = {
      name = "${name}-background-controller";
      inherit labels;
    };
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io";
      kind = "ClusterRole";
      name = "${name}-background-controller";
    };
    subjects = [
      {
        kind = "ServiceAccount";
        name = "${name}-background-controller";
        inherit namespace;
      }
    ];
  }

  # ConfigMap — Kyverno configuration
  {
    apiVersion = "v1";
    kind = "ConfigMap";
    metadata = {
      name = "${name}-config";
      inherit namespace;
      inherit labels;
    };
    data = {
      # Exclude system namespaces from policy enforcement
      "excludeNamespaces" = excludedNamespaces;

      "resourceFilters" = builtins.toJSON [
        {
          name = "exclude-system-namespaces";
          namespaceSelector = {
            matchExpressions = [
              {
                key = "kubernetes.io/metadata.name";
                operator = "In";
                values = [
                  "kube-system"
                  "metallb-system"
                  "kube-node-lease"
                ];
              }
            ];
          };
        }
        {
          name = "exclude-kyverno-resources";
          kinds = [
            "ClusterPolicy"
            "Policy"
            "ClusterPolicyReport"
            "PolicyReport"
          ];
        }
      ];
    };
  }

  # Deployment — Kyverno admission controller
  {
    apiVersion = "apps/v1";
    kind = "Deployment";
    metadata = {
      name = "${name}-admission-controller";
      inherit namespace;
      labels = labels // {
        component = "admission-controller";
      };
    };
    spec = {
      replicas = 1;
      revisionHistoryLimit = 10;
      selector = {
        matchLabels = lib.mkSelectorLabels { name = "${name}-admission-controller"; };
      };
      template = {
        metadata = {
          labels = labels // {
            component = "admission-controller";
          };
          annotations = {
            "prometheus.io/scrape" = "true";
            "prometheus.io/port" = "8000";
            "prometheus.io/path" = "/metrics";
          };
        };
        spec = {
          serviceAccountName = "${name}-admission-controller";
          securityContext = {
            runAsNonRoot = true;
            runAsUser = 1000;
            fsGroup = 2000;
            fsGroupChangePolicy = "OnRootMismatch";
          };
          initContainers = [
            {
              name = "init";
              image = "${image}:${tag}";
              imagePullPolicy = "IfNotPresent";
              args = [ "kyvernopre" ];
              resources = {
                requests = {
                  cpu = "50m";
                  memory = "64Mi";
                };
                limits = {
                  cpu = "200m";
                  memory = "256Mi";
                };
              };
              securityContext = {
                allowPrivilegeEscalation = false;
                runAsNonRoot = true;
                capabilities = {
                  drop = [ "ALL" ];
                };
              };
              env = [
                {
                  name = "KYVERNO_NAMESPACE";
                  valueFrom = {
                    fieldRef = {
                      fieldPath = "metadata.namespace";
                    };
                  };
                }
              ];
            }
          ];
          containers = [
            {
              name = "kyverno";
              image = "${image}:${tag}";
              imagePullPolicy = "IfNotPresent";
              ports = [
                {
                  containerPort = 9443;
                  name = "webhook";
                  protocol = "TCP";
                }
                {
                  containerPort = 8000;
                  name = "metrics";
                  protocol = "TCP";
                }
              ];
              inherit resources;
              securityContext = {
                allowPrivilegeEscalation = false;
                runAsNonRoot = true;
                readOnlyRootFilesystem = false;
                capabilities = {
                  drop = [ "ALL" ];
                };
              };
              env = [
                {
                  name = "INIT_CONTAINER";
                  value = "true";
                }
                {
                  name = "KYVERNO_NAMESPACE";
                  valueFrom = {
                    fieldRef = {
                      fieldPath = "metadata.namespace";
                    };
                  };
                }
                {
                  name = "KYVERNO_POLICY_MUTATION";
                  value = "true";
                }
                {
                  name = "KYVERNO_POLICY_VALIDATION";
                  value = "true";
                }
                {
                  name = "KYVERNO_GENERATE_SUCCESS_EVENTS";
                  value = "true";
                }
                {
                  name = "KYVERNO_LEADER_ELECTION";
                  value = "true";
                }
                {
                  name = "WEBHOOK_TIMEOUT";
                  value = "30";
                }
              ];
              volumeMounts = [
                {
                  name = "tmp-dir";
                  mountPath = "/tmp";
                }
                {
                  name = "certs";
                  mountPath = "/etc/cert";
                }
              ];
              livenessProbe = {
                httpGet = {
                  path = "/healthz";
                  port = 9443;
                  scheme = "HTTPS";
                };
                initialDelaySeconds = 15;
                periodSeconds = 20;
                timeoutSeconds = 5;
                failureThreshold = 3;
              };
              readinessProbe = {
                httpGet = {
                  path = "/healthz";
                  port = 9443;
                  scheme = "HTTPS";
                };
                initialDelaySeconds = 5;
                periodSeconds = 10;
                timeoutSeconds = 5;
                failureThreshold = 3;
              };
            }
          ];
          volumes = [
            {
              name = "tmp-dir";
              emptyDir = { };
            }
            {
              name = "certs";
              emptyDir = { };
            }
          ];
          restartPolicy = "Always";
          dnsPolicy = "ClusterFirst";
        };
      };
    };
  }

  # Deployment — Background controller
  {
    apiVersion = "apps/v1";
    kind = "Deployment";
    metadata = {
      name = "${name}-background-controller";
      inherit namespace;
      labels = labels // {
        component = "background-controller";
      };
    };
    spec = {
      replicas = 1;
      revisionHistoryLimit = 10;
      selector = {
        matchLabels = lib.mkSelectorLabels { name = "${name}-background-controller"; };
      };
      template = {
        metadata = {
          labels = labels // {
            component = "background-controller";
          };
        };
        spec = {
          serviceAccountName = "${name}-background-controller";
          securityContext = {
            runAsNonRoot = true;
            runAsUser = 1000;
            fsGroup = 2000;
            fsGroupChangePolicy = "OnRootMismatch";
          };
          containers = [
            {
              name = "kyverno-background-controller";
              image = "ghcr.io/kyverno/kyverno:v1.12.0";
              imagePullPolicy = "IfNotPresent";
              args = [ "background-controller" ];
              ports = [
                {
                  containerPort = 9443;
                  name = "webhook";
                  protocol = "TCP";
                }
              ];
              resources = {
                requests = {
                  cpu = "50m";
                  memory = "128Mi";
                };
                limits = {
                  cpu = "500m";
                  memory = "512Mi";
                };
              };
              securityContext = {
                allowPrivilegeEscalation = false;
                runAsNonRoot = true;
                readOnlyRootFilesystem = true;
                capabilities = {
                  drop = [ "ALL" ];
                };
              };
              env = [
                {
                  name = "KYVERNO_NAMESPACE";
                  valueFrom = {
                    fieldRef = {
                      fieldPath = "metadata.namespace";
                    };
                  };
                }
              ];
              volumeMounts = [
                {
                  name = "tmp-dir";
                  mountPath = "/tmp";
                }
              ];
            }
          ];
          volumes = [
            {
              name = "tmp-dir";
              emptyDir = { };
            }
          ];
          restartPolicy = "Always";
          dnsPolicy = "ClusterFirst";
        };
      };
    };
  }

  # Service — webhook (port 9443)
  {
    apiVersion = "v1";
    kind = "Service";
    metadata = {
      name = "${name}-webhook";
      inherit namespace;
      inherit labels;
    };
    spec = {
      type = "ClusterIP";
      ports = [
        {
          port = 9443;
          targetPort = 9443;
          name = "webhook";
          protocol = "TCP";
        }
      ];
      selector = lib.mkSelectorLabels { name = "${name}-admission-controller"; };
    };
  }

  # Service — metrics (port 8000)
  {
    apiVersion = "v1";
    kind = "Service";
    metadata = {
      name = "${name}-metrics";
      inherit namespace;
      inherit labels;
    };
    spec = {
      type = "ClusterIP";
      ports = [
        {
          port = 8000;
          targetPort = 8000;
          name = "metrics";
          protocol = "TCP";
        }
      ];
      selector = lib.mkSelectorLabels { name = "${name}-admission-controller"; };
    };
  }

  # ValidatingWebhookConfiguration
  {
    apiVersion = "admissionregistration.k8s.io/v1";
    kind = "ValidatingWebhookConfiguration";
    metadata = {
      name = "${name}-validating-webhook-cfg";
      inherit labels;
      annotations = {
        "cert-manager.k8s.io/inject-ca-from" = "${namespace}/${name}-tls";
      };
    };
    webhooks = [
      {
        name = "validate.kyverno.svc";
        matchPolicy = "Equivalent";
        rules = [
          {
            apiGroups = [ "*" ];
            apiVersions = [ "*" ];
            operations = [
              "CREATE"
              "UPDATE"
              "DELETE"
            ];
            resources = [ "*" ];
            scope = "*";
          }
        ];
        failurePolicy = "Fail";
        sideEffects = "NoneOnDryRun";
        timeoutSeconds = 30;
        admissionReviewVersions = [ "v1" ];
        clientConfig = {
          service = {
            name = "${name}-webhook";
            inherit namespace;
            path = "/validate";
            port = 9443;
          };
        };
      }
    ];
  }

  # MutatingWebhookConfiguration
  {
    apiVersion = "admissionregistration.k8s.io/v1";
    kind = "MutatingWebhookConfiguration";
    metadata = {
      name = "${name}-mutating-webhook-cfg";
      inherit labels;
      annotations = {
        "cert-manager.k8s.io/inject-ca-from" = "${namespace}/${name}-tls";
      };
    };
    webhooks = [
      {
        name = "mutate.kyverno.svc";
        matchPolicy = "Equivalent";
        rules = [
          {
            apiGroups = [ "*" ];
            apiVersions = [ "*" ];
            operations = [
              "CREATE"
              "UPDATE"
            ];
            resources = [ "*" ];
            scope = "*";
          }
        ];
        failurePolicy = "Fail";
        sideEffects = "NoneOnDryRun";
        timeoutSeconds = 30;
        admissionReviewVersions = [ "v1" ];
        reinvocationPolicy = "IfNeeded";
        clientConfig = {
          service = {
            name = "${name}-webhook";
            inherit namespace;
            path = "/mutate";
            port = 9443;
          };
        };
      }
    ];
  }
]
