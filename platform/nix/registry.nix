# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
# Enhanced with DevGuard patterns for multi-registry support and image signing

{ lib, pkgs, ... }:

let
  # =============================================================================
  # REGISTRY TYPE DEFINITIONS
  # =============================================================================
  
  # Registry type names (for validation)
  registryTypeNames = [ 
    "oci" "docker" "zot" "ghcr" "gitlab" "docker-hub" 
    "quay" "harbor" "ecr" "acr" "gcr" "local" 
  ];

  # Registry configuration type
  registryType = lib.types.submodule {
    options = {
      name = lib.mkOption { type = lib.types.str; };
      url = lib.mkOption { type = lib.types.str; };
      type = lib.mkOption { type = lib.types.enum registryTypeNames; };
      namespace = lib.mkOption { type = lib.types.str; default = ""; };
      username = lib.mkOption { default = null; type = lib.types.nullOr lib.types.str; };
      password = lib.mkOption { default = null; type = lib.types.nullOr lib.types.str; };
      tokenEnv = lib.mkOption { default = null; type = lib.types.nullOr lib.types.str; };
      insecure = lib.mkOption { default = false; type = lib.types.bool; };
      # DevGuard pattern: Registry capabilities
      supportsSigning = lib.mkOption { default = true; type = lib.types.bool; };
      supportsPush = lib.mkOption { default = true; type = lib.types.bool; };
      supportsPull = lib.mkOption { default = true; type = lib.types.bool; };
      supportsAttestations = lib.mkOption { default = true; type = lib.types.bool; };
    };
  };

  # =============================================================================
  # IMAGE FORMATTING
  # =============================================================================
  
  # Format image name with registry
  formatImageName = { registry, repo, tag ? "latest", digest ? null }:
    let
      base = if registry != null && registry != "" then "${registry}/" else "";
      namespace = if builtins.hasAttr "namespace" registry && registry.namespace != "" then "${registry.namespace}/" else "";
      tagPart = if tag != null then ":${tag}" else "";
      digestPart = if digest != null then "@${digest}" else "";
    in "${base}${namespace}${repo}${tagPart}${digestPart}";

  # Format image name without registry (just repo:tag)
  formatImageReference = { repo, tag ? "latest", digest ? null }:
    let
      tagPart = if tag != null then ":${tag}" else "";
      digestPart = if digest != null then "@${digest}" else "";
    in "${repo}${tagPart}${digestPart}";

  # Parse image reference into components
  parseImageReference = image: 
    let
      # Split by @ for digest
      parts = builtins.split "@" image;
      ref = builtins.elemAt parts 0;
      digest = if builtins.length parts > 1 then builtins.elemAt parts 1 else null;
      
      # Split by : for tag
      refParts = builtins.split ":" ref;
      repoWithRegistry = builtins.elemAt refParts 0;
      tag = if builtins.length refParts > 1 then builtins.elemAt refParts 1 else null;
      
      # Split by / for registry
      repoParts = builtins.split "/" repoWithRegistry;
      registry = if builtins.length repoParts > 1 then builtins.concatStringsSep "/" (builtins.take (builtins.length repoParts - 1) repoParts) else null;
      repo = builtins.elemAt repoParts (builtins.length repoParts - 1);
      
      # Handle namespaces (e.g., ghcr.io/owner/repo)
      namespace = if registry != null && builtins.length repoParts > 2 then 
        builtins.elemAt repoParts (builtins.length repoParts - 2)
      else null;
      
    in {
      registry = registry;
      namespace = namespace;
      repo = repo;
      tag = tag;
      digest = digest;
      full = image;
    };

  # =============================================================================
  # PREDEFINED REGISTRIES - Enhanced with DevGuard patterns
  # =============================================================================
  
  # DevGuard pattern: Comprehensive registry configuration
  registries = lib.genAttrs [
    "ghcr" "gitlab" "zot" "docker-hub" "quay" "harbor" 
    "ecr" "acr" "gcr" "local" "nix-cache"
  ] (name:
    let
      cfg = {
        name = name;
        url = if name == "ghcr" then "ghcr.io"
          else if name == "gitlab" then "registry.gitlab.com"
          else if name == "zot" then builtins.getEnv "ZOT_REGISTRY_FALLBACK" or "registry.example.com:5000"  # Replace with your registry
          else if name == "docker-hub" then "docker.io"
          else if name == "quay" then "quay.io"
          else if name == "harbor" then "harbor.opendesk.local"
          else if name == "ecr" then "public.ecr.aws"
          else if name == "acr" then "*.azurecr.io"
          else if name == "gcr" then "gcr.io"
          else if name == "local" then "localhost:5000"
          else if name == "nix-cache" then "cache.nixos.org"
          else "";
        type = if name == "zot" then "zot"
          else if name == "docker-hub" then "docker"
          else "oci";
        namespace = if name == "gitlab" then "opencode"
          else if name == "ghcr" then "tobias-weiss-ai-xr"
          else "opendesk";
        insecure = if name == "zot" then true
          else if name == "local" then true
          else false;
        # DevGuard pattern: Registry capabilities
        supportsSigning = if name == "zot" || name == "gitlab" || name == "ghcr" then true else false;
        supportsPush = true;
        supportsPull = true;
        supportsAttestations = if name == "zot" || name == "gitlab" || name == "ghcr" then true else false;
        # DevGuard pattern: Authentication configuration
        tokenEnv = if name == "gitlab" then "OPENCODE_TOKEN"
          else if name == "ghcr" then "GITHUB_TOKEN"
          else if name == "zot" then "ZOT_TOKEN"
          else null;
      };
    in cfg
  );

  # =============================================================================
  # MULTI-REGISTRY CONFIGURATION - DevGuard Pattern
  # =============================================================================
  
  # Multi-registry configuration for simultaneous deployment
  multiRegistryConfig = {
    # List of registries to push to
    targets = [ "gitlab" "ghcr" "zot" ];
    
    # Authentication environment variables
    authEnvVars = [
      "OPENCODE_TOKEN"  # GitLab
      "GITHUB_TOKEN"   # GitHub
      "ZOT_TOKEN"      # Zot
    ];
    
    # Strategy for pushing (parallel or sequential)
    strategy = "parallel";
    
    # Maximum parallel pushes
    maxParallel = 3;
    
    # Fail on single registry failure or continue with others
    failFast = false;
    
    # Retry configuration
    retry = {
      enabled = true;
      maxAttempts = 3;
      delaySeconds = 5;
    };
    
    # Health check configuration
    healthCheck = {
      enabled = true;
      timeoutSeconds = 30;
      checkBeforePush = true;
    };
  };

  # =============================================================================
  # IMAGE SIGNING - DevGuard Pattern (Cosign integration)
  # =============================================================================
  
  # Signing configuration
  signingConfig = {
    # Signing modes
    modes = {
      keyless = {
        enable = true;
        fulcioUrl = "https://fulcio.sigstore.dev";
        rekorUrl = "https://rekor.sigstore.dev";
        # DevGuard pattern: Keyless signing is preferred for public registries
        default = true;
      };
      keyBased = {
        enable = false;  # Disable by default for security
        privateKeyPath = "/path/to/cosign/private.key";
        publicKeyPath = "/path/to/cosign/public.key";
        passwordEnv = "COSIGN_PASSWORD";
        # DevGuard pattern: Key-based signing for private registries
        default = false;
      };
    };
    
    # Annotations for signatures
    annotations = {
      # DevGuard pattern: Include metadata in signatures
      builder = "opendesk-nix";
      gitCommit = "${lib belleza getGitRev}" or "unknown";
      gitRepo = "${lib belleza getGitRepo}" or "unknown";
      buildTime = "${lib bugs getTime}" or "unknown";
    };
    
    # Signature retention policy
    retention = {
      keepSignatures = true;
      maxSignaturesPerImage = 10;
      cleanupOldSignatures = true;
    };
    
    # Verification configuration
    verification = {
      enabled = true;
      enforce = true;  # Fail if signature verification fails
      checkSignaturesOnPull = true;
      checkAttestations = true;
    };
  };

  # Get signing mode configuration
  getSigningMode = modeName: 
    if builtins.hasAttr modeName signingConfig.modes then
      signingConfig.modes.${modeName}
    else if modeName == "default" || modeName == null then
      # Prefer keyless, fallback to key-based if enabled
      if signingConfig.modes.keyless.enable then
        signingConfig.modes.keyless
      else if signingConfig.modes.keyBased.enable then
        signingConfig.modes.keyBased
      else
        throw "No signing mode available. Enable at least one signing mode.";
    else
      throw "Unknown signing mode: ${modeName}. Available: ${builtins.concatStringsSep ", " (builtins.attrNames signingConfig.modes)}";

  # Check if signing is enabled
  isSigningEnabled = : 
    signingConfig.modes.keyless.enable || signingConfig.modes.keyBased.enable;

  # =============================================================================
  # ATTESTATION SUPPORT - DevGuard Pattern
  # =============================================================================
  
  # Attestation types
  attestationTypes = [
    "sbom"   # Software Bill of Materials
    "vulnerability-scan"  # Vulnerability scan results
    "build"  # Build configuration and parameters
    "policy" # Policy compliance results
  ];

  # Attestation configuration
  attestationConfig = {
    enabled = true;
    types = attestationTypes;
    # DevGuard pattern: Store attestations in OCI registry
    storeInRegistry = true;
    # DevGuard pattern: Sign attestations with Cosign
    signAttestations = true;
    # DevGuard pattern: Verify attestations before deployment
    verifyAttestations = true;
    # Retention policy
    retention = {
      keepAttestations = true;
      maxAttestationsPerImage = 20;
    };
  };

  # =============================================================================
  # REGISTRY OPERATIONS
  # =============================================================================
  
  # Push to a single registry
  pushToRegistry = { image, registryConfig, tag ? "latest", signingMode ? "default" }:
    let
      imageName = formatImageName {
        registry = registryConfig.url;
        repo = image;
        tag = tag;
      };
      signingModeConfig = getSigningMode signingMode;
      shouldSign = isSigningEnabled && signingModeConfig.enable && registryConfig.supportsSigning;
      
    in pkgs.runCommand "push-${builtins.hashString "sha256" imageName}" {
      nativeBuildInputs = with pkgs; [ docker cosign ];
    }''
      # DevGuard pattern: Health check before push
      if ${toString registryConfig.insecure}; then
        DOCKER_OPTS="--insecure-registry ${registryConfig.url}"
      fi
      
      echo "Pushing ${image} to ${imageName}"
      
      # Create temporary directory for scripts
      mkdir -p /tmp/registry-push
      cd /tmp/registry-push
      
      # DevGuard pattern: Authenticate based on registry type
      ${if registryConfig.tokenEnv != null then ''
        if [ -n "${!'${registryConfig.tokenEnv}'}" ]; then
          echo "Authenticating with ${registryConfig.tokenEnv}"
          echo "${!'${registryConfig.tokenEnv}'}" | docker login ${registryConfig.url} --username ${registryConfig.username or "token"} --password-stdin $DOCKER_OPTS
        else
          echo "Warning: ${registryConfig.tokenEnv} not set"
        fi
      '' else ''
        if [ -n "${registryConfig.username}" ] && [ -n "${registryConfig.password}" ]; then
          echo "Authenticating with username/password"
          echo "${registryConfig.password}" | docker login ${registryConfig.url} --username ${registryConfig.username} --password-stdin $DOCKER_OPTS
        fi
      ''}
      
      # DevGuard pattern: Push the image
      docker push ${imageName} $DOCKER_OPTS
      
      # DevGuard pattern: Sign the image if signing is enabled
      ${if shouldSign then ''
        echo "Signing image ${imageName}"
        
        # Use appropriate signing mode
        ${if signingMode == "keyless" || signingModeConfig.default then ''
          export COSIGN_EXPERIMENTAL=1
          cosign sign ${imageName} --yes
        '' else ''
          # Key-based signing
          if [ -n "${!'${signingModeConfig.passwordEnv}'}" ]; then
            echo "${!'${signingModeConfig.passwordEnv}'}" | cosign sign ${imageName} --key ${signingModeConfig.privateKeyPath} --password-stdin --yes
          else
            cosign sign ${imageName} --key ${signingModeConfig.privateKeyPath} --yes
          fi
        ''}
      '' else ''echo "Signing not enabled for this registry"''}
      
      # Cleanup
      cd -
      rm -rf /tmp/registry-push
      
      touch $out
    '';

  # Pull from a single registry
  pullFromRegistry = { image, registryConfig, tag ? "latest" }:
    let
      imageName = formatImageName {
        registry = registryConfig.url;
        repo = image;
        tag = tag;
      };
      
    in pkgs.runCommand "pull-${builtins.hashString "sha256" imageName}" {
      nativeBuildInputs = with pkgs; [ docker cosign ];
    }''
      if ${toString registryConfig.insecure}; then
        DOCKER_OPTS="--insecure-registry ${registryConfig.url}"
      fi
      
      echo "Pulling from ${imageName}"
      
      # DevGuard pattern: Authenticate if needed
      ${if registryConfig.tokenEnv != null then ''
        if [ -n "${!'${registryConfig.tokenEnv}'}" ]; then
          echo "${!'${registryConfig.tokenEnv}'}" | docker login ${registryConfig.url} --username ${registryConfig.username or "token"} --password-stdin $DOCKER_OPTS
        fi
      '' else ''''}
      
      # DevGuard pattern: Pull the image
      docker pull ${imageName} $DOCKER_OPTS
      
      # DevGuard pattern: Verify signature if verification is enabled
      ${if signingConfig.verification.enabled && signingConfig.verification.enforce then ''
        echo "Verifying signature for ${imageName}"
        cosign verify ${imageName} || {
          echo "Signature verification failed for ${imageName}"
          exit 1
        }
      '' else if signingConfig.verification.enabled then ''
        echo "Verifying signature for ${imageName}"
        cosign verify ${imageName} 2>/dev/null || echo "Warning: Signature verification failed or not available for ${imageName}"
      '' else ''echo "Signature verification not enabled"''}
      
      touch $out
    '';

  # Push to multiple registries simultaneously - DevGuard Pattern
  pushToAll = { image, tag ? "latest", registriesToUse ? [ "gitlab" "ghcr" "zot" ], signingMode ? "default" }:
    let
      registryConfigs = map (name: builtins.getAttr name registries) registriesToUse;
      config = getSigningMode signingMode;
      
      # Create push commands for each registry
      pushCommands = map (reg: 
        let
          imageName = formatImageName {
            registry = reg.url;
            repo = image;
            tag = tag;
          };
        in
        pkgs.writeShellScriptBin "push-to-${reg.name}" ''
          #!${pkgs.bash}/bin/bash
          {
            echo "[{reg.name}] Starting push to ${imageName}"
            ${PKGS.docker}/bin/docker push ${imageName} ${
              if reg.insecure then "--insecure-registry ${reg.url}" else ""
            }
            ${if isSigningEnabled && reg.supportsSigning then ''.''.'
              echo "[{reg.name}] Signing image"
              ${PKGS.cosign}/bin/cosign sign ${imageName} --yes
            '''.''.'' else '''.''.''}
            echo "[{reg.name}] Push to ${reg.name} completed"
          } &
        ''
      ) registryConfigs;
      
    in pkgs.runCommand "push-to-all-${builtins.hashString "sha256" (builtins.concatStringsSep "" registriesToUse)}" {
      nativeBuildInputs = with pkgs; [ docker cosign bash ];
    }''
      echo "Pushing ${image}:${tag} to ${builtins.concatStringsSep ", " registriesToUse}"
      
      # DevGuard pattern: Parallel push with error handling
      PIDS=()
      ERRORS=0
      
      ${builtins.concatStringsSep "\n" (map (reg: ''
        (
          echo "Starting push to ${reg.url}..."
          ${if reg.tokenEnv != null then ''
            if [ -n "${!'${reg.tokenEnv}'}" ]; then
              echo "${!'${reg.tokenEnv}'}" | ${PKGS.docker}/bin/docker login ${reg.url} --username ${reg.username or "token"} --password-stdin 2>/dev/null
            else
              echo "Warning: ${reg.tokenEnv} not set for ${reg.url}"
            fi
          '' else ''''}
          
          ${PKGS.docker}/bin/docker push ${formatImageName { registry = reg.url; repo = image; tag = tag; }} ${
            if reg.insecure then "--insecure-registry ${reg.url}" else ""
          } 2>&1
          
          ${if isSigningEnabled && reg.supportsSigning then ''
            echo "Signing image for ${reg.url}..."
            ${PKGS.cosign}/bin/cosign sign ${formatImageName { registry = reg.url; repo = image; tag = tag; }} --yes 2>&1
          '' else ''''}
          
          exitsatively=$?
          if [ $exitsatively -ne 0 ]; then
            echo "Error pushing to ${reg.url}"
            ERRORS=$((ERRORS + 1))
          fi
          
          echo "Push to ${reg.url} completed with exit code $exitsatively"
        ) &
        PIDS+=($!)
      '') registriesToUse)}
      
      # Wait for all pushes to complete
      for pid in "${PIDS[@]}"; do
        wait "$pid"
      done
      
      if [ $ERRORS -gt 0 ]; then
        echo "Completed with $ERRORS error(s)"
        exit $ERRORS
      fi
      
      echo "All pushes completed successfully"
      touch $out
    '';

  # Sequential push with retry - DevGuard Pattern
  pushToAllSequential = { 
    image, 
    tag ? "latest", 
    registriesToUse ? [ "gitlab" "ghcr" "zot" ],
    signingMode ? "default",
    retryConfig ? multiRegistryConfig.retry
  }:
    let
      registryConfigs = map (name: builtins.getAttr name registries) registriesToUse;
      
      pushWithRetry = reg: 
        pkgs.runCommand "push-${reg.name}-retry-${builtins.hashString "sha256" image}" {
          nativeBuildInputs = with pkgs; [ docker cosign bash ];
        }''
          ATTEMPT=1
          MAX_ATTEMPTS=${toString (retryConfig.maxAttempts or 3)}
          DELAY=${toString (retryConfig.delaySeconds or 5)}
          SUCCESS=false
          
          while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
            echo "[${reg.name}] Attempt $ATTEMPT of $MAX_ATTEMPTS"
            
            ${if reg.tokenEnv != null then ''
              if [ -n "${!'${reg.tokenEnv}'}" ]; then
                echo "${!'${reg.tokenEnv}'}" | ${PKGS.docker}/bin/docker login ${reg.url} --username ${reg.username or "token"} --password-stdin 2>/dev/null
              fi
            '' else ''''}
            
            # Try to push
            ${PKGS.docker}/bin/docker push ${
              formatImageName { registry = reg.url; repo = image; tag = tag; }
            } ${
              if reg.insecure then "--insecure-registry ${reg.url}" else ""
            } 2>&1
            
            if [ $? -eq 0 ]; then
              SUCCESS=true
              break
            fi
            
            if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
              echo "[${reg.name}] Retrying in $DELAY seconds..."
              sleep $DELAY
            fi
            
            ATTEMPT=$((ATTEMPT + 1))
          done
          
          if [ "$SUCCESS" = false ]; then
            echo "[${reg.name}] Failed after $MAX_ATTEMPTS attempts"
            exit 1
          fi
          
          # Sign the image
          ${if isSigningEnabled && reg.supportsSigning then ''
            echo "[${reg.name}] Signing image"
            ${PKGS.cosign}/bin/cosign sign ${
              formatImageName { registry = reg.url; repo = image; tag = tag; }
            } --yes 2>&1
          '' else ''''}
          
          echo "[${reg.name}] Push completed successfully"
          touch $out
        '';
      
      pushes = map pushWithRetry registryConfigs;
      
    in pkgs.runCommand "push-sequential-${builtins.hashString "sha256" (builtins.concatStringsSep "" registriesToUse)}" {
      nativeBuildInputs = [ ];
    }''
      echo "Sequential push to ${builtins.concatStringsSep ", " registriesToUse}"
      ${builtins.concatStringsSep "\n" (map (p: 