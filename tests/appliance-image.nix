# SPDX-License-Identifier: Apache-2.0
# Eval-level check for the appliance image module (modules/appliance-image.nix)
#
# Verifies the repart partition layout is correctly wired up WITHOUT
# building the full multi-GB image. To build the actual image:
#   nix build .#nixosConfigurations.<name>.config.system.build.image
# or use the module in a nixosSystem and build system.build.image.

{
  pkgs,
  lib,
  nixpkgs,
  ...
}:

let
  system = pkgs.system;

  eval = nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      ../modules/appliance-image.nix
      {
        nixpkgs.hostPlatform = system;
        opendesk.appliance.enable = true;
        opendesk.appliance.sysupdate.enable = true;
        boot.loader.systemd-boot.enable = true;
        fileSystems."/" = {
          device = "/dev/disk/by-label/root";
          fsType = "ext4";
        };
        users.allowNoPasswordLogin = true;
        system.stateVersion = "24.11";
      }
    ];
  };

  p = eval.config.image.repart.partitions;

  espType = p.esp.repartConfig.Type;
  storeFormat = p."nix-store".repartConfig.Format;
  storeReadOnly = p."nix-store".repartConfig.ReadOnly;
  rootType = p.root.repartConfig.Type;
  split = eval.config.image.repart.split;
  imageId = eval.config.system.image.id;
  sysupdateEnabled = eval.config.systemd.sysupdate.enable;

  checks = [
    "esp partition type is esp (got: ${espType})"
    "nix-store partition format is squashfs (got: ${storeFormat})"
    "nix-store partition is read-only (got: ${toString storeReadOnly})"
    "root partition type is root (got: ${rootType})"
    "image split enabled for A/B updates (got: ${toString split})"
    "image id set (got: ${imageId})"
    "sysupdate enabled (got: ${toString sysupdateEnabled})"
  ];

  allPass =
    espType == "esp"
    && storeFormat == "squashfs"
    && storeReadOnly == "yes"
    && lib.hasPrefix "root" rootType
    && split
    && imageId != ""
    && sysupdateEnabled;
in
pkgs.runCommand "appliance-image-check" { } ''
  ${lib.concatMapStringsSep "\n" (c: "echo '✓ ${c}'") checks}
  ${if allPass then "echo 'All appliance image checks passed.'" else "echo 'FAILED' && exit 1"}
  touch $out
''
