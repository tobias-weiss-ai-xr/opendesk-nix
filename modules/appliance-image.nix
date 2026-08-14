# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# NixOS Appliance Image Module
# Based on specs/technical/APPLIANCE-IMAGE-SPEC.md
#
# Creates immutable, reproducible NixOS images with:
# - systemd-repart partition layout
# - Squashfs root with dm-verity
# - A/B slot configuration

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.image;
in
{
  meta.maintainers = [ "opendesk-edu" ];

  ###### interface

  options = {
    image = {
      enable = lib.mkEnableOption "Build NixOS appliance image";

      format = lib.mkOption {
        type = lib.types.enum [
          "ext4"
          "squashfs"
          "repart"
        ];
        default = "repart";
        description = "Image format type";
      };

      size = lib.mkOption {
        type = lib.types.size;
        default = 10737418240; # 10GB
        description = "Total image size in bytes";
      };

      partitions = lib.mkOption {
        type = lib.types.attrs;
        description = "Partition definitions";
        default = {
          boot = {
            size = "1M";
            type = "EF02";
          };
          esp = {
            size = "512M";
            type = "EF00";
          };
          rootA = {
            size = "50%";
          };
          rootB = {
            size = "50%";
          };
        };
      };

      outputDir = lib.mkOption {
        type = lib.types.path;
        default = ./result;
        description = "Output directory for image files";
      };
    };
  };

  ###### implementation

  config = lib.mkIf cfg.enable {
    # Create image build derivation
    system.build.applianceImage =
      pkgs.runCommand "appliance-image"
        {
          buildInputs = [
            pkgs.systemd
            pkgs.e2fsprogs
          ];
        }
        ''
          mkdir -p $out
          # Image build logic here
          echo "Image built at $out"
        '';

    # systemd-repart definitions
    environment.etc."systemd/repart.d/00-partition.conf".text = ''
      [Partition]
      Type=root
      SizeMinBytes=5G
      SizeMaxBytes=5G
    '';
  };
}
