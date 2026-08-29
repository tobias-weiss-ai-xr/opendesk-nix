# Zot Registry Nix Flake
# SPDX-License-Identifier: Apache-2.0
# Maintainer: openDesk Edu Team <team@opendesk-edu.org>
#
# ==============================================================================
# Builds Zot (OCI registry server) v2.1.20 from source and packages it as a
# container image, configured as an on-demand pull-through cache for the
# registries the SCS K3s cluster consumes (GHCR, docker.io, opencode.de,
# gitlab.opencode.de, registry.k8s.io).
#
# Usage:
#   nix build .#zot          # the zot binary itself
#   nix build .#zot-image    # the OCI container image tarball (docker load it)
#   docker load < result
#
# Deploy notes:
#   - Upstream credentials (e.g. GHCR PAT) are NOT baked into the image.
#     Mount a credentials file at /etc/zot/credentials.json with format:
#       { "ghcr.io": { "username": "...", "password": "..." } }
#   - Sync uses destination "/" (identity mapping): the local repo path equals
#     the upstream path. This matches containerd mirror behaviour, which strips
#     the registry host and leaves the full repository path.
#   - On-demand sync tries every configured registry in order and stops at the
#     first success; "not found" / "unauthorized" upstreams are skipped.
# ==============================================================================
{
  description = "Zot OCI registry (pull-through cache) built from source";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        zotSrc = pkgs.fetchFromGitHub {
          owner = "project-zot";
          repo = "zot";
          rev = "v2.1.20";
          sha256 = "sha256-lEw2VzPmKPisy6PmqZMf7cv+a19NSHsxJg+nosYMrGY=";
        };

        zot = pkgs.buildGoModule {
          pname = "zot";
          version = "2.1.20";
          src = zotSrc;
          # zot's in-tree vendor dir is stale/corrupt (modules.txt out of sync
          # with go.mod) -> drop it right after unpack so the module graph is
          # re-vendored fresh.
          postUnpack = ''
            rm -rf $sourceRoot/vendor
          '';
          vendorHash = "sha256-7B46O3YZdc8c1awn9iwm5+2I+sQn+ylhXzdY/Q6UOR4=";
          # zot extensions are behind Go build tags. We enable the set needed
          # for the pull-through cache (sync) plus operational extras.
          # "search" is intentionally omitted: it drags in zot's trivy
          # integration which requires Go's experimental encoding/json/v2
          # (GOEXPERIMENT=jsonv2). "ui" omitted to skip the embedded frontend.
          tags = [
            "sync"
            "scrub"
            "metrics"
            "lint"
            "profile"
            "userprefs"
            "imagetrust"
            "events"
            "mgmt"
          ];
          # zot's main is at cmd/zot
          subPackages = [ "cmd/zot" ];
          ldflags = [
            "-s"
            "-w"
            "-X github.com/project-zot/zot/cmd/zot/cli/AppVersion=2.1.20"
          ];
        };

        # Pull-through-capable default config (sync on-demand, identity mapping).
        zotConfig = pkgs.writeText "config.json" (builtins.toJSON {
          distSpecVersion = "1.1.1";
          storage = {
            rootDirectory = "/var/lib/zot";
            gc = true;
          };
          http = {
            address = "0.0.0.0";
            port = "5001";
          };
          log = {
            level = "info";
            output = "/dev/stdout";
          };
          extensions = {
            sync = {
              enable = true;
              # credentials for authed upstreams (GHCR PAT etc.); mount at
              # runtime, never baked into the image
              credentialsFile = "/etc/zot/credentials.json";
              registries = [
                {
                  urls = [ "https://ghcr.io" ];
                  # destination "/" = identity: local repo path == upstream path
                  content = [
                    {
                      destination = "/";
                      prefix = "**";
                    }
                  ];
                  onDemand = true;
                  tlsVerify = true;
                }
                {
                  urls = [ "https://registry-1.docker.io" ];
                  content = [
                    {
                      destination = "/";
                      prefix = "**";
                    }
                  ];
                  onDemand = true;
                  tlsVerify = true;
                }
                {
                  urls = [ "https://registry.opencode.de" ];
                  content = [
                    {
                      destination = "/";
                      prefix = "**";
                    }
                  ];
                  onDemand = true;
                  tlsVerify = true;
                }
                {
                  urls = [ "https://registry.gitlab.opencode.de" ];
                  content = [
                    {
                      destination = "/";
                      prefix = "**";
                    }
                  ];
                  onDemand = true;
                  tlsVerify = true;
                }
                {
                  urls = [ "https://registry.k8s.io" ];
                  content = [
                    {
                      destination = "/";
                      prefix = "**";
                    }
                  ];
                  onDemand = true;
                  tlsVerify = true;
                }
              ];
            };
          };
        });

        zotImage = pkgs.dockerTools.buildLayeredImage {
          name = "zot";
          tag = "2.1.20-nix";
          created = "now";
          contents = [ zot pkgs.cacert ];
          extraCommands = ''
            mkdir -p etc/zot
            cp ${zotConfig} etc/zot/config.json
            chmod 0644 etc/zot/config.json
            mkdir -p var/lib/zot
          '';
          config = {
            Entrypoint = [ "${zot}/bin/zot" ];
            Cmd = [ "serve" "/etc/zot/config.json" ];
            Env = [
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "SSL_CERT_DIR=${pkgs.cacert}/etc/ssl/certs"
            ];
            ExposedPorts = {
              "5001/tcp" = { };
            };
            Volumes = {
              "/var/lib/zot" = { };
            };
          };
        };
      in
      {
        packages = {
          zot = zot;
          zot-image = zotImage;
          default = zotImage;
        };
      });
}
