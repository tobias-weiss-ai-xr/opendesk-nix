{ lib, pkgs, config ? {} }:

# Import sub-libraries
let
  plugins = import ./operators/plugins.nix { inherit lib pkgs; };
  pkg = import ./operators/pkg.nix { inherit lib pkgs; };
  
  # External imports
  security-scanning = import ./security-scanning.nix { inherit lib pkgs; };
  registry-nix = import ./registry.nix { inherit lib pkgs; };
  compliance = import ./compliance.nix { inherit lib pkgs; };

  # Shortcut
  utils = lib;

  # Constants
  defaultNamespace = plugins.defaultNamespace;
  defaultLabels = plugins.defaultLabels;

in

{
  # =============================================================================
  # OPERATOR FACTORY
  # Generate complete operator deployments with DevGuard patterns
  # =============================================================================

  lib = plugins // pkg;

  # ---------------------------------------------------------------------------
  # Base: Kubernetes Object Constructors
  # ---------------------------------------------------------------------------

  mkMetadata = { name, namespace ? defaultNamespace, labels ? {}, annotations ? {}, 
                 finalizers ? [], ownerReferences ? [] }:
    {
      name = name;
      namespace = if namespace == "" then null else namespace;
      labels = defaultLabels // labels;
      annotations = annotations;
      finalizers = finalizers;
      ownerReferences = ownerReferences;
    };

  mkServiceAccount = { name, namespace ? defaultNamespace, labels ? {}, annotations ? {}, 
                        automountToken ? true, secrets ? [], imagePullSecrets ? [] }:
    {
      apiVersion = "v1";
      kind = "ServiceAccount";
      metadata = mkMetadata { inherit name namespace; labels = labels; annotations = annotations; };
      automountServiceAccountToken = automountToken;
      secrets = secrets;
      imagePullSecrets = imagePullSecrets;
    };

  mkClusterRole = { name, rules ? [], labels ? {}, annotations ? {}, 
                     aggregationRule ? null }:
    {
      apiVersion = "rbac.authorization.k8s.io/v1";
      kind = "ClusterRole";
      metadata = mkMetadata { inherit name; namespace = ""; labels = labels; annotations = annotations; };
      rules = rules;
      aggregationRule = aggregationRule;
    };

  mkClusterRoleBinding = { name, roleRef, subjects ? [], labels ? {}, annotations ? {} }:
    {
      apiVersion = "rbac.authorization.k8s.io/v1";
      kind = "ClusterRoleBinding";
      metadata = mkMetadata { inherit name; namespace = ""; labels = labels; annotations = annotations; };
      roleRef = roleRef;
      subjects = subjects;
    };

  mkRoleBinding = { name, namespace ? defaultNamespace, roleRef, subjects ? [], 
                    labels ? {}, annotations ? {} }:
    {
      apiVersion = "rbac.authorization.k8s.io/v1";
      kind = "RoleBinding";
      metadata = mkMetadata { inherit name namespace; labels = labels; annotations = annotations; };
      roleRef = roleRef;
      subjects = subjects;
    };

  mkCustomResourceDefinition = { 
    name, group, version, kind, plural, 
    scope ? "Namespaced",
    shortNames ? [],
    labels ? {},
    annotations ? {},
    subresources ? null,
    additionalPrinterColumns ? [],
    validation ? null,
    conversion ? null,
    preserveUnknownFields ? false,
    ...
  }:
    let
      fullName = "${plural}.${group}";
    in {
      apiVersion = "apiextensions.k8s.io/v1";
      kind = "CustomResourceDefinition";
      metadata = mkMetadata { 
        name = fullName; 
        namespace = ""; 
        labels = defaultLabels // labels;
        annotations = annotations // {
          "controller-gen.kubebuilder.io/version" = "v0.14.0";
          "api-approved.kubernetes.io" = "https://github.com/kubernetes-sigs/controller-runtime";
        };
      };
      spec = {
        group = group;
        versions = [
          {
            name = version;
            served = true;
            storage = true;
            schema = {
              openAPIV3Schema = {
                type = "object";
                properties = {
                  apiVersion = { type = "string"; };
                  kind = { type = "string"; };
                  metadata = { type = "object"; };
                  spec = { type = "object"; };
                  status = { type = "object"; };
                };
              };
            };
            subresources = subresources;
            additionalPrinterColumns = additionalPrinterColumns;
            validation = validation;
          }
        ];
        scope = scope;
        names = {
          plural = plural;
          singular = plural;
          kind = kind;
          listKind = "${kind}List";
          shortNames = shortNames;
        };
        conversion = conversion;
        preserveUnknownFields = preserveUnknownFields;
      };
    };

  mkDeployment = { 
    name, 
    namespace ? defaultNamespace,
    replicas ? 1,
    image,
    args ? [],
    env ? [],
    envFrom ? [],
    volumes ? [],
    volumeMounts ? [],
    ports ? [],
    resources ? {
      limits = { cpu = "500m"; memory = "512Mi"; };
      requests = { cpu = "100m"; memory = "128Mi"; };
    },
    securityContext ? {
      allowPrivilegeEscalation = false;
      capabilities = { drop = [ "ALL" ]; };
      privileged = false;
      readOnlyRootFilesystem = true;
      runAsNonRoot = true;
      runAsUser = 1000;
      seccompProfile = { type = "RuntimeDefault"; };
    },
    livenessProbe ? null,
    readinessProbe ? null,
    startupProbe ? null,
    serviceAccountName ? name,
    nodeSelector ? {},
    affinity ? {},
    tolerations ? [],
    labels ? {},
    annotations ? {},
    podLabels ? {},
    podAnnotations ? {},
    revisionHistoryLimit ? 10,
    strategy ? { type = "RollingUpdate"; rollingUpdate = { maxSurge = 1; maxUnavailable = 0; }; },
    ...
  }:
    {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = mkMetadata { inherit name namespace; labels = labels; annotations = annotations; };
      spec = {
        replicas = replicas;
        revisionHistoryLimit = revisionHistoryLimit;
        selector = {
          matchLabels = defaultLabels // labels // { "app.kubernetes.io/name" = name; };
        };
        strategy = strategy;
        template = {
          metadata = {
            labels = defaultLabels // labels // podLabels // { "app.kubernetes.io/name" = name; };
            annotations = annotations // podAnnotations;
          };
          spec = {
            serviceAccountName = serviceAccountName;
            automountServiceAccountToken = true;
            containers = [
              {
                name = name;
                image = image;
                args = args;
                env = env;
                envFrom = envFrom;
                ports = ports;
                volumeMounts = volumeMounts;
                resources = resources;
                securityContext = securityContext;
                livenessProbe = livenessProbe;
                readinessProbe = readinessProbe;
                startupProbe = startupProbe;
              }
            ];
            volumes = volumes;
            nodeSelector = nodeSelector;
            affinity = affinity;
            tolerations = tolerations;
          };
        };
      };
    };

  mkConfigMap = { name, namespace ? defaultNamespace, data ? {}, labels ? {}, annotations ? {} }:
    {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = mkMetadata { inherit name namespace; labels = labels; annotations = annotations; };
      data = data;
    };

  mkSecret = { name, namespace ? defaultNamespace, data ? {}, stringData ? {}, 
               labels ? {}, annotations ? {}, type ? "Opaque" }:
    {
      apiVersion = "v1";
      kind = "Secret";
      metadata = mkMetadata { inherit name namespace; labels = labels; annotations = annotations; };
      type = type;
      data = data;
      stringData = stringData;
    };

  # ---------------------------------------------------------------------------
  # COMPIANCE OPERATOR
  # Automatically validates container images against compliance policies
  # ---------------------------------------------------------------------------

  complianceOperator = { 
    name ? "opendesk-compliance-operator",
    namespace ? defaultNamespace,
    image ? "ghcr.io/tobias-weiss-ai-xr/opendesk-compliance-operator:latest",
    tag ? "latest",
    replicas ? 1,
    watchNamespaces ? [ "default" "opendesk" ],
    watchedResources ? [ "Deployment" "StatefulSet" "DaemonSet" "Pod" "Job" "CronJob" ],
    scannerTypes ? [ "grype" "trivy" ],
    complianceProfileName ? "production",
    blockNonCompliant ? true,
    rescanInterval ? "1h",
    maxConcurrentScans ? 5,
    ...
  }@opts:
    let
      cfg = opts;
      baseLabels = defaultLabels // {
        "app.kubernetes.io/name" = cfg.name;
        "app.kubernetes.io/component" = "compliance-operator";
      };
    in {
      # Configuration for the operator
      config = {
        watchNamespaces = cfg.watchNamespaces;
        watchedResources = cfg.watchedResources;
        scannerConfig = security-scanning.scannerConfig."${toString cfg.complianceProfileName}";
        complianceProfile = compliance.profiles."${toString cfg.complianceProfileName}";
        behavior = {
          blockNonCompliant = cfg.blockNonCompliant;
          scanInterval = cfg.rescanInterval;
          maxConcurrent = cfg.maxConcurrentScans;
        };
      };

      # Custom Resource Definition for ComplianceScan
      ComplianceScanCRD = mkCustomResourceDefinition {
        name = "compliance-scan";
        group = "opendesk.io";
        version = "v1";
        kind = "ComplianceScan";
        plural = "compliancescans";
        shortNames = [ "cs" ];
        scope = "Namespaced";
        labels = baseLabels;
        additionalPrinterColumns = [
          { name = "Target"; type = "string"; jsonPath = ".spec.resourceName"; };
          { name = "Namespace"; type = "string"; jsonPath = ".spec.resourceNamespace"; };
          { name = "Phase"; type = "string"; jsonPath = ".status.phase"; };
          { name = "Compliant"; type = "string"; jsonPath = ".status.compliant"; };
          { name = "Scanned"; type = "date"; jsonPath = ".status.lastScanTime"; };
          { name = "Age"; type = "date"; jsonPath = ".metadata.creationTimestamp"; };
        ];
        subresources = { status = {}; };
      };

      # RBAC
      rbac = {
        serviceAccount = mkServiceAccount {
          name = cfg.name;
          namespace = cfg.namespace;
          labels = baseLabels;
        };

        clusterRole = mkClusterRole {
          name = cfg.name;
          labels = baseLabels;
          rules = [
            {
              apiGroups = [ "" ];
              resources = [ "pods" "replicationcontrollers" "services" "secrets" "configmaps" "namespaces" "events" ];
              verbs = [ "get" "list" "watch" "create" "update" "patch" "delete" ];
            }
            {
              apiGroups = [ "apps" ];
              resources = [ "deployments" "statefulsets" "daemonsets" "replicasets" ];
              verbs = [ "get" "list" "watch" "create" "update" "patch" "delete" ];
            }
            {
              apiGroups = [ "batch" ];
              resources = [ "jobs" "cronjobs" "jobtemplates" ];
              verbs = [ "get" "list" "watch" "create" "update" "patch" "delete" ];
            }
            {
              apiGroups = [ "opendesk.io" ];
              resources = [ "compliancescans" ];
              verbs = [ "get" "list" "watch" "create" "update" "patch" "delete" ];
            }
          ];
        };

        roleBinding = mkRoleBinding {
          name = cfg.name;
          namespace = cfg.namespace;
          roleRef = {
            apiGroup = "rbac.authorization.k8s.io";
            kind = "ClusterRole";
            name = cfg.name;
          };
          subjects = [
            {
              kind = "ServiceAccount";
              name = cfg.name;
              namespace = cfg.namespace;
            }
          ];
          labels = baseLabels;
        };
      };

      # Deployment
      deployment = mkDeployment {
        name = cfg.name;
        namespace = cfg.namespace;
        replicas = cfg.replicas;
        image = "${cfg.image}:${cfg.tag}";
        serviceAccountName = cfg.name;
        labels = baseLabels;
        args = [
          "--operator-name=${cfg.name}"
          "--watch-namespaces=${builtins.concatStringsSep "," cfg.watchNamespaces}"
          "--watched-resources=${builtins.concatStringsSep "," cfg.watchedResources}"
          "--scanners=${builtins.concatStringsSep "," cfg.scannerTypes}"
          "--compliance-profile=${cfg.complianceProfileName}"
          "--max-concurrent-scans=${toString cfg.maxConcurrentScans}"
          "--rescan-interval=${cfg.rescanInterval}"
          "--block-non-compliant=${if cfg.blockNonCompliant then "true" else "false"}"
        ];
        env = [
          { name = "OPERATOR_NAME"; value = cfg.name; };
          { name = "OPERATOR_NAMESPACE"; valueFrom = { fieldRef = { fieldPath = "metadata.namespace"; }; }; };
          { name = "WATCH_NAMESPACES"; value = builtins.concatStringsSep "," cfg.watchNamespaces; };
          { name = "MAX_CONCURRENT_SCANS"; value = toString cfg.maxConcurrentScans; };
        ];
        livenessProbe = {
          httpGet = { path = "/healthz"; port = 8081; scheme = "HTTP"; };
          initialDelaySeconds = 10;
          periodSeconds = 30;
          timeoutSeconds = 5;
        };
        readinessProbe = {
          httpGet = { path = "/readyz"; port = 8081; scheme = "HTTP"; };
          initialDelaySeconds = 5;
          periodSeconds = 15;
          timeoutSeconds = 3;
        };
      };

      # Full manifest for deployment
      manifest = [
        ComplianceScanCRD
        rbac.serviceAccount
        rbac.clusterRole
        rbac.roleBinding
        deployment
      ];

      # Nix package definition
      package = pkgs.stdenv.mkDerivation rec {
        pname = cfg.name;
        version = "1.0.0";
        src = ./.;
        nativeBuildInputs = [ pkgs.go pkgs.gcc ];
        buildPhase = ''
          go build -o ${pname} ./cmd/operator
        '';
        installPhase = ''
          mkdir -p $out/bin
          cp ${pname} $out/bin/
        '';
      };
    };

  # ---------------------------------------------------------------------------
  # IMAGE BUILDER OPERATOR
  # Automatically builds and pushes container images
  # ---------------------------------------------------------------------------

  imageBuilderOperator = { 
    name ? "opendesk-image-builder-operator",
    namespace ? defaultNamespace,
    image ? "ghcr.io/tobias-weiss-ai-xr/opendesk-image-builder-operator:latest",
    tag ? "latest",
    replicas ? 1,
    watchNamespaces ? [ "default" "opendesk" ],
    builderTool ? "docker",
    maxConcurrentBuilds ? 3,
    buildTimeout ? "30m",
    enableSigning ? true,
    keylessSigning ? true,
    enableAttestations ? true,
    attestationTypes ? [ "sbom" "vulnerability-scan" "provenance" ],
    pushToAllRegistries ? false,
    defaultRegistry ? "ghcr.io",
    ...
  }@opts:
    let
      cfg = opts;
      baseLabels = defaultLabels // {
        "app.kubernetes.io/name" = cfg.name;
        "app.kubernetes.io/component" = "image-builder-operator";
      };
      
      registries = registry-nix.makeMultiRegistryConfig {
        registries = [
          (registry-nix.makeRegistryConfig { name = "ghcr"; url = "ghcr.io"; })
          (registry-nix.makeRegistryConfig { name = "docker-hub"; url = "docker.io"; })
        ];
      };
    in {
      config = {
        watchNamespaces = cfg.watchNamespaces;
        builder = {
          tool = cfg.builderTool;
          timeout = cfg.buildTimeout;
          maxConcurrent = cfg.maxConcurrentBuilds;
        };
        registry = registries;
        signing = {
          enable = cfg.enableSigning;
          keyless = cfg.keylessSigning;
        };
        attestation = {
          enable = cfg.enableAttestations;
          types = cfg.attestationTypes;
        };
        pushStrategy = {
          pushToAll = cfg.pushToAllRegistries;
          defaultRegistry = cfg.defaultRegistry;
        };
      };

      # CRD for ImageBuild
      ImageBuildCRD = mkCustomResourceDefinition {
        name = "imagebuild";
        group = "opendesk.io";
        version = "v1";
        kind = "ImageBuild";
        plural = "imagebuilds";
        shortNames = [ "ib" ];
        scope = "Namespaced";
        labels = baseLabels;
        additionalPrinterColumns = [
          { name = "Source"; type = "string"; jsonPath = ".spec.source.repository"; };
          { name = "Branch"; type = "string"; jsonPath = ".spec.source.branch"; };
          { name = "Phase"; type = "string"; jsonPath = ".status.phase"; };
          { name = "Image"; type = "string"; jsonPath = ".status.image"; };
          { name = "Age"; type = "date"; jsonPath = ".metadata.creationTimestamp"; };
        ];
        subresources = { status = {}; };
      };

      # RBAC
      rbac = {
        serviceAccount = mkServiceAccount {
          name = cfg.name;
          namespace = cfg.namespace;
          labels = baseLabels;
        };

        clusterRole = mkClusterRole {
          name = cfg.name;
          labels = baseLabels;
          rules = [
            {
              apiGroups = [ "" ];
              resources = [ "pods" "secrets" "configmaps" "namespaces" "events" ];
              verbs = [ "get" "list" "watch" "create" "update" "patch" "delete" ];
            }
            {
              apiGroups = [ "batch" ];
              resources = [ "jobs" "cronjobs" ];
              verbs = [ "get" "list" "watch" "create" "update" "patch" "delete" ];
            }
            {
              apiGroups = [ "opendesk.io" ];
              resources = [ "imagebuilds" ];
              verbs = [ "get" "list" "watch" "create" "update" "patch" "delete" ];
            }
          ];
        };

        roleBinding = mkClusterRoleBinding {
          name = cfg.name;
          roleRef = {
            apiGroup = "rbac.authorization.k8s.io";
            kind = "ClusterRole";
            name = cfg.name;
          };
          subjects = [
            {
              kind = "ServiceAccount";
              name = cfg.name;
              namespace = cfg.namespace;
            }
          ];
          labels = baseLabels;
        };
      };

      # Deployment
      deployment = mkDeployment {
        name = cfg.name;
        namespace = cfg.namespace;
        replicas = cfg.replicas;
        image = "${cfg.image}:${cfg.tag}";
        serviceAccountName = cfg.name;
        labels = baseLabels;
        resources = {
          limits = { cpu = "1"; memory = "1Gi"; };
          requests = { cpu = "200m"; memory = "512Mi"; };
        };
        args = [
          "--operator-name=${cfg.name}"
          "--watch-namespaces=${builtins.concatStringsSep "," cfg.watchNamespaces}"
          "--builder-tool=${cfg.builderTool}"
          "--max-concurrent-builds=${toString cfg.maxConcurrentBuilds}"
          "--enable-signing=${if cfg.enableSigning then "true" else "false"}"
          "--keyless-signing=${if cfg.keylessSigning then "true" else "false"}"
          "--enable-attestations=${if cfg.enableAttestations then "true" else "false"}"
          "--attestation-types=${builtins.concatStringsSep "," cfg.attestationTypes}"
        ];
        env = [
          { name = "OPERATOR_NAME"; value = cfg.name; };
          { name = "OPERATOR_NAMESPACE"; valueFrom = { fieldRef = { fieldPath = "metadata.namespace"; }; }; };
          { name = "BUILDER_TOOL"; value = cfg.builderTool; };
          { name = "MAX_CONCURRENT_BUILDS"; value = toString cfg.maxConcurrentBuilds; };
        ];
        livenessProbe = {
          httpGet = { path = "/healthz"; port = 8082; scheme = "HTTP"; };
          initialDelaySeconds = 10;
          periodSeconds = 30;
          timeoutSeconds = 5;
        };
        readinessProbe = {
          httpGet = { path = "/readyz"; port = 8082; scheme = "HTTP"; };
          initialDelaySeconds = 5;
          periodSeconds = 15;
          timeoutSeconds = 3;
        };
      };

      manifest = [
        ImageBuildCRD
        rbac.serviceAccount
        rbac.clusterRole
        rbac.roleBinding
        deployment
      ];
    };

  # ---------------------------------------------------------------------------
  # IMAGE INVENTORY OPERATOR
  # Discovers and tracks images in the cluster
  # ---------------------------------------------------------------------------

  imageInventoryOperator = { 
    name ? "opendesk-image-inventory-operator",
    namespace ? defaultNamespace,
    image ? "ghcr.io/tobias-weiss-ai-xr/opendesk-image-inventory-operator:latest",
    tag ? "latest",
    replicas ? 1,
    watchNamespaces ? [ "default" "opendesk" "kube-system" ],
    scanOnDiscovery ? true,
    scanInterval ? "1h",
    maxConcurrentScans ? 10,
    ...
  }@opts:
    let
      cfg = opts;
      baseLabels = defaultLabels // {
        "app.kubernetes.io/name" = cfg.name;
        "app.kubernetes.io/component" = "image-inventory-operator";
      };
    in {
      config = {
        watchNamespaces = cfg.watchNamespaces;
        scanConfig = {
          onDiscovery = cfg.scanOnDiscovery;
          interval = cfg.scanInterval;
          maxConcurrent = cfg.maxConcurrentScans;
        };
      };

      # CRD for ImageInventory
      ImageInventoryCRD = mkCustomResourceDefinition {
        name = "imageinventory";
        group = "opendesk.io";
        version = "v1";
        kind = "ImageInventory";
        plural = "imageinventories";
        shortNames = [ "ii" ];
        scope = "Namespaced";
        labels = baseLabels;
        additionalPrinterColumns = [
          { name = "Namespace"; type = "string"; jsonPath = ".spec.namespace"; };
          { name = "Images"; type = "integer"; jsonPath = ".status.imageCount"; };
          { name = "Scanned"; type = "integer"; jsonPath = ".status.scannedCount"; };
          { name = "Vulnerable"; type = "integer"; jsonPath = ".status.vulnerableCount"; };
          { name = "Age"; type = "date"; jsonPath = ".metadata.creationTimestamp"; };
        ];
        subresources = { status = {}; };
      };

      # RBAC
      rbac = {
        serviceAccount = mkServiceAccount {
          name = cfg.name;
          namespace = cfg.namespace;
          labels = baseLabels;
        };

        clusterRole = mkClusterRole {
          name = cfg.name;
          labels = baseLabels;
          rules = [
            {
              apiGroups = [ "" ];
              resources = [ "pods" "replicationcontrollers" "namespaces" "secrets" "configmaps" ];
              verbs = [ "get" "list" "watch" ];
            }
            {
              apiGroups = [ "apps" ];
              resources = [ "deployments" "statefulsets" "daemonsets" "replicasets" ];
              verbs = [ "get" "list" "watch" ];
            }
            {
              apiGroups = [ "batch" ];
              resources = [ "jobs" "cronjobs" ];
              verbs = [ "get" "list" "watch" ];
            }
            {
              apiGroups = [ "opendesk.io" ];
              resources = [ "imageinventories" ];
              verbs = [ "get" "list" "watch" "create" "update" "patch" "delete" ];
            }
          ];
        };

        roleBinding = mkClusterRoleBinding {
          name = cfg.name;
          roleRef = {
            apiGroup = "rbac.authorization.k8s.io";
            kind = "ClusterRole";
            name = cfg.name;
          };
          subjects = [
            {
              kind = "ServiceAccount";
              name = cfg.name;
              namespace = cfg.namespace;
            }
          ];
          labels = baseLabels;
        };
      };

      # Deployment
      deployment = mkDeployment {
        name = cfg.name;
        namespace = cfg.namespace;
        replicas = cfg.replicas;
        image = "${cfg.image}:${cfg.tag}";
        serviceAccountName = cfg.name;
        labels = baseLabels;
        args = [
          "--operator-name=${cfg.name}"
          "--watch-namespaces=${builtins.concatStringsSep "," cfg.watchNamespaces}"
          "--scan-on-discovery=${if cfg.scanOnDiscovery then "true" else "false"}"
          "--scan-interval=${cfg.scanInterval}"
          "--max-concurrent-scans=${toString cfg.maxConcurrentScans}"
        ];
        env = [
          { name = "OPERATOR_NAME"; value = cfg.name; };
          { name = "OPERATOR_NAMESPACE"; valueFrom = { fieldRef = { fieldPath = "metadata.namespace"; }; }; };
          { name = "WATCH_NAMESPACES"; value = builtins.concatStringsSep "," cfg.watchNamespaces; };
          { name = "SCAN_INTERVAL"; value = cfg.scanInterval; };
        ];
        livenessProbe = {
          httpGet = { path = "/healthz"; port = 8083; scheme = "HTTP"; };
          initialDelaySeconds = 15;
          periodSeconds = 60;
          timeoutSeconds = 5;
        };
        readinessProbe = {
          httpGet = { path = "/readyz"; port = 8083; scheme = "HTTP"; };
          initialDelaySeconds = 5;
          periodSeconds = 30;
          timeoutSeconds = 3;
        };
      };

      manifest = [
        ImageInventoryCRD
        rbac.serviceAccount
        rbac.clusterRole
        rbac.roleBinding
        deployment
      ];
    };

  # ---------------------------------------------------------------------------
  # POLICY ENFORCER OPERATOR
  # Enforces security policies using Kyverno/OPA/Gatekeeper
  # ---------------------------------------------------------------------------

  policyEnforcerOperator = { 
    name ? "opendesk-policy-enforcer-operator",
    namespace ? defaultNamespace,
    image ? "ghcr.io/tobias-weiss-ai-xr/opendesk-policy-enforcer-operator:latest",
    tag ? "latest",
    replicas ? 1,
    watchNamespaces ? [ "default" "opendesk" ],
    enableKyverno ? true,
    enableOPA ? false,
    enableGatekeeper ? false,
    validationFailureAction ? "enforce",
    auditInterval ? "5m",
    ...
  }@opts:
    let
      cfg = opts;
      baseLabels = defaultLabels // {
        "app.kubernetes.io/name" = cfg.name;
        "app.kubernetes.io/component" = "policy-enforcer-operator";
      };
    in {
      config = {
        watchNamespaces = cfg.watchNamespaces;
        engines = {
          kyverno = {
            enable = cfg.enableKyverno;
            image = "ghcr.io/kyverno/kyverno:v1.12.0";
          };
          opa = {
            enable = cfg.enableOPA;
            image = "openpolicyagent/opa:0.60.0";
          };
          gatekeeper = {
            enable = cfg.enableGatekeeper;
            image = "openpolicyagent/gatekeeper:v3.15.0";
          };
        };
        behavior = {
          validationFailureAction = cfg.validationFailureAction;
          auditInterval = cfg.auditInterval;
        };
      };

      # RBAC - Policy enforcer needs broad access
      rbac = {
        serviceAccount = mkServiceAccount {
          name = cfg.name;
          namespace = cfg.namespace;
          labels = baseLabels;
        };

        clusterRole = mkClusterRole {
          name = cfg.name;
          labels = baseLabels;
          rules = [
            {
              apiGroups = [ "" ];
              resources = [ "*" ];
              verbs = [ "get" "list" "watch" "create" "update" "patch" "delete" ];
            }
            {
              apiGroups = [ "apps" ];
              resources = [ "*" ];
              verbs = [ "get" "list" "watch" "create" "update" "patch" "delete" ];
            }
            {
              apiGroups = [ "batch" ];
              resources = [ "*" ];
              verbs = [ "get" "list" "watch" "create" "update" "patch" "delete" ];
            }
            {
              apiGroups = [ "kyverno.io" ];
              resources = [ "*" ];
              verbs = [ "get" "list" "watch" "create" "update" "patch" "delete" ];
            }
            {
              apiGroups = [ "constraints.gatekeeper.sh" ];
              resources = [ "*" ];
              verbs = [ "get" "list" "watch" "create" "update" "patch" "delete" ];
            }
            {
              apiGroups = [ "opendesk.io" ];
              resources = [ "*" ];
              verbs = [ "get" "list" "watch" "create" "update" "patch" "delete" ];
            }
          ];
        };

        roleBinding = mkClusterRoleBinding {
          name = cfg.name;
          roleRef = {
            apiGroup = "rbac.authorization.k8s.io";
            kind = "ClusterRole";
            name = cfg.name;
          };
          subjects = [
            {
              kind = "ServiceAccount";
              name = cfg.name;
              namespace = cfg.namespace;
            }
          ];
          labels = baseLabels;
        };
      };

      # Deployment
      deployment = mkDeployment {
        name = cfg.name;
        namespace = cfg.namespace;
        replicas = cfg.replicas;
        image = "${cfg.image}:${cfg.tag}";
        serviceAccountName = cfg.name;
        labels = baseLabels;
        args = [
          "--operator-name=${cfg.name}"
          "--watch-namespaces=${builtins.concatStringsSep "," cfg.watchNamespaces}"
          "--kyverno-enable=${if cfg.enableKyverno then "true" else "false"}"
          "--opa-enable=${if cfg.enableOPA then "true" else "false"}"
          "--gatekeeper-enable=${if cfg.enableGatekeeper then "true" else "false"}"
          "--validation-failure-action=${cfg.validationFailureAction}"
          "--audit-interval=${cfg.auditInterval}"
        ];
        env = [
          { name = "OPERATOR_NAME"; value = cfg.name; };
          { name = "OPERATOR_NAMESPACE"; valueFrom = { fieldRef = { fieldPath = "metadata.namespace"; }; }; };
          { name = "KYVERNO_ENABLE"; value = if cfg.enableKyverno then "true" else "false"; };
          { name = "VALIDATION_FAILURE_ACTION"; value = cfg.validationFailureAction; };
        ];
        livenessProbe = {
          httpGet = { path = "/healthz"; port = 8084; scheme = "HTTP"; };
          initialDelaySeconds = 10;
          periodSeconds = 30;
          timeoutSeconds = 5;
        };
        readinessProbe = {
          httpGet = { path = "/readyz"; port = 8084; scheme = "HTTP"; };
          initialDelaySeconds = 5;
          periodSeconds = 15;
          timeoutSeconds = 3;
        };
      };

      manifest = [
        rbac.serviceAccount
        rbac.clusterRole
        rbac.roleBinding
        deployment
      ];
    };

  # ---------------------------------------------------------------------------
  # SECURITY SCANNER OPERATOR
  # Dedicated operator for scanning running workloads
  # ---------------------------------------------------------------------------

  securityScannerOperator = { 
    name ? "opendesk-security-scanner-operator",
    namespace ? defaultNamespace,
    image ? "ghcr.io/tobias-weiss-ai-xr/opendesk-security-scanner-operator:latest",
    tag ? "latest",
    replicas ? 1,
    watchNamespaces ? [ "default" "opendesk" ],
    scannerTypes ? [ "grype" "trivy" ],
    schedule ? "0 2 * * *",
    scanNewPods ? true,
    scanUpdatedPods ? true,
    ...
  }@opts:
    let
      cfg = opts;
      baseLabels = defaultLabels // {
        "app.kubernetes.io/name" = cfg.name;
        "app.kubernetes.io/component" = "security-scanner-operator";
      };
    in {
      config = {
        watchNamespaces = cfg.watchNamespaces;
        scannerTypes = cfg.scannerTypes;
        schedule = cfg.schedule;
        scanNewPods = cfg.scanNewPods;
        scanUpdatedPods = cfg.scanUpdatedPods;
      };

      # RBAC
      rbac = {
        serviceAccount = mkServiceAccount {
          name = cfg.name;
          namespace = cfg.namespace;
          labels = baseLabels;
        };

        clusterRole = mkClusterRole {
          name = cfg.name;
          labels = baseLabels;
          rules = [
            {
              apiGroups = [ "" ];
              resources = [ "pods" "replicationcontrollers" "namespaces" "events" ];
              verbs = [ "get" "list" "watch" ];
            }
            {
              apiGroups = [ "apps" ];
              resources = [ "deployments" "statefulsets" "daemonsets" "replicasets" ];
              verbs = [ "get" "list" "watch" ];
            }
            {
              apiGroups = [ "batch" ];
              resources = [ "jobs" "cronjobs" ];
              verbs = [ "get" "list" "watch" "create" "update" "patch" "delete" ];
            }
          ];
        };

        roleBinding = mkClusterRoleBinding {
          name = cfg.name;
          roleRef = {
            apiGroup = "rbac.authorization.k8s.io";
            kind = "ClusterRole";
            name = cfg.name;
          };
          subjects = [
            {
              kind = "ServiceAccount";
              name = cfg.name;
              namespace = cfg.namespace;
            }
          ];
          labels = baseLabels;
        };
      };

      # Deployment
      deployment = mkDeployment {
        name = cfg.name;
        namespace = cfg.namespace;
        replicas = cfg.replicas;
        image = "${cfg.image}:${cfg.tag}";
        serviceAccountName = cfg.name;
        labels = baseLabels;
        args = [
          "--scan-schedule=${cfg.schedule}"
          "--scan-new-pods=${if cfg.scanNewPods then "true" else "false"}"
          "--scan-updated-pods=${if cfg.scanUpdatedPods then "true" else "false"}"
          "--scanners=${builtins.concatStringsSep "," cfg.scannerTypes}"
        ];
        env = [
          { name = "POD_NAMESPACE"; valueFrom = { fieldRef = { fieldPath = "metadata.namespace"; }; }; };
          { name = "SCAN_SCHEDULE"; value = cfg.schedule; };
        ];
        livenessProbe = {
          httpGet = { path = "/healthz"; port = 8085; scheme = "HTTP"; };
          initialDelaySeconds = 10;
          periodSeconds = 30;
        };
        readinessProbe = {
          httpGet = { path = "/readyz"; port = 8085; scheme = "HTTP"; };
          initialDelaySeconds = 5;
          periodSeconds = 15;
        };
      };

      manifest = [
        rbac.serviceAccount
        rbac.clusterRole
        rbac.roleBinding
        deployment
      ];
    };

  # ---------------------------------------------------------------------------
  # ATTESTATION COLLECTOR OPERATOR
  # Manages attestations for built and deployed images
  # ---------------------------------------------------------------------------

  attestationCollectorOperator = { 
    name ? "opendesk-attestation-collector-operator",
    namespace ? defaultNamespace,
    image ? "ghcr.io/tobias-weiss-ai-xr/opendesk-attestation-collector-operator:latest",
    tag ? "latest",
    replicas ? 1,
    storageBackend ? "in-cluster",
    retentionPeriod ? "30d",
    validateAttestations ? true,
    ...
  }@opts:
    let
      cfg = opts;
      baseLabels = defaultLabels // {
        "app.kubernetes.io/name" = cfg.name;
        "app.kubernetes.io/component" = "attestation-collector-operator";
      };
    in {
      config = {
        storageBackend = cfg.storageBackend;
        retentionPeriod = cfg.retentionPeriod;
        validation = {
          enable = cfg.validateAttestations;
        };
        attestationTypes = compliance.attestationTypes;
      };

      # RBAC
      rbac = {
        serviceAccount = mkServiceAccount {
          name = cfg.name;
          namespace = cfg.namespace;
          labels = baseLabels;
        };

        clusterRole = mkClusterRole {
          name = cfg.name;
          labels = baseLabels;
          rules = [
            {
              apiGroups = [ "" ];
              resources = [ "secrets" "configmaps" "namespaces" ];
              verbs = [ "get" "list" "watch" "create" "update" "patch" "delete" ];
            }
            {
              apiGroups = [ "opendesk.io" ];
              resources = [ "*" ];
              verbs = [ "get" "list" "watch" "create" "update" "patch" "delete" ];
            }
          ];
        };

        roleBinding = mkClusterRoleBinding {
          name = cfg.name;
          roleRef = {
            apiGroup = "rbac.authorization.k8s.io";
            kind = "ClusterRole";
            name = cfg.name;
          };
          subjects = [
            {
              kind = "ServiceAccount";
              name = cfg.name;
              namespace = cfg.namespace;
            }
          ];
          labels = baseLabels;
        };
      };

      # Deployment
      deployment = mkDeployment {
        name = cfg.name;
        namespace = cfg.namespace;
        replicas = cfg.replicas;
        image = "${cfg.image}:${cfg.tag}";
        serviceAccountName = cfg.name;
        labels = baseLabels;
        args = [
          "--storage-backend=${cfg.storageBackend}"
          "--retention-period=${cfg.retentionPeriod}"
          "--validate-attestations=${if cfg.validateAttestations then "true" else "false"}"
        ];
        env = [
          { name = "OPERATOR_NAME"; value = cfg.name; };
          { name = "STORAGE_BACKEND"; value = cfg.storageBackend; };
          { name = "RETENTION_PERIOD"; value = cfg.retentionPeriod; };
        ];
        livenessProbe = {
          httpGet = { path = "/healthz"; port = 8086; scheme = "HTTP"; };
          initialDelaySeconds = 10;
          periodSeconds = 30;
        };
        readinessProbe = {
          httpGet = { path = "/readyz"; port = 8086; scheme = "HTTP"; };
          initialDelaySeconds = 5;
          periodSeconds = 15;
        };
      };

      manifest = [
        rbac.serviceAccount
        rbac.clusterRole
        rbac.roleBinding
        deployment
      ];
    };

  # ---------------------------------------------------------------------------
  # ALL OPERATORS
  # ---------------------------------------------------------------------------

  allOperators = let
    baseOps = [
      complianceOperator
      imageBuilderOperator
      imageInventoryOperator
      policyEnforcerOperator
      securityScannerOperator
      attestationCollectorOperator
    ];
  in map (op: op {}) baseOps;

  # ---------------------------------------------------------------------------
  # OPERATOR SELECTOR AND FILTERS
  # ---------------------------------------------------------------------------

  selectOperators = { types ? [], enabled ? [], disabled ? [], ... }:
    filter (op: 
      let
        typeMatch = if types == [] then true else lib.elem op.name types;
        enabledMatch = if enabled == [] then true else lib.elem op.name enabled;
        disabledMatch = if disabled == [] then true else ! (lib.elem op.name disabled);
      in typeMatch && enabledMatch && disabledMatch
    ) allOperators;

  # Select operators by namespaces
  operatorsForNamespace = { namespace, watchNamespaces ? [ namespace ] }:
    let
      matching = filter (op: 
        lib.elem namespace op.config.watchNamespaces || 
        lib.elem namespace watchNamespaces
      ) allOperators;
    in matching;

  # ---------------------------------------------------------------------------
  # DEPLOYMENT HELPERS
  # ---------------------------------------------------------------------------

  # Generate complete deployment manifest for all operators
  deployAll = { namespace ? defaultNamespace, operators ? allOperators, ... }:
    let
      # Create namespace if it doesn't exist
      nsManifest = {
        apiVersion = "v1";
        kind = "Namespace";
        metadata = {
          name = namespace;
          labels = defaultLabels // {
            name = namespace;
          };
        };
      };
      
      # Collect all manifests from all operators
      allManifests = concatMap (op: op.manifest) operators;
    in [ nsManifest ] ++ allManifests;

  # Generate manifest for specific operator
  deployOperator = { name, namespace ? defaultNamespace, ... }:
    let
      operator = lib.head (selectOperators { enabled = [ name ]; });
    in if operator == null then throw "Operator ${name} not found" else operator.manifest;

  # Generate Kustomize configuration
  mkKustomization = { namespace ? defaultNamespace, operators ? allOperators, ... }:
    {
      apiVersion = "kustomize.config.k8s.io/v1beta1";
      kind = "Kustomization";
      namespace = namespace;
      resources = map (op: "${op.name}.yaml") operators;
      commonLabels = defaultLabels;
      images = map (op: {
        name = "${op.name}";
        newName = op.deployment.spec.template.spec.containers.0.image;
        newTag = "latest";
      }) operators;
    };

  # ---------------------------------------------------------------------------
  # EXPORT
  # ---------------------------------------------------------------------------

  inherit allOperators selectOperators operatorsForNamespace;
  inherit deployAll deployOperator mkKustomization;
  
  inherit complianceOperator imageBuilderOperator imageInventoryOperator;
  inherit policyEnforcerOperator securityScannerOperator attestationCollectorOperator;

  # Helpers
  inherit mkMetadata mkServiceAccount mkClusterRole mkClusterRoleBinding;
  inherit mkRoleBinding mkCustomResourceDefinition mkDeployment mkConfigMap mkSecret;
}
