# openDesk Edu - Documentation Generator Library
#
# This library provides functions to generate documentation from Nix expressions.
# It creates API documentation, README files, and examples for all libraries.
#
# Usage:
#   let
#     lib = import ./lib { system = "x86_64-linux"; };
#   in {
#     packages.documentation = lib.docs.generateAllDocs;
#   }

{ pkgs, lib, ... }:

let
  # ============================================================================
  # Markdown Generation Utilities
  # ============================================================================

  # Escape markdown special characters
  escapeMarkdown = str:
    lib.replaceStrings ["`" "*" "_" "[" "]" "{" "}"]
                       ["\\`" "\\*" "\\_" "\\[" "\\]" "\\{" "\\}"]
                       str;

  # Generate code block
  codeBlock = lang: code:
    "```${lang}\n${code}\n```";

  # Generate header
  header = level: text:
    "${lib.replicate level "#" } ${text}\n";

  # Generate table row
  tableRow = cells:
    "| ${lib.concatStringsSep " | " cells} |\n";

  # Generate table header
  tableHeader = headers:
    tableRow headers + tableHeaderSeparator (length headers);

  # Generate table header separator
  tableHeaderSeparator = count:
    lib.concatStringsSep "" (lib.genList (_i: "---|") count) + "\n";

  # ============================================================================
  # Function Documentation
  # ============================================================================

  # Generate documentation for a single function
  generateFunctionDoc = name: func: description: examples: ''
    ### ${name}

    ${description}

    **Type:**
    ${codeBlock "nix" (toString (lib.typeOf func))}

    **Parameters:**
    ${generateParametersDoc func}

    **Returns:**
    ${generateReturnsDoc func}

    **Examples:**
    ${lib.concatMapStrings (example: codeBlock "nix" example) examples}
  '';

  # Generate parameters documentation
  generateParametersDoc = func:
    let
      args = lib.functionArgs func;
    in
    if args == []
    then "No parameters."
    else
      tableHeader [ "Parameter" "Type" "Required" "Description" ] +
      lib.concatMapStrings (arg:
        tableRow [
          (escapeMarkdown arg)
          "any"
          "Yes"
          "Parameter `${arg}`"
        ]
      ) args;

  # Generate returns documentation
  generateReturnsDoc = func:
    let
      returnType = toString (lib.typeOf func);
    in
    "Returns a ${escapeMarkdown returnType}.";

  # ============================================================================
  # Library Documentation
  # ============================================================================

  # Generate README for a library
  generateLibraryReadme = { name, description, functions, examples ? [] }: ''
    # ${name}

    ${description}

    ## Functions

    ${lib.concatMapStrings (f: generateFunctionDoc f.name f.func f.description f.examples) functions}

    ## Examples

    ${lib.concatMapStrings (example: codeBlock "nix" example) examples}

    ## License

    This library is part of openDesk Edu and is licensed under the Apache License 2.0.
  '';

  # ============================================================================
  # k8s.nix Documentation
  # ============================================================================

  k8s-docs = generateLibraryReadme {
    name = "lib/k8s.nix";
    description = ''
      Kubernetes resource generation library for openDesk Edu.

      This library provides helper functions to create Kubernetes manifests
      from Nix expressions, ensuring consistency and reducing boilerplate.
    '';
    functions = [
      {
        name = "mkDeployment";
        func = { replicas ? 1 }: {};
        description = ''
          Create a Kubernetes Deployment resource.

          Generates a Deployment manifest with the specified configuration.
          Includes default security contexts and resource limits.
        '';
        examples = [
          ''
            lib.k8s.mkDeployment {
              name = "mariadb";
              image = "mariadb:11.4.4";
              ports = [ { containerPort = 3306; } ];
              resources = {
                requests.memory = "512Mi";
                requests.cpu = "250m";
              };
            }
          ''
        ];
      }
      {
        name = "mkService";
        func = { type ? "ClusterIP" }: {};
        description = ''
          Create a Kubernetes Service resource.

          Generates a Service manifest to expose deployments.
        '';
        examples = [
          ''
            lib.k8s.mkService {
              name = "mariadb";
              ports = [
                { name = "mysql"; port = 3306; targetPort = 3306; }
              ];
            }
          ''
        ];
      }
      {
        name = "mkConfigMap";
        func = { data }: {};
        description = ''
          Create a Kubernetes ConfigMap resource.

          Generates a ConfigMap with the specified key-value pairs.
        '';
        examples = [
          ''
            lib.k8s.mkConfigMap {
              name = "app-config";
              data = {
                "config.yaml" = ''
                  _key: value
                '';
              };
            }
          ''
        ];
      }
      {
        name = "mkSecret";
        func = { type ? "Opaque" }: {};
        description = ''
          Create a Kubernetes Secret resource.

          Generates a Secret with base64-encoded values.
        '';
        examples = [
          ''
            lib.k8s.mkSecret {
              name = "db-credentials";
              type = "Opaque";
              data = {
                "username" = "admin";
                "password" = "secret";
              };
            }
          ''
        ];
      }
      {
        name = "mkNamespace";
        func = { labels ? {} }: {};
        description = ''
          Create a Kubernetes Namespace resource.

          Generates a Namespace with optional labels.
        '';
        examples = [
          ''
            lib.k8s.mkNamespace {
              name = "opendesk";
              labels = {
                "app.kubernetes.io/part-of" = "opendesk-edu";
              };
            }
          ''
        ];
      }
      {
        name = "mkRBAC";
        func = { rules }: {};
        description = ''
          Create Kubernetes RBAC resources (Role, RoleBinding, ServiceAccount).

          Generates Role, RoleBinding, and ServiceAccount for the specified rules.
        '';
        examples = [
          ''
            lib.k8s.mkRBAC {
              name = "operator";
              namespace = "opendesk";
              rules = [
                {
                  apiGroups = [ "" ];
                  resources = [ "pods" ];
                  verbs = [ "get" "list" "watch" ];
                }
              ];
            }
          ''
        ];
      }
    ];
    examples = [
      ''
        # Complete deployment example
        let
          deployment = lib.k8s.mkDeployment {
            name = "my-app";
            image = "my-app:latest";
            ports = [ { containerPort = 8080; } ];
            resources = {
              requests.memory = "256Mi";
              requests.cpu = "100m";
            };
          };
        in deployment
      ''
    ];
  };

  # ============================================================================
  # Security.nix Documentation
  # ============================================================================

  security-docs = generateLibraryReadme {
    name = "lib/security.nix";
    description = ''
      Security configuration library for openDesk Edu.

      This library provides functions to create secure Kubernetes configurations
      following ZKI-IT-Grundschutz and BSI best practices.
    '';
    functions = [
      {
        name = "mkSecurityContext";
        func = { readOnlyRootFilesystem ? true }: {};
        description = ''
          Create a secure container security context.

          Generates security context with hardened defaults.
        '';
        examples = [
          ''
            lib.security.mkSecurityContext {
              runAsNonRoot = true;
              readOnlyRootFilesystem = true;
              allowPrivilegeEscalation = false;
            }
          ''
        ];
      }
      {
        name = "mkNetworkPolicy";
        func = { egress ? [] }: {};
        description = ''
          Create a Kubernetes NetworkPolicy.

          Generates NetworkPolicy for network segmentation.
        '';
        examples = [
          ''
            lib.security.mkNetworkPolicy {
              name = "default-deny";
              namespace = "opendesk";
            }
          ''
        ];
      }
      {
        name = "mkKyvernoPolicy";
        func = { validationFailureAction ? "enforce" }: {};
        description = ''
          Create a Kyverno ClusterPolicy.

          Generates Kyverno policy for admission control.
        '';
        examples = [
          ''
            lib.security.mkKyvernoPolicy {
              name = "require-non-root";
              rules = [
                {
                  name = "run-as-non-root";
                  context = [ /* ... */ ];
                }
              ];
            }
          ''
        ];
      }
    ];
    examples = [
      ''
        # Complete security configuration
        let
          securityContext = lib.security.mkSecurityContext { };
          networkPolicy = lib.security.mkNetworkPolicy {
            name = "default-deny";
            namespace = "opendesk";
          };
        in {
          deployments = [ securityContext ];
          networkPolicies = [ networkPolicy ];
        }
      ''
    ];
  };

  # ============================================================================
  # Operators.nix Documentation
  # ============================================================================

  operators-docs = generateLibraryReadme {
    name = "lib/operators.nix";
    description = ''
      Kubernetes Operators library for openDesk Edu.

      This library provides Nix expressions for deploying and managing
      Kubernetes Operators for compliance automation and image building.
    '';
    functions = [
      {
        name = "compliance-operator";
        func = { checkpoints }: {};
        description = ''
          Compliance Operator for ZKI-IT-Grundschutz automation.

          Provides automated compliance checks and reporting.
        '';
        examples = [
          ''
            let
              operator = lib.operators.compliance-operator;
            in {
              crds = [ operator.crd ];
              deployments = [ operator.deployment ];
            }
          ''
        ];
      }
      {
        name = "image-builder-operator";
        func = { rbac }: {};
        description = ''
          Image Builder Operator for automated Nix builds.

          Provides automated container image building from Nix expressions.
        '';
        examples = [
          ''
            let
              operator = lib.operators.image-builder-operator;
            in {
              crds = [ operator.crd ];
              deployments = [ operator.deployment ];
            }
          ''
        ];
      }
    ];
    examples = [
      ''
        # Deploy all operators
        let
          operators = lib.operators.all-operators;
        in {
          crds = operators.crds;
          deployments = operators.deployments;
          rbac = operators.rbac;
        }
      ''
    ];
  };

  # ============================================================================
  # Combined Documentation
  # ============================================================================

  combined-docs = pkgs.runCommand "opendesk-nix-docs" { } ''
    mkdir -p $out/docs/lib
    
    # Generate individual library docs
    echo "${k8s-docs}" > $out/docs/lib/k8s.md
    echo "${security-docs}" > $out/docs/lib/security.md
    echo "${operators-docs}" > $out/docs/lib/operators.md
    
    # Generate combined index
    cat > $out/index.md << 'EOF'
    # openDesk Edu Library Documentation

    This documentation covers all libraries provided by openDesk Edu.

    ## Libraries

    - [k8s.nix](docs/lib/k8s.md) - Kubernetes resource generation
    - [security.nix](docs/lib/security.md) - Security configuration
    - [operators.nix](docs/lib/operators.md) - Kubernetes Operators

    ## Quick Start

    ```nix
    let
      lib = import ./lib { system = "x86_64-linux"; };
    in {
      packages.my-deployment = lib.k8s.mkDeployment {
        name = "my-app";
        image = "my-app:latest";
      };
    }
    ```

    ## License

    This documentation is part of openDesk Edu and is licensed under
    the Apache License 2.0.
    EOF
    
    touch $out/DocumentationGenerated
  '';

  # ============================================================================
  # Export
  # ============================================================================

in {
  # Individual library documentation
  k8s-docs = pkgs.writeText "k8s-docs.md" k8s-docs;
  security-docs = pkgs.writeText "security-docs.md" security-docs;
  operators-docs = pkgs.writeText "operators-docs.md" operators-docs;

  # Combined documentation
  all-docs = combined-docs;

  # Helper function to generate docs for any library
  generateDocs = { name, description, functions, examples ? [] }:
    pkgs.writeText "${name}-docs.md"
      (generateLibraryReadme { inherit name description functions examples; });

  # Markdown generation utilities
  utils = {
    inherit escapeMarkdown codeBlock header tableRow tableHeader;
  };
}
