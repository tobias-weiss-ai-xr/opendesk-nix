# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# NixOS Appliance Image Module
# Based on specs/technical/APPLIANCE-IMAGE-SPEC.md
# and ~/git/nix-best-practices/examples/appliance-image.nix
#
# Builds an immutable, reproducible, A/B-updatable NixOS image using:
#   - nixpkgs' image/repart.nix (systemd-repart)
#   - profiles/image-based-appliance.nix (minimal, no nix, no switch)
#   - Squashfs read-only nix-store partition
#   - systemd-boot with UKI (Unified Kernel Image)
#   - A/B OTA slots via systemd-sysupdate (see opendesk.appliance.update)
#
# Usage in a NixOS config:
#   imports = [ inputs.opendesk-nix.nixosModules.appliance-image ];
#   opendesk.appliance.enable = true;
#   opendesk.appliance.update.enable = true;  # optional OTA

{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

let
  cfg = config.opendesk.appliance;
  efiArch =
    config.nixpkgs.hostPlatform.efiArch
      or (lib.removeSuffix "-linux" config.nixpkgs.hostPlatform.system);
in
{
  meta.maintainers = [ "opendesk-edu" ];

  # Always import the repart image builder (options-only when image disabled)
  imports = [ (modulesPath + "/image/repart.nix") ];

  options.opendesk.appliance = {
    enable = lib.mkEnableOption "Build NixOS appliance image (immutable, A/B updatable)";

    imageId = lib.mkOption {
      type = lib.types.str;
      default = "opendesk-k3s";
      description = "Identifier of the appliance image (sets /etc/os-release IMAGE_ID).";
    };

    version = lib.mkOption {
      type = lib.types.str;
      default = "1.0.0";
      description = "Version of the appliance image (sets /etc/os-release IMAGE_VERSION).";
    };

    espSize = lib.mkOption {
      type = lib.types.str;
      default = "200M";
      description = "Size of the EFI System Partition.";
    };

    nixStoreSize = lib.mkOption {
      type = lib.types.str;
      default = "2G";
      description = "Size of the (squashfs) nix-store partition. A/B updateable.";
    };

    rootSize = lib.mkOption {
      type = lib.types.str;
      default = "5G";
      description = "Size of the writable root partition.";
    };

    sysupdate = {
      enable = lib.mkEnableOption "A/B OTA updates via systemd-sysupdate";

      cacheUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://cache.internal/updates/";
        description = "Base URL of the update server serving image artifacts.";
      };

      checkInterval = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = "systemd-sysupdate check interval (OnCalendar).";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # === image-based-appliance profile (inlined, conditional) ===
    # The system is static: cannot be rebuilt, no Nix available.
    nix.enable = false;
    system.switch.enable = false;
    users.mutableUsers = false;
    boot.initrd.systemd.enable = lib.mkDefault true;
    networking.useNetworkd = lib.mkDefault true;

    system.image.id = cfg.imageId;
    system.image.version = cfg.version;

    image.repart = {
      name = cfg.imageId;
      split = true; # Separate nix-store image for A/B updates

      partitions = {
        # EFI System Partition (boot)
        esp = {
          contents = {
            "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI".source =
              "${pkgs.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";
            "/EFI/Linux/${config.system.boot.loader.ukiFile}".source =
              "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
          };
          repartConfig = {
            Type = "esp";
            Format = "vfat";
            Label = "boot";
            SizeMinBytes = cfg.espSize;
            SplitName = "-";
          };
        };

        # Nix store (read-only squashfs, A/B updateable)
        nix-store = {
          storePaths = [ config.system.build.toplevel ];
          stripNixStorePrefix = true;
          repartConfig = {
            Type = "linux-generic";
            Format = "squashfs";
            ReadOnly = "yes";
            Label = "nix-store_${cfg.version}";
            SizeMinBytes = cfg.nixStoreSize;
            SizeMaxBytes = cfg.nixStoreSize;
            SplitName = "nix-store";
          };
        };

        # Root (writable, grows at runtime via systemd-repart)
        root.repartConfig = {
          Type = "root";
          Format = "ext4";
          Label = "root";
          SizeMinBytes = cfg.rootSize;
          SizeMaxBytes = cfg.rootSize;
          SplitName = "-";
        };
      };
    };

    # === A/B OTA updates via systemd-sysupdate ===
    systemd.sysupdate = lib.mkIf cfg.sysupdate.enable {
      enable = true;

      timerConfig = {
        OnCalendar = cfg.sysupdate.checkInterval;
        Persistent = true;
        AccuracySec = "1h";
      };

      transfers = {
        # Nix store image (A/B slots)
        "10-nix-store" = {
          Source = {
            Path = cfg.sysupdate.cacheUrl;
            Type = "url-file";
            MatchPattern = [ "${cfg.imageId}_@v.nix-store.raw" ];
          };
          Target = {
            InstancesMax = 2; # A/B slots
            Path = "auto";
            MatchPattern = "nix-store_@v";
            Type = "partition";
            MatchPartitionType = "linux-generic";
            ReadOnly = "yes";
          };
        };

        # UKI boot image (A/B slots)
        "20-boot-image" = {
          Source = {
            Path = cfg.sysupdate.cacheUrl;
            Type = "url-file";
            MatchPattern = [ "${cfg.imageId}_@v.efi.raw" ];
          };
          Target = {
            InstancesMax = 2;
            Path = "auto";
            MatchPattern = "esp-@v";
            Type = "partition";
            MatchPartitionType = "esp";
            ReadOnly = "yes";
          };
        };
      };
    };

    # systemd-repart grows the root partition at boot (in initrd)
    boot.initrd.systemd.repart = lib.mkIf cfg.sysupdate.enable {
      enable = true;
    };
    systemd.repart = lib.mkIf cfg.sysupdate.enable {
      enable = true;
      partitions = {
        "10-root" = {
          Type = "root";
          Format = "ext4";
          Label = "root";
          SizeMinBytes = cfg.rootSize;
          GrowFileSystem = true;
        };
      };
    };
  };
}
