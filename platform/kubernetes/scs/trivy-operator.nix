# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Trivy Operator — Continuous container image scanning for SCS K3s cluster.
# Generates K8s manifests for deploying Trivy Operator (v0.16.0) to scan
# images for CVEs on a continuous basis via Kubernetes admission and
# periodic scan jobs.
#
# Aligns with ZKI checkpoint P0-CONT-001 (Cosign/image verification pipeline).

{
  lib,
  env ? import ../environments/scs/default.nix { inherit lib; },
  ...
}:

let
  name = "trivy-operator";
  namespace = "trivy-system";
  image = "ghcr.io/aquasecurity/trivy-operator";
  tag = "0.16.0";

  labels =
    lib.mkLabels {
      inherit name;
      partOf = "scs-security";
    }
    // {
      "app.kubernetes.io/component" = "scanner";
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

  # Namespaces to exclude from scanning
  excludedNamespaces = "kube-system,metallb-system,trivy-system";

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
    name = "${name}";
    inherit namespace;
    inherit labels;
    automountServiceAccountToken = true;
  })

  # ClusterRole — read access to Pods/Nodes/ReplicaSets across all namespaces
  {
    apiVersion = "rbac.authorization.k8s.io/v1";
    kind = "ClusterRole";
    metadata = {
      name = "${name}";
      inherit labels;
    };
    rules = [
      {
        apiGroups = [ "" ];
        resources = [
          "pods"
          "nodes"
          "replicasets"
          "replicationcontrollers"
          "statefulsets"
          "daemonsets"
          "jobs"
          "cronjobs"
        ];
        verbs = [
          "get"
          "list"
          "watch"
        ];
      }
      {
        apiGroups = [ "apps" ];
        resources = [
          "replicasets"
          "statefulsets"
          "daemonsets"
          "deployments"
        ];
        verbs = [
          "get"
          "list"
          "watch"
        ];
      }
      {
        apiGroups = [ "batch" ];
        resources = [
          "jobs"
          "cronjobs"
        ];
        verbs = [
          "get"
          "list"
          "watch"
        ];
      }
      {
        apiGroups = [ "" ];
        resources = [
          "secrets"
          "configmaps"
          "serviceaccounts"
        ];
        verbs = [
          "get"
          "list"
          "watch"
        ];
      }
      {
        apiGroups = [
          "aquasecurity.github.io"
          "trivy-operator.aquasecurity.github.io"
        ];
        resources = [ "*" ];
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
      {
        apiGroups = [ "coordination.k8s.io" ];
        resources = [ "leases" ];
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
      {
        apiGroups = [ "security.openshift.io" ];
        resources = [ "securitycontextconstraints" ];
        verbs = [ "use" ];
      }
    ];
  }

  # ClusterRoleBinding
  {
    apiVersion = "rbac.authorization.k8s.io/v1";
    kind = "ClusterRoleBinding";
    metadata = {
      name = "${name}";
      inherit labels;
    };
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io";
      kind = "ClusterRole";
      name = "${name}";
    };
    subjects = [
      {
        kind = "ServiceAccount";
        name = "${name}";
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
      selector = {
        matchLabels = lib.mkSelectorLabels { inherit name; };
      };
      template = {
        metadata = {
          inherit labels;
          annotations = {
            "prometheus.io/scrape" = "true";
            "prometheus.io/port" = "8080";
            "prometheus.io/path" = "/metrics";
          };
        };
        spec = {
          serviceAccountName = name;
          securityContext = {
            runAsNonRoot = true;
            runAsUser = 1000;
            fsGroup = 2000;
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
              };
              env = [
                {
                  name = "TRIVY_OPERATOR_SCAN_JOB_TTL";
                  value = "1h";
                }
                {
                  name = "TRIVY_OPERATOR_SEVERITY";
                  value = "HIGH,CRITICAL";
                }
                {
                  name = "TRIVY_OPERATOR_IGNORE_UNFIXED";
                  value = "true";
                }
                {
                  name = "TRIVY_OPERATOR_SCAN_CODES_WHERE";
                  value = "";
                }
                {
                  name = "TRIVY_OPERATOR_EXCLUDED_NAMESPACES";
                  value = excludedNamespaces;
                }
                {
                  name = "TRIVY_OPERATOR_VULNERABILITY_REPORT_TTL";
                  value = "24h";
                }
                {
                  name = "TRIVY_OPERATOR_CONFIG_AUDIT_SCANNER_ENABLED";
                  value = "true";
                }
                {
                  name = "TRIVY_OPERATOR_RBAC_ASSESSMENT_SCANNER_ENABLED";
                  value = "true";
                }
                {
                  name = "TRIVY_OPERATOR_EXPOSED_SECRET_SCANNER_ENABLED";
                  value = "true";
                }
                {
                  name = "WORKER_TOKEN";
                  valueFrom = {
                    secretKeyRef = {
                      name = "${name}-webhook-secret";
                      key = "worker-token";
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

  # Service for metrics
  {
    apiVersion = "v1";
    kind = "Service";
    metadata = {
      inherit name;
      inherit namespace;
      inherit labels;
    };
    spec = {
      type = "ClusterIP";
      ports = [
        {
          port = 8080;
          targetPort = 8080;
          name = "metrics";
          protocol = "TCP";
        }
      ];
      selector = lib.mkSelectorLabels { inherit name; };
    };
  }

  # ConfigMap — scan configuration
  {
    apiVersion = "v1";
    kind = "ConfigMap";
    metadata = {
      name = "trivy-operator-trivy-config";
      inherit namespace;
      inherit labels;
    };
    data = {
      "trivy.yaml" = ''
        severity: HIGH,CRITICAL
        ignore-unfixed: true
        format: json
        exit-code: 0
        timeout: 5m
        scan:
          security-checks:
            - secret
          skip-files:
            - "*.exe"
            - "*.dll"
          ignore-policy: ""
      '';
    };
  }

  # Secret for webhook token (placeholder — rotate on deployment)
  {
    apiVersion = "v1";
    kind = "Secret";
    metadata = {
      name = "${name}-webhook-secret";
      inherit namespace;
      inherit labels;
    };
    type = "Opaque";
    stringData = {
      "worker-token" = "REPLACE-WITH-RANDOM-TOKEN";
    };
  }
]
