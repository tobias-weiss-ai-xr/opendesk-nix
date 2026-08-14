# openDesk Edu - Kubernetes Operators Library
#
# This library provides Nix expressions for deploying and managing
# Kubernetes Operators for compliance automation and image building.
#
# Usage:
#   let
#     lib = import ./lib { system = "x86_64-linux"; };
#   in {
#     packages.compliance-operator = lib.operators.compliance-operator;
#     packages.image-builder-operator = lib.operators.image-builder-operator;
#   }

{ pkgs, lib, ... }:

let
  # ============================================================================
  # Operator Base Configuration
  # ============================================================================

  operatorBaseImage = pkgs.dockerTools.buildImage {
    name = "opendesk-edu/operator-base";
    tag = "latest";
    fromImage = pkgs.dockerTools.pullImage {
      imageName = "gcr.io/distroless/static-debian11";
      imageDigest = "sha256:9d7619fd40aae13a9123f87b237596709f4689b07e2d8f40c5f8e8e9a3c2e8f1";
      sha256 = "sha256-9d7619fd40aae13a9123f87b237596709f4689b07e2d8f40c5f8e8e9a3c2e8f1";
    };
    config = {
      User = "1000";
      WorkingDir = "/operator";
    };
  };

  # ============================================================================
  # Compliance Operator
  # ============================================================================

  # CRD for Compliance resources
  complianceCRD = pkgs.writeText "compliance-crd.yaml" ''
    apiVersion: apiextensions.k8s.io/v1
    kind: CustomResourceDefinition
    metadata:
      name: compliances.opendesk-edu.org
    spec:
      group: opendesk-edu.org
      versions:
        - name: v1alpha1
          served: true
          storage: true
          schema:
            openAPIV3Schema:
              type: object
              properties:
                spec:
                  type: object
                  properties:
                    framework:
                      type: string
                      description: "Compliance framework (zki, bsi, iso27001)"
                    namespaces:
                      type: array
                      items:
                        type: string
                      description: "Namespaces to scan"
                    schedule:
                      type: string
                      description: "Cron schedule for periodic scans"
                    severityThreshold:
                      type: string
                      description: "Minimum severity to report (low, medium, high, critical)"
                status:
                  type: object
                  properties:
                    lastScanTime:
                      type: string
                      format: date-time
                    score:
                      type: integer
                      description: "Compliance score (0-100)"
                    violations:
                      type: array
                      items:
                        type: object
                        properties:
                          id:
                            type: string
                          severity:
                            type: string
                          description:
                            type: string
                    phase:
                      type: string
                      description: "Pending, Running, Completed, Failed"
      scope: Namespaced
      names:
        plural: compliances
        singular: compliance
        kind: Compliance
        shortNames:
          - comp
  '';

  # Compliance Operator Deployment
  complianceOperatorDeployment = lib.k8s.mkDeployment {
    name = "compliance-operator";
    namespace = "opendesk";
    image = "${operatorBaseImage.name}:latest";
    replicas = 2;
    ports = [
      {
        containerPort = 8080;
        name = "metrics";
      }
      {
        containerPort = 9443;
        name = "webhook";
      }
    ];
    resources = {
      requests.memory = "256Mi";
      requests.cpu = "100m";
      limits.memory = "512Mi";
      limits.cpu = "500m";
    };
    env = [
      {
        name = "WATCH_NAMESPACE";
        value = "";
      } # Watch all namespaces
      {
        name = "OPERATOR_NAME";
        value = "compliance-operator";
      }
      {
        name = "LOG_LEVEL";
        value = "info";
      }
    ];
    serviceAccountName = "compliance-operator";
    securityContext = {
      runAsNonRoot = true;
      runAsUser = 1000;
      runAsGroup = 1000;
      fsGroup = 1000;
    };
    volumes = [
      {
        name = "certs";
        secret = {
          secretName = "compliance-operator-cert";
        };
      }
    ];
    volumeMounts = [
      {
        name = "certs";
        mountPath = "/etc/operator/certs";
        readOnly = true;
      }
    ];
  };

  # Compliance Operator RBAC
  complianceOperatorRBAC = lib.k8s.mkRBAC {
    name = "compliance-operator";
    namespace = "opendesk";
    rules = [
      {
        apiGroups = [ "opendesk-edu.org" ];
        resources = [
          "compliances"
          "compliances/status"
          "compliances/finalizers"
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
      {
        apiGroups = [ "kyverno.io" ];
        resources = [
          "clusterpolicies"
          "policies"
          "policystatus"
        ];
        verbs = [
          "get"
          "list"
          "watch"
        ];
      }
      {
        apiGroups = [ "reports.kyverno.com" ];
        resources = [
          "policyreports"
          "clusterpolicyreports"
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
          "namespaces"
          "pods"
          "services"
          "deployments"
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
          "deployments"
          "statefulsets"
          "daemonsets"
        ];
        verbs = [
          "get"
          "list"
          "watch"
        ];
      }
      {
        apiGroups = [ "networking.k8s.io" ];
        resources = [ "networkpolicies" ];
        verbs = [
          "get"
          "list"
          "watch"
        ];
      }
    ];
  };

  # ============================================================================
  # Image Builder Operator
  # ============================================================================

  # CRD for ImageBuild resources
  imageBuilderCRD = pkgs.writeText "imagebuild-crd.yaml" ''
    apiVersion: apiextensions.k8s.io/v1
    kind: CustomResourceDefinition
    metadata:
      name: imagebuilds.opendesk-edu.org
    spec:
      group: opendesk-edu.org
      versions:
        - name: v1alpha1
          served: true
          storage: true
          schema:
            openAPIV3Schema:
              type: object
              properties:
                spec:
                  type: object
                  properties:
                    service:
                      type: string
                      description: "Service name to build (e.g., sogo6, stalwart)"
                    registries:
                      type: array
                      items:
                        type: string
                      description: "Target registries for push"
                    sign:
                      type: boolean
                      default: true
                      description: "Sign image with cosign"
                    nixExpression:
                      type: string
                      description: "Custom Nix expression path"
                status:
                  type: object
                  properties:
                    phase:
                      type: string
                      description: "Pending, Building, Pushing, Completed, Failed"
                    buildLog:
                      type: string
                    imageDigest:
                      type: string
                    signed:
                      type: boolean
                    registries:
                      type: array
                      items:
                        type: string
      scope: Namespaced
      names:
        plural: imagebuilds
        singular: imagebuild
        kind: ImageBuild
        shortNames:
          - ib
  '';

  # Image Builder Operator Deployment
  imageBuilderOperatorDeployment = lib.k8s.mkDeployment {
    name = "image-builder-operator";
    namespace = "opendesk";
    image = "${operatorBaseImage.name}:latest";
    replicas = 1;
    ports = [
      {
        containerPort = 8081;
        name = "metrics";
      }
      {
        containerPort = 9444;
        name = "webhook";
      }
    ];
    resources = {
      requests.memory = "512Mi";
      requests.cpu = "200m";
      limits.memory = "2Gi";
      limits.cpu = "2000m";
    };
    env = [
      {
        name = "WATCH_NAMESPACE";
        value = "opendesk";
      }
      {
        name = "OPERATOR_NAME";
        value = "image-builder-operator";
      }
      {
        name = "LOG_LEVEL";
        value = "info";
      }
      {
        name = "NIX_STORE";
        value = "/nix/store";
      }
      {
        name = "BUILD_TIMEOUT";
        value = "3600";
      } # 1 hour timeout
    ];
    serviceAccountName = "image-builder-operator";
    securityContext = {
      runAsNonRoot = true;
      runAsUser = 1000;
      runAsGroup = 1000;
      fsGroup = 1000;
    };
    volumes = [
      {
        name = "nix-store";
        persistentVolumeClaim = {
          claimName = "nix-store-pvc";
        };
      }
      {
        name = "certs";
        secret = {
          secretName = "image-builder-operator-cert";
        };
      }
      {
        name = "docker-config";
        secret = {
          secretName = "docker-registry-auth";
        };
      }
    ];
    volumeMounts = [
      {
        name = "nix-store";
        mountPath = "/nix/store";
      }
      {
        name = "certs";
        mountPath = "/etc/operator/certs";
        readOnly = true;
      }
      {
        name = "docker-config";
        mountPath = "/kaniko/.docker";
        readOnly = true;
      }
    ];
  };

  # Image Builder Operator RBAC
  imageBuilderOperatorRBAC = lib.k8s.mkRBAC {
    name = "image-builder-operator";
    namespace = "opendesk";
    rules = [
      {
        apiGroups = [ "opendesk-edu.org" ];
        resources = [
          "imagebuilds"
          "imagebuilds/status"
          "imagebuilds/finalizers"
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
      {
        apiGroups = [ "" ];
        resources = [
          "pods"
          "pods/log"
          "persistentvolumeclaims"
        ];
        verbs = [
          "get"
          "list"
          "watch"
          "create"
          "update"
          "delete"
        ];
      }
      {
        apiGroups = [ "" ];
        resources = [ "secrets" ];
        verbs = [
          "get"
          "list"
          "watch"
        ];
      }
      {
        apiGroups = [ "batch" ];
        resources = [ "jobs" ];
        verbs = [
          "get"
          "list"
          "watch"
          "create"
          "update"
          "delete"
        ];
      }
    ];
  };

  # ============================================================================
  # ZKI Compliance Checkpoints
  # ============================================================================

  # ZKI-111-Checkpoints data structure
  zkiCheckpoints = {
    "P0-IAM-001" = {
      category = "IAM & Authentifizierung";
      priority = "P0";
      description = "Zentraler Identity Provider (Keycloak) betrieben";
      checkFunction = "checkKeycloakDeployment";
    };
    "P0-IAM-002" = {
      category = "IAM & Authentifizierung";
      priority = "P0";
      description = "SAML 2.0 / OIDC Support aktiviert";
      checkFunction = "checkSAML_OIDC";
    };
    "P0-IAM-003" = {
      category = "IAM & Authentifizierung";
      priority = "P0";
      description = "Multi-Faktor-Authentifizierung (MFA) konfigurierbar";
      checkFunction = "checkMFACapability";
    };
    "P0-NET-001" = {
      category = "Netzwerksicherheit";
      priority = "P0";
      description = "Network Policies für alle Namespaces implementiert";
      checkFunction = "checkNetworkPolicies";
    };
    "P0-NET-002" = {
      category = "Netzwerksicherheit";
      priority = "P0";
      description = "TLS 1.3 für alle externen Verbindungen";
      checkFunction = "checkTLSVersion";
    };
    "P0-CONT-001" = {
      category = "Container-Sicherheit";
      priority = "P0";
      description = "Image Signing mit Cosign";
      checkFunction = "checkImageSigning";
    };
    "P0-CONT-002" = {
      category = "Container-Sicherheit";
      priority = "P0";
      description = "Kyverno Policy für Image-Verification";
      checkFunction = "checkKyvernoImagePolicy";
    };
    "P0-CONT-003" = {
      category = "Container-Sicherheit";
      priority = "P0";
      description = "Non-Root Container Enforcement";
      checkFunction = "checkNonRootContainers";
    };
    "P0-DATA-001" = {
      category = "Datensicherheit";
      priority = "P0";
      description = "Encryption at Rest für Datenbanken";
      checkFunction = "checkDatabaseEncryption";
    };
    "P0-AUD-001" = {
      category = "Compliance & Audit";
      priority = "P0";
      description = "Zentrale Log-Aggregation (Loki)";
      checkFunction = "checkLogAggregation";
    };
  };

  # ============================================================================
  # Export
  # ============================================================================

in
{
  # Compliance Operator
  compliance-operator = {
    crd = complianceCRD;
    deployment = complianceOperatorDeployment;
    rbac = complianceOperatorRBAC;
    checkpoints = zkiCheckpoints;
  };

  # Image Builder Operator
  image-builder-operator = {
    crd = imageBuilderCRD;
    deployment = imageBuilderOperatorDeployment;
    rbac = imageBuilderOperatorRBAC;
  };

  # Combined operators deployment
  all-operators = {
    crds = [
      complianceCRD
      imageBuilderCRD
    ];
    deployments = [
      complianceOperatorDeployment
      imageBuilderOperatorDeployment
    ];
    rbac = [
      complianceOperatorRBAC
      imageBuilderOperatorRBAC
    ];
  };

  # Helper function to create operator namespace
  createOperatorNamespace =
    name:
    lib.k8s.mkNamespace {
      inherit name;
      labels = {
        "app.kubernetes.io/name" = name;
        "app.kubernetes.io/component" = "operator";
      };
    };

  # Helper function to create operator service account
  createOperatorServiceAccount =
    name: namespace:
    lib.k8s.mkServiceAccount {
      inherit name namespace;
      annotations = {
        "kubernetes.io/service-account.name" = name;
      };
    };
}
