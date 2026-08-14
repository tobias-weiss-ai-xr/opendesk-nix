# SPDX-License-Identifier: Apache-2.0
# Post-build hook configuration module

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.nix.postBuildHook;
in
{
  options = {
    nix.postBuildHook = {
      enable = lib.mkEnableOption "Automatic upload to binary cache";

      atticUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://attic.internal:8080";
      };

      atticCache = lib.mkOption {
        type = lib.types.str;
        default = "main";
      };

      atticKey = lib.mkOption {
        type = lib.types.path;
        default = "/etc/attic/signing.key";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    nix.settings.post-build-hook = "${pkgs.attic}/bin/attic upload --key ${cfg.atticKey} --cache ${cfg.atticCache} $out";
  };
}
