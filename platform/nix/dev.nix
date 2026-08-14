# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
# Enhanced with DevGuard patterns for security, Kubernetes, and full environments

{ pkgs, lib, ... }:

let
  # =============================================================================
  # DEVGUARD PATTERNS: Common configuration
  # =============================================================================

  # Environment variables for registry authentication
  registryEnv = {
    GITHUB_TOKEN = "";
    OPENCODE_TOKEN = "";
    ZOT_TOKEN = "";
    COSIGN_PASSWORD = "";
    SNYK_TOKEN = "";
    DOCKER_CONFIG = "$HOME/.docker";
  };

  # Common aliases for all shells
  commonAliases = ''
    # Git aliases
    alias gs='git status'
    alias ga='git add'
    alias gc='git commit -m'
    alias gco='git checkout'
    alias gb='git branch'
    alias gp='git push'
    alias gl='git pull'
    alias gf='git fetch'
    alias gd='git diff'
    alias gdc='git diff --cached'

    # Navigation
    alias ..='cd ..'
    alias ...='cd ../..'
    alias ....='cd ../../..'
    alias l='ls -la'
    alias ll='ls -lha'
    alias la='ls -A'

    # Nix
    alias nix-build='nix build .#'
    alias nix-run='nix run .#'
    alias nix-dev='nix develop'
    alias nix-shell='nix-shell'
    alias nix-env='nix-env'
    alias nix-gc='nix-collect-garbage'
    alias nix-search='nix-env -qaP'
    alias nix-info='nix-env -iA'

    # Docker
    alias d='docker'
    alias dps='docker ps'
    alias dpsa='docker ps -a'
    alias dlogs='docker logs'
    alias dstop='docker stop'
    alias drm='docker rm'
    alias dbuild='docker build'
    alias drun='docker run'
    alias dmulti='docker compose'

    # System
    alias ip='ip -c'
    alias ping='ping -c 3'
    alias wget='wget -c'
    alias curl='curl -v'
    alias head='head -n 20'
    alias tail='tail -n 20'
    alias grep='grep --color=auto'
  '';

  # Common packages for all shells
  commonPackages = with pkgs; [
    git
    curl
    wget
    jq
    yq
    openssl
    gnupg
    gnutls
    cacert
    unzip
    zip
    gnutar
    gzip
    htop
    iftop
    iotop
    lsof
    iproute2
    dnsutils
    whois
    traceroute
    netcat
    socat
    inetutils
    openssh
    rsync
    gnumake
    cmake
    coreutils
    findutils
    diffutils
    patch
    gnused
    gawk
    gnugrep
    gzip
    bzip2
    xz
    pciutils
    usbutils
    file
    wdiff
    colordiff
    tree
    direnv
    yamllint
    shellcheck
    hadolint
    docker-credential-helpers
  ];

  # =============================================================================
  # DEFAULT SHELL
  # =============================================================================

  defaultShell = pkgs.mkShell {
    name = "default";
    buildInputs = commonPackages;
    shellHook = ''
      echo "🎯 OpenDesk-Nix Default Shell"
      echo "============================"
      echo ""
      ${commonAliases}

      # Set registry environment variables if not already set
      ${builtins.concatStringsSep "\n" (
        map (kv: ''
          ${
            if builtins.getEnv kv.name == "" then
              ''export ${kv.name}="${registryEnv.${kv.name}}"''
            else
              "# ${kv.name} already set"
          }
        '') (lib.mapAttrsToList (name: value: { inherit name value; }) registryEnv)
      )}

      echo "Registry config: DOCKER_CONFIG=''${DOCKER_CONFIG}"
      echo ""
      echo "Type 'dev-shells' for available development shells"
    '';
  };

  # =============================================================================
  # SECURITY SHELL - DevGuard Pattern
  # =============================================================================

  securityShell =
    let
      securityPackages = with pkgs; [
        # Vulnerability scanners
        grype
        trivy
        syft

        # Signing and attestations
        cosign
        # in-toto  # not in nixpkgs

        # Additional security tools
        golangci-lint
        semgrep
        gosec
        nuclei
        # trivy-plugin-nodejs  # not in nixpkgs
        # trivy-plugin-python  # not in nixpkgs

        # Malware detection
        clamav

        # Network security
        nmap
        nikto
        masscan

        # Policy and compliance
        conftest
        # checkov  # depends on insecure ecdsa
        tfsec

        # secrets scanning
        gitleaks
        trufflehog
      ];

    in
    pkgs.mkShell {
      name = "security";
      buildInputs = commonPackages ++ securityPackages;
      shellHook = ''
        echo "🔒 OpenDesk-Nix Security Shell"
        echo "=============================="
        echo ""
        echo "Security Tools:"
        echo "  🔍 Scanners: grype, trivy, syft"
        echo "  ✍️  Signing: cosign, in-toto"
        echo "  🛡️  Analysis: semgrep, gosec, nuclei, gitleaks, trufflehog"
        echo "  📊 Compliance: conftest, checkov, tfsec"
        echo "  🌐 Network: nmap, nikto, masscan"
        echo ""
        ${commonAliases}

        # Security-specific aliases
        alias scan='security-scan'
        alias scan-all='security-scan all-images'
        alias scan-single='security-scan'
        alias scan-dir='security-scan directory'
        alias scan-grype='grype'
        alias scan-trivy='trivy fs'
        alias scan-sbom='syft'
        alias sign='cosign sign'
        alias verify='cosign verify'
        alias verify-all='cosign verify --recursive'
        alias attest='in-toto attest'
        alias verify-attest='cosign verify-attestation'
        alias check-policy='conftest test'
        alias check-secrets='gitleaks detect'
        alias check-nmap='nmap -sV'
        alias check-cve='grype --only-cve'

        # Environment setup
        export GRYPE_DB_AUTO_UPDATE=true
        export TRIVY_CACHE_DIR="/root/.cache/trivy"
        export COSIGN_EXPERIMENTAL=1
        export IN_TOTO_EXPERIMENTAL=1

        echo "Security environment configured"
        echo ""
      '';
    };

  # =============================================================================
  # KUBERNETES SHELL - DevGuard Pattern
  # =============================================================================

  k8sShell =
    let
      k8sPackages = with pkgs; [
        # Kubernetes CLI tools
        kubectl
        kubectl-neat
        # kubectl-aliases  # not in nixpkgs
        kubectx
        # kubens  # provided by kubectx
        kubent
        kubescape
        kubeval
        kubeconform

        # Helm and friends
        helm
        # helm-secrets  # not in nixpkgs
        # helm-diff  # not in nixpkgs
        # helm-s3  # not in nixpkgs
        # helm-gcs  # not in nixpkgs
        # helm-azure  # not in nixpkgs
        # helm-git  # not in nixpkgs

        # Kustomize
        kustomize
        # kustomize-editors-schema  # not in nixpkgs

        # Kubernetes IDEs
        k9s
        stern
        # lens  # unfree (Lens desktop license)

        # Service mesh
        istioctl
        linkerd

        # Monitoring
        prometheus

        # Other tools
        yq
        jq
        jsonnet

        # Image tools
        skopeo
        crane
        oras
        dive
      ];

    in
    pkgs.mkShell {
      name = "k8s";
      buildInputs = commonPackages ++ k8sPackages;
      shellHook = ''
        echo "☸️  OpenDesk-Nix Kubernetes Shell"
        echo "================================"
        echo ""
        echo "Kubernetes Tools:"
        echo "  🟢 kubectl with plugins: neat, aliases, ctx, ns, kubent"
        echo "  📦 Helm with plugins: secrets, diff, s3, gcs, azure, git"
        echo "  🎨 Kustomize"
        echo "  🔍 Service mesh: istioctl, linkerd"
        echo "  👁️  Monitoring: stern, k9s, lens"
        echo "  🐳 Image tools: skopeo, crane, oras, dive"
        echo "  🛡️  Security: kubescape, kubeval, kubeconform"
        echo ""
        ${commonAliases}

        # Kubernetes-specific aliases
        alias k='kubectl'
        alias kc='kubectl'
        alias kg='kubectl get'
        alias kgp='kubectl get pods'
        alias kgpa='kubectl get pods --all-namespaces'
        alias kgs='kubectl get services'
        alias kgn='kubectl get nodes'
        alias kgd='kubectl get deployments'
        alias kgds='kubectl get daemonsets'
        alias kgss='kubectl get statefulsets'
        alias kgsa='kubectl get all'
        alias kgpfa='kubectl get pods -o wide --all-namespaces'

        alias kl='kubectl logs'
        alias klt='kubectl logs -f --tail=50'
        alias kld='kubectl logs -p'  # previous instance
        alias kd='kubectl describe'
        alias kx='kubectl exec -it'
        alias kxsh='kubectl exec -it -- /bin/sh'
        alias kxbash='kubectl exec -it -- /bin/bash'

        alias ka='kubectl apply'
        alias kad='kubectl apply -f'
        alias kdel='kubectl delete'
        alias kdelf='kubectl delete -f'
        alias kdeln='kubectl delete --ignore-not-found'
        alias kreplace='kubectl replace'
        alias kpatch='kubectl patch'
        alias kscale='kubectl scale'
        alias krollout='kubectl rollout'
        alias kport='kubectl port-forward'
        alias kproxy='kubectl proxy'
        alias kcp='kubectl cp'
        alias kapi='kubectl api-resources'
        alias kevents='kubectl get events --sort-by='.{metadata.creationTimestamp}'
        alias ktop='kubectl top'

        # Helm aliases
        alias h='helm'
        alias hi='helm install'
        alias hu='helm upgrade'
        alias hr='helm uninstall'
        alias hs='helm show'
        alias hg='helm get'
        alias hl='helm list'
        alias hf='helm fetch'
        alias hp='helm pull'
        alias hx='helm export'
        alias htemplate='helm template'
        alias hlint='helm lint'
        alias htest='helm test'
        alias hrepo='helm repo'
        alias hsearch='helm search'

        # Kustomize aliases
        alias kz='kustomize'
        alias kzbuild='kustomize build'
        alias kzedit='kustomize edit'

        # Other aliases
        alias sk='skopeo'
        alias cr='crane'
        alias or='oras'
        alias dv='dive'

        # K9s
        alias k9s='k9s'

        # Stern
        alias stern='stern'
        alias stderr='stern --error'

        # Context and namespace management
        alias kns='kubens'
        alias kcx='kubectx'

        # DevGuard pattern: Set default context and namespace
        if [ -n "$K8S_CONTEXT" ]; then
          kubectx "$K8S_CONTEXT"
        fi
        if [ -n "$K8S_NAMESPACE" ]; then
          kubens "$K8S_NAMESPACE"
        fi

        # DevGuard pattern: Configure tab completion
        source <(${pkgs.kubectl}/bin/kubectl completion bash)
        complete -o default -F __start_kubectl k
        complete -o default -F __start_kubectl kubectl
        complete -o default -F __start_helm helm

        echo "Kubernetes environment configured"
        echo "Context: $(kubectx -c 2>/dev/null || echo 'none')"
        echo "Namespace: $(kubens -c 2>/dev/null || echo 'default')"
        echo ""
      '';
    };

  # =============================================================================
  # FULL SHELL - DevGuard Pattern
  # =============================================================================

  fullShell =
    let
      fullPackages = with pkgs; [
        # Security packages
        grype
        trivy
        syft
        cosign
        # in-toto  # not in nixpkgs
        semgrep
        gosec
        nuclei

        # Kubernetes packages
        kubectl
        helm
        kustomize
        k9s
        stern
        linkerd
        istioctl

        # Container packages
        docker
        skopeo
        crane
        oras
        dive

        # Development packages
        go
        nodejs
        python3
        # python3Packages.virtualenv  # depends on insecure ecdsa
        # python3Packages.pip  # depends on insecure ecdsa

        # Build packages
        gnumake
        cmake
        autoconf
        automake
        gcc
        "g++"
        clang
        llvm
        rustc
        cargo

        # Database clients
        postgresql
        # sqlitebrowse  # not in nixpkgs
        redis
        # mongodb  # unfree (SSPL license)

        # MQ clients
        rabbitmq-c

        # DevGuard pattern: Monitoring and observability
        prometheus
        grafana
        loki
        tempo

        # Network tools
        nmap
        nikto
        masscan

        # Policy tools
        conftest
        # checkov  # depends on insecure ecdsa
        tfsec

        # secrets tools
        gitleaks
        trufflehog

        # Secrets management
        # vault  # unfree (BSL 1.1 license)
        sops
        age
      ];

    in
    pkgs.mkShell {
      name = "full";
      buildInputs = commonPackages ++ fullPackages;
      shellHook = ''
        echo "🚀 OpenDesk-Nix Full Shell"
        echo "==========================="
        echo ""
        echo "This shell includes ALL tools from:"
        echo "  🔒 Security Shell (grype, trivy, cosign, etc.)"
        echo "  ☸️  Kubernetes Shell (kubectl, helm, k9s, etc.)"
        echo "  🐳 Container tools (docker, skopeo, crane, etc.)"
        echo "  🔧 Development tools (go, nodejs, python, rust, etc.)"
        echo "  💾 Database clients (postgresql, redis, mongodb, etc.)"
        echo "  🔍 Security analysis (nmap, nikto, conftest, etc.)"
        echo "  🔐 Secrets management (vault, sops, age, etc.)"
        echo ""
        ${commonAliases}

        # All security aliases
        alias scan='security-scan'
        alias scan-all='security-scan all-images'
        alias sign='cosign sign'
        alias verify='cosign verify'
        alias attest='in-toto attest'

        # All Kubernetes aliases
        alias k='kubectl'
        alias kgp='kubectl get pods'
        alias kl='kubectl logs'
        alias kd='kubectl describe'
        alias kx='kubectl exec -it'
        alias h='helm'
        alias sk='skopeo'
        alias cr='crane'
        alias dv='dive'

        # DevGuard pattern: Environment setup
        export GOPATH="$HOME/go"
        export GOROOT="${pkgs.go}"
        export PATH="$GOPATH/bin:$PATH"
        export NODE_PATH="${pkgs.nodejs}/lib/node_modules"
        export PYTHONPATH="${pkgs.python3}/lib/python3.10/site-packages"
        export CARGO_HOME="$HOME/.cargo"
        export RUSTUP_HOME="$HOME/.rustup"
        export COSIGN_EXPERIMENTAL=1
        export IN_TOTO_EXPERIMENTAL=1

        # DevGuard pattern: Set registry tokens from environment
        ${builtins.concatStringsSep "\n" (
          map (kv: ''
            ${
              if builtins.getEnv kv.name == "" then
                ''export ${kv.name}="${registryEnv.${kv.name}}"''
              else
                "# ${kv.name} already set from environment"
            }
          '') (lib.mapAttrsToList (name: value: { inherit name value; }) registryEnv)
        )}

        echo "Full environment configured"
        echo ""
        echo "Available commands:"
        echo "  Type 'compgen -c | wc -l' to see total available commands"
        echo ""
      '';
    };

  # =============================================================================
  # SERVICE-SPECIFIC SHELLS - DevGuard Pattern
  # =============================================================================

  # Function to create a service-specific shell
  serviceShell =
    {
      serviceName,
      packages ? [ ],
      aliases ? "",
      env ? { },
      description ? "",
    }:
    pkgs.mkShell {
      name = serviceName;
      buildInputs = commonPackages ++ packages;
      shellHook = ''
        echo "🛠️  OpenDesk-Nix ${serviceName} Shell"
        echo "=================================="
        ${
          if description != "" then
            ''
              echo ""
              echo "${description}"
            ''
          else
            ""
        }
        echo ""
        ${commonAliases}
        ${
          if aliases != "" then
            ''
              echo ""
              echo "Service-specific aliases:"
              echo "${aliases}"
            ''
          else
            ""
        }

        # Set service-specific environment
        ${builtins.concatStringsSep "\n" (
          map (kv: ''export ${kv.name}="${kv.value}"'') (
            lib.mapAttrsToList (name: value: { inherit name value; }) env
          )
        )}

        # Set registry tokens
        ${builtins.concatStringsSep "\n" (
          map (kv: ''
            ${
              if builtins.getEnv kv.name == "" then
                ''export ${kv.name}="${registryEnv.${kv.name}}"''
              else
                "# ${kv.name} already set"
            }
          '') (lib.mapAttrsToList (name: value: { inherit name value; }) registryEnv)
        )}

        echo "${serviceName} environment configured"
        echo ""
      '';
    };

  # Predefined service shells
  predefinedServiceShells = {
    mariadb = serviceShell {
      serviceName = "mariadb";
      packages = with pkgs; [
        mariadb
        mariadb.client
      ];
      aliases = ''
        alias mysql='mysql'
        alias mysqldump='mysqldump'
        alias mysqladmin='mysqladmin'
      '';
      env = {
        MYSQL_HOST = "localhost";
        MYSQL_PORT = "3306";
        MYSQL_USER = "root";
      };
      description = "MariaDB/ MySQL database development and administration";
    };

    postgresql = serviceShell {
      serviceName = "postgresql";
      packages = with pkgs; [ postgresql ];
      aliases = ''
        alias psql='psql'
        alias pg_dump='pg_dump'
        alias pg_restore='pg_restore'
        alias pgadmin='pgAdmin4'
        alias createdb='createdb'
        alias dropdb='dropdb'
      '';
      env = {
        PGHOST = "localhost";
        PGPORT = "5432";
        PGUSER = "postgres";
      };
      description = "PostgreSQL database development and administration";
    };

    redis = serviceShell {
      serviceName = "redis";
      packages = with pkgs; [ redis ];
      aliases = ''
        alias redis-cli='redis-cli'
        alias redis-server='redis-server'
        alias redis-sentinel='redis-sentinel'
        alias redis-benchmark='redis-benchmark'
      '';
      env = {
        REDIS_HOST = "localhost";
        REDIS_PORT = "6379";
      };
      description = "Redis in-memory data store development and administration";
    };

    sogo5 = serviceShell {
      serviceName = "sogo5";
      packages = with pkgs; [ ];
      aliases = ''
        alias sogo='sogo'
        alias sogod='sogod'
      '';
      env = {
        SOGO_HOST = "localhost";
        SOGO_PORT = "20000";
      };
      description = "SOGo Groupware 5 development and administration";
    };

    sogo6 = serviceShell {
      serviceName = "sogo6";
      packages = with pkgs; [ ];
      aliases = ''
        alias sogo='sogo'
        alias sogod='sogod'
      '';
      env = {
        SOGO_HOST = "localhost";
        SOGO_PORT = "20000";
      };
      description = "SOGo Groupware 6 development and administration";
    };

    nginx = serviceShell {
      serviceName = "nginx";
      packages = with pkgs; [ nginx ];
      aliases = ''
        alias nginx='nginx'
        alias nginx-reload='nginx -s reload'
        alias nginx-restart='nginx -s stop && nginx'
        alias nginx-test='nginx -t'
        alias nginx-logs='tail -f /var/log/nginx/error.log'
      '';
      env = {
        NGINX_CONF = "/etc/nginx/nginx.conf";
        NGINX_PREFIX = "/usr/share/nginx";
      };
      description = "Nginx web server development and administration";
    };

    monitoring = serviceShell {
      serviceName = "monitoring";
      packages = with pkgs; [
        prometheus
        grafana
        loki
        tempo
        prometheus-node-exporter
        cadvisor
      ];
      aliases = ''
        alias prom='prometheus'
        alias graf='grafana-server'
        alias loki='loki'
        alias tempo='tempo'
      '';
      env = {
        PROMETHEUS_PORT = "9090";
        GRAFANA_PORT = "3000";
        LOKI_PORT = "3100";
        TEMPO_PORT = "3200";
      };
      description = "Monitoring and observability stack development";
    };
  };

  # =============================================================================
  # DEVGUARD PATTERNS: Shell selector function
  # =============================================================================

  # List all available shells
  listShells =
    builtins.attrNames {
      default = defaultShell;
      security = securityShell;
      k8s = k8sShell;
      full = fullShell;
    }
    ++ builtins.attrNames predefinedServiceShells;

  # Open a specific shell by name
  openShell =
    name:
    if name == "list" || name == null then
      pkgs.runCommand "list-shells" { } ''
        echo "Available development shells:"
        echo "=============================="
        ${builtins.concatStringsSep "\n" (
          map (shellName: ''
            echo "  - ${shellName}"
          '') listShells
        )}
        echo ""
        echo "Usage: nix develop -c <shell-name>"
      ''
    else if builtins.elem name listShells then
      if
        builtins.elem name [
          "default"
          "security"
          "k8s"
          "full"
        ]
      then
        {
          default = defaultShell;
          security = securityShell;
          k8s = k8sShell;
          full = fullShell;
        }
        .${name}
      else
        predefinedServiceShells.${name}
    else
      throw "Unknown shell: ${name}. Available: ${builtins.concatStringsSep ", " listShells}";

in
{
  # Main shells
  shells = {
    inherit
      defaultShell
      securityShell
      k8sShell
      fullShell
      ;
    inherit predefinedServiceShells;
  };

  # Shell utility functions
  inherit serviceShell listShells openShell;

  # Configuration
  config = {
    default = "default";
    security = true;
    k8s = true;
    full = true;
    registryTokens = registryEnv;
  };
}
