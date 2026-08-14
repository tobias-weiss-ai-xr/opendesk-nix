# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Sealed Secrets — Encrypt Kubernetes Secrets at rest using asymmetric encryption.
# Generates K8s manifests for bitnami-labs/sealed-secrets controller (v0.26.4).
# Controller runs in kube-system namespace (Bitnami convention).
#
# Usage:
#   kubeseal -f secret.yaml -w sealed-secret.yaml
#   kubectl apply -f sealed-secret.yaml
#
# Aligns with ZKI checkpoint P0-DATA-001 (encryption at rest).

{
  lib,
  env ? import ../environments/scs/default.nix { inherit lib; },
  ...
}:

let
  name = "sealed-secrets-controller";
  namespace = "kube-system";
  image = "ghcr.io/bitnami-labs/sealed-secrets-controller";
  tag = "v0.26.4";

  labels =
    lib.mkLabels {
      name = "sealed-secrets";
      partOf = "scs-security";
    }
    // {
      "app.kubernetes.io/component" = "secret-encryption";
      "app.kubernetes.io/managed-by" = "nix";
    };

  resources = {
    requests = {
      cpu = "100m";
      memory = "128Mi";
    };
    limits = {
      cpu = "500m";
      memory = "512Mi";
    };
  };

in
[
  # ServiceAccount (in kube-system, per Bitnami convention)
  (lib.serviceAccount {
    inherit name;
    inherit namespace;
    inherit labels;
    automountServiceAccountToken = true;
  })

  # ClusterRole — manage SealedSecret CRDs across all namespaces
  {
    apiVersion = "rbac.authorization.k8s.io/v1";
    kind = "ClusterRole";
    metadata = {
      name = "secrets-unsealer";
      inherit labels;
    };
    rules = [
      {
        apiGroups = [ "bitnami.com" ];
        resources = [ "sealedsecrets" ];
        verbs = [
          "get"
          "list"
          "watch"
        ];
      }
      {
        apiGroups = [ "bitnami.com" ];
        resources = [ "sealedsecrets/status" ];
        verbs = [ "update" ];
      }
      {
        apiGroups = [ "" ];
        resources = [ "secrets" ];
        verbs = [
          "get"
          "create"
          "update"
          "delete"
        ];
      }
      {
        apiGroups = [ "" ];
        resources = [ "events" ];
        verbs = [
          "create"
          "patch"
        ];
      }
      {
        apiGroups = [ "admissionregistration.k8s.io" ];
        resources = [
          "mutatingwebhookconfigurations"
          "validatingwebhookconfigurations"
        ];
        verbs = [
          "get"
          "list"
          "watch"
          "create"
          "update"
          "patch"
          "delete"
        ];
      }
    ];
  }

  # ClusterRoleBinding
  {
    apiVersion = "rbac.authorization.k8s.io/v1";
    kind = "ClusterRoleBinding";
    metadata = {
      name = "secrets-unsealer";
      inherit labels;
    };
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io";
      kind = "ClusterRole";
      name = "secrets-unsealer";
    };
    subjects = [
      {
        kind = "ServiceAccount";
        inherit name;
        inherit namespace;
      }
    ];
  }

  # Role — manage CRDs and webhook secrets in kube-system
  {
    apiVersion = "rbac.authorization.k8s.io/v1";
    kind = "Role";
    metadata = {
      name = "sealed-secrets-controller";
      inherit namespace;
      inherit labels;
    };
    rules = [
      {
        apiGroups = [ "apiextensions.k8s.io" ];
        resources = [ "customresourcedefinitions" ];
        resourceNames = [ "sealedsecrets.bitnami.com" ];
        verbs = [
          "get"
          "update"
        ];
      }
    ];
  }

  # RoleBinding
  {
    apiVersion = "rbac.authorization.k8s.io/v1";
    kind = "RoleBinding";
    metadata = {
      name = "sealed-secrets-controller";
      inherit namespace;
      inherit labels;
    };
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io";
      kind = "Role";
      name = "sealed-secrets-controller";
    };
    subjects = [
      {
        kind = "ServiceAccount";
        inherit name;
        inherit namespace;
      }
    ];
  }

  # Deployment
  {
    apiVersion = "apps/v1";
    kind = "Deployment";
    metadata = {
      inherit name;
      inherit namespace;
      inherit labels;
    };
    spec = {
      replicas = 1;
      revisionHistoryLimit = 10;
      strategy = {
        type = "RollingUpdate";
        rollingUpdate = {
          maxSurge = "25%";
          maxUnavailable = "0%";
        };
      };
      selector = {
        matchLabels = lib.mkSelectorLabels { inherit name; };
      };
      template = {
        metadata = {
          inherit labels;
          annotations = {
            "prometheus.io/scrape" = "true";
            "prometheus.io/port" = "8080";
          };
        };
        spec = {
          serviceAccountName = name;
          securityContext = {
            runAsNonRoot = true;
            runAsUser = 1001;
            fsGroup = 1001;
            fsGroupChangePolicy = "OnRootMismatch";
          };
          containers = [
            {
              inherit name;
              image = "${image}:${tag}";
              imagePullPolicy = "IfNotPresent";
              ports = [
                {
                  containerPort = 8080;
                  name = "http";
                  protocol = "TCP";
                }
                {
                  containerPort = 8081;
                  name = "metrics";
                  protocol = "TCP";
                }
              ];
              inherit resources;
              securityContext = {
                allowPrivilegeEscalation = false;
                runAsNonRoot = true;
                readOnlyRootFilesystem = true;
                capabilities = {
                  drop = [ "ALL" ];
                };
                seccompProfile = {
                  type = "RuntimeDefault";
                };
              };
              command = [ "controller" ];
              args = [
                "--key-prefix"
                "sealed-secrets-key"
                "--listen"
                ":8080"
                "--metrics-listen"
                ":8081"
              ];
              env = [
                {
                  name = "SEALED_SECRETS_CONTROLLER_LOG_LEVEL";
                  value = "info";
                }
                {
                  name = "SEALED_SECRETS_CONTROLLER_NAMESPACE";
                  valueFrom = {
                    fieldRef = {
                      fieldPath = "metadata.namespace";
                    };
                  };
                }
              ];
              livenessProbe = {
                httpGet = {
                  path = "/healthz";
                  port = 8080;
                };
                initialDelaySeconds = 30;
                periodSeconds = 10;
                timeoutSeconds = 5;
                failureThreshold = 3;
              };
              readinessProbe = {
                httpGet = {
                  path = "/healthz";
                  port = 8080;
                };
                initialDelaySeconds = 5;
                periodSeconds = 10;
                timeoutSeconds = 5;
                failureThreshold = 3;
              };
              volumeMounts = [
                {
                  name = "tls-certs";
                  mountPath = "/etc/tls";
                }
                {
                  name = "tmp-dir";
                  mountPath = "/tmp";
                }
              ];
            }
          ];
          volumes = [
            {
              name = "tls-certs";
              emptyDir = {
                medium = "Memory";
              };
            }
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

  # Service — webhook port
  {
    apiVersion = "v1";
    kind = "Service";
    metadata = {
      name = "sealed-secrets";
      inherit namespace;
      inherit labels;
    };
    spec = {
      type = "ClusterIP";
      ports = [
        {
          port = 8080;
          targetPort = 8080;
          name = "http";
          protocol = "TCP";
        }
        {
          port = 8081;
          targetPort = 8081;
          name = "metrics";
          protocol = "TCP";
        }
      ];
      selector = lib.mkSelectorLabels { inherit name; };
    };
  }

  # MutatingWebhookConfiguration — converts SealedSecret → Secret
  {
    apiVersion = "admissionregistration.k8s.io/v1";
    kind = "MutatingWebhookConfiguration";
    metadata = {
      name = "sealed-secrets-webhook";
      inherit labels;
      annotations = {
        "cert-manager.k8s.io/inject-ca-from" = "${namespace}/sealed-secrets-tls";
      };
    };
    webhooks = [
      {
        name = "sealedsecrets.bitnami.com";
        matchPolicy = "Equivalent";
        rules = [
          {
            apiGroups = [ "bitnami.com" ];
            apiVersions = [ "v1alpha1" ];
            operations = [
              "CREATE"
              "UPDATE"
            ];
            resources = [ "sealedsecrets" ];
            scope = "Namespace";
          }
        ];
        failurePolicy = "Fail";
        sideEffects = "None";
        timeoutSeconds = 5;
        admissionReviewVersions = [ "v1" ];
        clientConfig = {
          service = {
            name = "sealed-secrets";
            inherit namespace;
            path = "/v1/rotate";
            port = 8080;
          };
        };
      }
    ];
  }
]
