# SPDX-License-Identifier: Apache-2.0
# A/B Update integration test

{ pkgs, ... }:

{
  name = "ab-updates";

  nodes = {
    builder = { ... }: { };

    node = pkgs.nixosTest {
      name = "ab-update-node";
      config = {
        # Enable A/B updates
        services.abUpdates = {
          enable = true;
          slots = "a";
          updateSource = "/nix/store";
          rollbackTimeout = 300;
        };

        # Basic system configuration
        system.stateVersion = "24.11";
      };
    };
  };

  testScript = ''
    # Start the node
    node.start()
    node.wait_for_unit("multi-user.target")

    # Check that A/B update service is enabled
    node.succeed("systemctl is-enabled ab-rollback-assessment.timer")

    # Check state directory exists
    node.succeed("test -d /var/lib/ab-updates")

    # Check active slot file exists
    node.succeed("test -f /var/lib/ab-updates/active_slot")

    # Verify systemd-sysupdate is available
    node.succeed("which systemd-sysupdate")

    # Check sysupdate configuration
    node.succeed("test -f /etc/systemd/sysupdate.d/ab-update.conf")

    # Run the update manager status command
    node.succeed("ab-update-manager status")

    # Verify rollback timer is configured
    node.succeed("systemctl list-timers ab-rollback-assessment.timer")

    print("All A/B update tests passed!")
  '';
}
