# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Basic integration test for opendesk-nix
# Based on ~/git/nix-best-practices/examples/integration-test.nix
#
# This tests that MariaDB service starts and accepts connections.
# Run with: nix flake check .#integration
# Or interactively: nix build .#checks.x86_64-linux.integration.driverInteractive

{ pkgs, ... }:

{
  name = "opendesk-mariadb-integration";

  nodes = {
    server = { config, ... }: {
      services.mysql = {
        enable = true;
        package = pkgs.mariadb;
        initialDatabases = [
          { name = "opendesk"; }
        ];
      };
      networking.firewall.allowedTCPPorts = [ 3306 ];
    };

    client = { ... }: {
      environment.systemPackages = [ pkgs.mariadb ];
    };
  };

  testScript = ''
    start_all()

    # Wait for MariaDB to be ready
    server.wait_for_unit("mysql.service")
    server.wait_for_open_port(3306)

    # Client must be able to connect
    client.systemctl("start network-online.target")
    client.wait_for_unit("network-online.target")

    # Test database connectivity
    client.succeed(
      "mysql -h server -P 3306 -u root -e 'SHOW DATABASES;' | grep opendesk"
    )

    # Test creating a table
    client.succeed(
      "mysql -h server -P 3306 -u root opendesk -e 'CREATE TABLE test (id INT);'"
    )
    client.succeed(
      "mysql -h server -P 3306 -u root opendesk -e 'INSERT INTO test VALUES (1);'"
    )
    result = client.succeed(
      "mysql -h server -P 3306 -u root opendesk -e 'SELECT * FROM test;'"
    )
    assert "1" in result, "Database write/read failed"
  '';

  # Interactive debugging (uncomment to use)
  # interactive.nodes.server = {
  #   virtualisation.forwardPorts = [{ from = "host"; host.port = 3306; guest.port = 3306; }];
  # };
}
