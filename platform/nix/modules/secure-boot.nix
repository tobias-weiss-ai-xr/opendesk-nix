# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Secure Boot Module with lanzaboote
# Based on ~/git/nix-best-practices patterns
#
# Features:
# - UEFI Secure Boot with lanzaboote
# - Signed kernel and initrd
# - TPM 2.0 attestation support
# - Measured boot integration

{ config, lib, pkgs, ... }:

let
  cfg = config.security.secureBoot;
in {
  meta.maintainers = [ "opendesk-edu" ];

  ###### interface

  options = {
    security.secureBoot = {
      enable = lib.mkEnableOption "UEFI Secure Boot with lanzaboote";

      mode = lib.mkOption {
        type = lib.types.enum [ "enroll" "manual" ];
        default = "enroll";
        description = "Key enrollment mode";
      };

      keySize = lib.mkOption {
        type = lib.types.enum [ 2048 3072 4096 ];
        default = 3072;
        description = "RSA key size in bits";
      };

      tpmAttestation = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable TPM 2.0 attestation";
      };

      measuredBoot = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable measured boot (PCR 7)";
      };

      allowedSigners = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "List of allowed signers (email/SPKI)";
      };

      keyDatabase = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to key database for runtime verification";
      };
    };
  };

  ###### implementation

  config = lib.mkIf cfg.enable {
    # Import lanzaboote module
    imports = [ 
      (if pkgs ? lanzaboote then 
        "${toString pkgs.lanzaboote}/nix/modules/lanzaboote"
      else 
        throw "lanzaboote not available in this nixpkgs version"
      )
    ];

    # Lanzaboote configuration
    boot.lanzaboote = {
      enable = true;
      pkiBundle = "/etc/lanzaboote/pki";
    };

    # Generate Secure Boot keys
    environment.etc."lanzaboote/generate-keys.sh".source = pkgs.writeScript "generate-keys" ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      PKI_DIR="/etc/lanzaboote/pki"
      KEY_SIZE=${toString cfg.keySize}
      
      mkdir -p "$PKI_DIR"
      
      # Generate CA key
      openssl req -x509 -newkey rsa:$KEY_SIZE -keyout "$PKI_DIR/ca.key" \
        -out "$PKI_DIR/ca.crt" -days 3650 -nodes \
        -subj "/CN=openDesk Edu Secure Boot CA"
      
      # Generate signing key
      openssl req -x509 -newkey rsa:$KEY_SIZE -keyout "$PKI_DIR/db.key" \
        -out "$PKI_DIR/db.crt" -days 3650 -nodes \
        -subj "/CN=openDesk Edu Signing Key"
      
      # Generate platform key
      openssl req -x509 -newkey rsa:$KEY_SIZE -keyout "$PKI_DIR/plat.key" \
        -out "$PKI_DIR/plat.crt" -days 3650 -nodes \
        -subj "/CN=openDesk Edu Platform Key"
      
      chmod 600 "$PKI_DIR"/*.key
      echo "Keys generated in $PKI_DIR"
    '';

    # TPM 2.0 configuration
    services.tpm2 = lib.mkIf cfg.tpmAttestation {
      enable = true;
      tcti = "device:/dev/tpmrm0";
    };

    # Measured boot configuration
    boot.initrd.systemd = lib.mkIf cfg.measuredBoot {
      enable = true;
      
      # Add TPM measurements
      units."tpm2-measure.service" = {
        description = "Measure boot components to TPM PCR";
        defaultDependencies = false;
        before = [ "initrd.target" ];
        serviceConfig.Type = "oneshot";
        script = ''
          # Measure kernel command line
          echo "$INITRD_KERNEL_CMDLINE" | ${pkgs.tpm2-tools}/bin/tpm2_pcrextend 7:sha256
          
          # Measure initrd hash
          ${pkgs.coreutils}/bin/sha256sum /run/initramfs/stage2/initrd | \
            ${pkgs.tpm2-tools}/bin/tpm2_pcrextend 7:sha256
        '';
      };
    };

    # Boot loader configuration
    boot.loader = {
      systemd-boot = {
        enable = true;
        secureBoot = true;
        tpmStateVerification = cfg.tpmAttestation;
      };
      
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot/efi";
      };
    };

    # Kernel parameters for secure boot
    boot.kernelParams = [
      "tpm.log=verbose"
      "secureboot=enforce"
    ];

    # Audit logging for security events
    audit = {
      enable = true;
      rules = [
        "-w /boot -p wa -k boot_changes"
        "-w /etc -p wa -k etc_changes"
        "-w /nix/store -p r -k store_access"
      ];
    };

    # Firewall rules for attestation
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.tpmAttestation [
      8443  # Attestation service
    ];
  };
}
