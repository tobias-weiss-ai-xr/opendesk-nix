# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# treefmt configuration for opendesk-nix
# Run with: nix fmt
# Check with: nix flake check
#
# Based on best practices from ~/git/nix-best-practices/examples/treefmt.nix

{ pkgs, ... }:

{
  settings = {
    tree-root-file = "flake.nix";
    on-unmatched = "info";

    formatter = {
      # Nix formatting (RFC 166 style - best practice)
      nixfmt = {
        command = pkgs.lib.getExe pkgs.nixfmt-rfc-style;
        includes = [ "*.nix" ];
        # Legacy/example files with syntax errors that cannot be formatted yet
        excludes = [
          "overlays/container-gov-de.nix"
          "templates/**"
          "dev-agent/flake.nix"
          "examples/advanced/flake.nix"
          "platform/kubernetes/**"
          "platform/nix/integrated-devguard.nix"
          "platform/nix/docs.nix"
          "platform/nix/ci-cd/**"
          "platform/nix/compliance/**"
          "sogo/**"
        ];
      };

      # Nix linting (best practice: run separately in CI, not as a treefmt formatter)
      # statix = {
      #   command = pkgs.lib.getExe pkgs.statix;
      #   options = [ "fix" ];
      #   no-positional-arg-support = true;
      #   includes = [ "*.nix" ];
      # };

      # Dead code removal
      deadnix = {
        command = pkgs.lib.getExe pkgs.deadnix;
        options = [ "--edit" ];
        includes = [ "*.nix" ];
      };

      # YAML/JSON formatting (commented out - prettier not available in nixpkgs)
      # prettier = {
      #   command = pkgs.lib.getExe pkgs.prettier;
      #   options = [ "--write" ];
      #   includes = [ "*.yaml" "*.yml" "*.json" "*.md" ];
      # };

      # Shell formatting
      shfmt = {
        command = pkgs.lib.getExe pkgs.shfmt;
        includes = [
          "*.sh"
          "*.bash"
        ];
        # Legacy scripts with syntax errors that cannot be formatted yet
        excludes = [
          "docker/**"
          "scripts/build/security-scan.sh"
        ];
      };
    };
  };
}
