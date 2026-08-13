# SPDX-License-Identifier: Apache-2.0
# Attic server integration test

{ pkgs, ... }: {

  name = "attic-server";

  nodes = {
    attic = { config, pkgs, ... }: {
      services.attic-server = {
        enable = true;
        listenPort = 8080;
        openFirewall = false;
        cacheDir = "/var/lib/attic";
      };
    };

    client = { config, pkgs, ... }: {
      nix.settings.substituters = [ "http://attic:8080" ];
      nix.settings.trusted-public-keys = [ "attic.scs.hrz@uni-marburg.de-1:abc123" ];
    };
  };

  testScript = ''
    # Start Attic server
    attic.start()
    attic.wait_for_unit("attic-server.service")
    
    # Verify server is responsive
    attic.succeed("curl -s http://localhost:8080/")
    
    # Client can substitute from cache
    client.succeed(
      "nix build --substituters http://attic:8080 .\hello"
    )
    
    # Verify path exists in cache
    attic.succeed("attic list main | grep hello")
  '';
}
