# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# disko Configuration for K3s Nodes
# Based on specs/technical/APPLIANCE-IMAGE-SPEC.md
#
# Declarative disk partitioning with:
# - GPT partition table
# - EFI System Partition
# - Btrfs root with subvolumes

{ config, lib, ... }:

let cfg = config.disko.configurations.k3sNode;
in {
  meta.maintainers = [ "opendesk-edu" ];

  ###### interface

  options = {
    disko.configurations.k3sNode = {
      enable = lib.mkEnableOption "K3s node disk configuration";

      device = lib.mkOption {
        type = lib.types.str;
        default = "/dev/sda";
        description = "Target disk device";
      };

      btrfsCompression = lib.mkOption {
        type = lib.types.enum [ "none" "zstd" "lzo" "zlib" ];
        default = "zstd";
        description = "Btrfs compression algorithm";
      };
    };
  };

  ###### implementation

  config = lib.mkIf cfg.enable {
    disko.devices = {
      disk = {
        main = {
          type = "disk";
          device = cfg.device;
          content = {
            type = "gpt";
            partitions = {
              boot = {
                size = "1M";
                type = "EF02";
                priority = 1;
              };

              esp = {
                size = "512M";
                type = "EF00";
                priority = 2;
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountPoint = "/boot/efi";
                };
              };

              root = {
                size = "100%";
                priority = 3;
                content = {
                  type = "btrfs";
                  extraArgs = [ "-f" ];
                  subvolumes = {
                    "/root" = {
                      mountPoint = "/";
                      mountOptions = [ "subvol=root" "defaults" ];
                    };

                    "/nix" = {
                      mountPoint = "/nix";
                      mountOptions = [
                        "subvol=nix"
                        "noatime"
                        "compress=${cfg.btrfsCompression}"
                      ];
                    };

                    "/var" = {
                      mountPoint = "/var";
                      mountOptions = [ "subvol=var" "defaults" ];
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
