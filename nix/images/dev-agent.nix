# SPDX-License-Identifier: Apache-2.0
# Dev Agent Operator — AI-powered Kubernetes self-healing operator
# Image: dev-agent:latest-nix
# Built with: Nix dockerTools.buildLayeredImage using nixpkgs
# Registry: 172.17.0.6:5001/dev-agent:latest-nix

{ pkgs ? import <nixpkgs> { system = "x86_64-linux"; } }:

let
  operatorPy = pkgs.writeText "dev_agent.py" (builtins.readFile ./dev-agent-files/dev_agent.py);
  entrypointSh = pkgs.writeText "entrypoint.sh" (builtins.readFile ./dev-agent-files/entrypoint.sh);
  healthcheckSh = pkgs.writeText "healthcheck.sh" (builtins.readFile ./dev-agent-files/healthcheck.sh);

  devAgentDir = pkgs.runCommand "dev-agent-files" {} ''
    mkdir -p $out/opt/dev-agent $out/etc/opendesk-dev-agent $out/home/opendesk
    cp ${operatorPy} $out/opt/dev-agent/dev_agent.py
    cp ${entrypointSh} $out/opt/dev-agent/entrypoint.sh
    chmod +x $out/opt/dev-agent/entrypoint.sh
    cp ${healthcheckSh} $out/opt/dev-agent/healthcheck.sh
    chmod +x $out/opt/dev-agent/healthcheck.sh
  '';

in
pkgs.dockerTools.buildLayeredImage {
  name = "dev-agent";
  tag = "latest-nix";

  contents = with pkgs; [
    python3
    curl
    bash
    coreutils
    gnugrep
    gnused
    cacert
    procps
    kubectl
    devAgentDir
    dockerTools.fakeNss
  ];

  config = {
    User = "0:0";
    WorkingDir = "/home/opendesk";
    Entrypoint = [
      "${pkgs.bash}/bin/bash"
      "/opt/dev-agent/entrypoint.sh"
    ];
    Cmd = [
      "${pkgs.python3}/bin/python3"
      "/opt/dev-agent/dev_agent.py"
    ];
    Env = [
      "OPERATOR_NAME=opendesk-dev-agent"
      "OPERATOR_NAMESPACE=opendesk-dev-agent"
      "OPERATOR_VERSION=2.1.0"
      "OPERATOR_LOG_LEVEL=info"
      "OPERATOR_WATCH_NAMESPACES=opendesk,opendesk-edu,default,llm"
      "OLLAMA_URL=http://ollama.llm.svc.cluster.local:11434"
      "OLLAMA_MODEL=qwen3-30b-a3b:latest"
      "RECONCILE_INTERVAL=60"
      "OPERATOR_METRICS_BIND_ADDRESS=0.0.0.0:8080"
      "OPERATOR_HEALTH_PROBE_BIND_ADDRESS=0.0.0.0:8081"
      "K8S_CLUSTER_TYPE=k3s"
      "PATH=${pkgs.python3}/bin:${pkgs.curl}/bin:${pkgs.bash}/bin:${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin:${pkgs.procps}/bin:${pkgs.kubectl}/bin"
      "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      "HOME=/home/opendesk"
    ];
    ExposedPorts = {
      "8080/tcp" = {};
      "8081/tcp" = {};
    };
  };

  maxLayers = 50;
}
