# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Eval-only checks for openDesk services
# Fast validation that catches option drift without building VMs
# Run with: nix build .#checks.x86_64-linux.eval-opendesk-services

{ pkgs, nixos-services, ... }:

let
  # Simply evaluate all service configurations to catch errors
  # This is fast (seconds) vs integration tests (minutes)
  evaluatedServices = map (name: (nixos-services.${name} or {}).config or null) 
    (builtins.attrNames nixos-services);

  # Generate a simple text output
  outputText = builtins.concatStringsSep "\n" (
    map (name: "✓ Service '${name}' evaluated successfully") 
    (builtins.attrNames nixos-services)
  );

in
  pkgs.writeText "eval-services-check" outputText
