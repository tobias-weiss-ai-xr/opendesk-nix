# SPDX-License-Identifier: Apache-2.0
# Phase 5 Advanced Features Integration Test

{ pkgs, ... }:

{
  name = "phase5-advanced";

  nodes = {
    builder = _: { };

    node = pkgs.nixosTest {
      name = "advanced-features-node";
      config = {
        # Remote builders configuration
        nix.remoteBuilders = {
          enable = true;
          connectTimeout = 30;
          buildTimeout = 3600;
          nodes = [
            {
              name = "builder-1";
              endpoint = "nix-builder-1@10.0.0.10";
              sshKey = /etc/nix/builders/ssh-key;
              system = "x86_64-linux";
              maxJobs = 4;
              speedFactor = 2;
              supportedFeatures = [
                "kvm"
                "bigparallel"
              ];
            }
          ];
        };

        # Secure Boot configuration
        security.secureBoot = {
          enable = true;
          mode = "enroll";
          keySize = 3072;
          tpmAttestation = true;
          measuredBoot = true;
        };

        # Runtime state configuration
        services.runtimeState = {
          enable = true;
          syncInterval = 300;

          grafana = {
            enable = true;
            datasources = {
              prometheus = {
                type = "prometheus";
                url = "http://localhost:9090";
                default = true;
              };
            };
          };

          prometheus = {
            enable = true;
            scrapeConfigs = {
              node = {
                targets = [ "localhost:9100" ];
                interval = "15s";
              };
            };
            alertRules = {
              high-cpu = {
                alert = "HighCPUUsage";
                expr = "node_cpu_usage > 80";
                for = "5m";
                labels = {
                  severity = "warning";
                };
              };
            };
          };
        };

        # Basic system configuration
        system.stateVersion = "24.11";
      };
    };
  };

  testScript = _: ''
    # Start the node
    node.start()
    node.wait_for_unit("multi-user.target")

    # Test 1: Remote builders configuration
    print("Testing remote builders configuration...")
    node.succeed("nix show-config | grep -q 'builders'")
    node.succeed("test -f /etc/ssh/ssh_config")
    node.succeed("systemctl is-enabled nix-builder-health.timer")
    print("✓ Remote builders configuration valid")

    # Test 2: Secure Boot configuration
    print("Testing Secure Boot configuration...")
    node.succeed("test -d /etc/lanzaboote/pki")
    node.succeed("test -f /etc/lanzaboote/pki/ca.crt")
    node.succeed("test -f /etc/lanzaboote/pki/db.crt")
    node.succeed("systemctl is-active tpm2-abrmd")
    print("✓ Secure Boot configuration valid")

    # Test 3: TPM 2.0 configuration
    print("Testing TPM 2.0 configuration...")
    node.succeed("test -e /dev/tpmrm0")
    node.succeed("which tpm2_pcrextend")
    print("✓ TPM 2.0 configuration valid")

    # Test 4: Runtime state configuration
    print("Testing runtime state configuration...")
    node.succeed("test -f /etc/keycloak/realm.json")
    node.succeed("test -d /etc/grafana/provisioning")
    node.succeed("test -f /etc/prometheus/prometheus.yml")
    node.succeed("systemctl is-enabled opendesk-state-sync.timer")
    print("✓ Runtime state configuration valid")

    # Test 5: Grafana datasources
    print("Testing Grafana datasources...")
    node.succeed("test -f /etc/grafana/provisioning/datasources/prometheus.yml")
    print("✓ Grafana datasources configured")

    # Test 6: Prometheus alert rules
    print("Testing Prometheus alert rules...")
    node.succeed("grep -q 'HighCPUUsage' /etc/prometheus/rules/*.yml")
    print("✓ Prometheus alert rules configured")

    # Test 7: State sync timer
    print("Testing state sync timer...")
    node.succeed("systemctl list-timers opendesk-state-sync.timer")
    print("✓ State sync timer configured")

    print("")
    print("=== All Phase 5 tests passed! ===")
    print("")
    print("✓ Remote builders: Configured")
    print("✓ Secure Boot: Enabled")
    print("✓ TPM 2.0: Active")
    print("✓ Runtime state: Declarative")
    print("")
  '';
}
