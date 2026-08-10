{ lib, pkgs, ... }:

let
  # Import DevGuard libraries
  security-scanning = import ./security-scanning.nix { inherit lib pkgs; };
  registry-nix = import ./registry.nix { inherit lib pkgs; };
  compliance = import ./compliance.nix { inherit lib pkgs; };

in

{
  # Operator runtime dependencies
  runtimeDeps = with pkgs; [
    # Kubernetes tools
    kubectl
    helm
    kustomize
    
    # Container runtime
    docker-cli
    containerd
    
    # Security tools
    cosign
    grype
    trivy
    syft
    
    # Supply chain tools
    in-toto
    
    # Other utilities
    curl
    jq
    yq-go
    git
  ];

  # Operator build dependencies  
  buildDeps = with pkgs; [
    # Go for operator development
    go
    go-tools
    
    # Nix for builds
    nix
    cairn  # For building Nix-based images
    
    # Container build tools
    docker
    buildah
    img
    
    # Build utilities
    gnumake
    gcc
  ];

  # Operator test dependencies
  testDeps = with pkgs; [
    golangci-lint
    gotest
    kubeval
    conftest
  ];

}
