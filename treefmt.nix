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
      # Nix formatting (required)
      nixfmt = {
        command = pkgs.lib.getExe pkgs.nixfmt;
        includes = [ "*.nix" ];
      };

      # Nix linting with auto-fix
      statix = {
        command = pkgs.lib.getExe pkgs.statix;
        options = [ "fix" ];
        no-positional-arg-support = true;
        includes = [ "*.nix" ];
      };

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
        includes = [ "*.sh" "*.bash" ];
      };

      # Shell linting (no auto-fix)
      shellcheck = {
        command = pkgs.lib.getExe pkgs.shellcheck;
        includes = [ "*.sh" "*.bash" ];
        excludes = [ ".envrc" ];
      };
    };
  };
}
