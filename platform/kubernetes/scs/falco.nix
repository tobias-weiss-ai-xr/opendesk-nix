# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Falco — CNCF runtime security monitoring for SCS K3s cluster.
# Deployed as DaemonSet to monitor syscalls on every node.
# Custom rules detect writes to Ceph mounts, K3s bootstrap data access,
# shell execution in containers, and crypto mining activity.
#
# K3s uses containerd — socket path: /run/containerd/containerd.sock
# Bare-metal cluster: 3 nodes (clrz14-06/07/08), CPU budget is limited.
#
# Aligns with ZKI checkpoint P0-AUD-001 (centralized log aggregation).

{ lib, env ? import ../environments/scs/default.nix { inherit lib; }, ... }:

let
  name = "falco";
  namespace = "falco";
  image = "falcosecurity/falco";
  tag = "0.39.0";
  initImage = "falcosecurity/falco-init";
  initTag = "0.39.0";

  labels = lib.mkLabels {
    inherit name;
    partOf = "scs-security";
  } // {
    "app.kubernetes.io/component" = "runtime-security";
    "app.kubernetes.io/managed-by" = "nix";
  };

  # Falco is CPU-hungry on bare-metal — generous but bounded
  resources = {
    requests = {
      cpu = "200m";
      memory = "256Mi";
    };
    limits = {
      cpu = "1000m";
      memory = "1Gi";
    };
  };

  # Custom Falco rules for SCS environment
  customRules = builtins.toJSON {
    customRules = [
      # Detect shell in containers (default Falco rule, explicit here for clarity)
      {
        rule = "Terminal Shell in Container";
        condition =
          "spawned_process and container and proc.name in (bash, sh, zsh, fish) and proc.pname != docker-entrypoint and not proc.cmdline contains --version";
        output =
          "Terminal shell spawned in container (user=%user.name command=%proc.cmdline container=%container.name image=%container.image.repository)";
        priority = "WARNING";
        tags = [ "container" "shell" "mitre_execution" ];
      }
      # Detect crypto mining
      {
        rule = "Detect Crypto Mining";
        condition =
          "spawned_process and container and (proc.name in (xmrig, minerd, cryptonight) or proc.cmdline contains stratum or proc.cmdline contains pool)";
        output =
          "Crypto mining detected (user=%user.name command=%proc.cmdline container=%container.name image=%container.image.repository)";
        priority = "CRITICAL";
        tags = [ "container" "crypto" "mitre_execution" ];
      }
      # Detect writes to Ceph mount paths
      {
        rule = "Detect Ceph Mount Write";
        condition =
          "open_write and fd.name startswith /mnt/ceph and container";
        output =
          "Write to Ceph mount detected (user=%user.name file=%fd.name container=%container.name image=%container.image.repository)";
        priority = "WARNING";
        tags = [ "container" "filesystem" "storage" ];
      }
      # Detect access to K3s bootstrap data
      {
        rule = "Detect K3s Bootstrap Access";
        condition =
          "open_read and fd.name startswith /var/lib/rancher/k3s and container";
        output =
          "Access to K3s bootstrap data detected (user=%user.name file=%fd.name container=%container.name image=%container.image.repository)";
        priority = "WARNING";
        tags = [ "container" "kubernetes" "config" ];
      }
      # Detect container escape attempts via /proc
      {
        rule = "Detect Proc Escape Attempt";
        condition =
          "open_read and fd.name startswith /proc/1/ and container and not user.name = root";
        output =
          "Potential container escape via /proc access (user=%user.name file=%fd.name container=%container.name image=%container.image.repository)";
        priority = "CRITICAL";
        tags = [ "container" "escape" "mitre_privilege_escalation" ];
      }
      # Detect network connections from containers to mining pool ports
      {
        rule = "Detect Mining Pool Connection";
        condition =
          "outbound and container and (fd.sport = 3333 or fd.sport = 4444 or fd.sport = 5555 or fd.sport = 8888 or fd.lport = 3333 or fd.lport = 4444)";
        output =
          "Suspicious mining pool port connection (user=%user.name connection=%fd.name container=%container.name image=%container.image.repository)";
        priority = "WARNING";
        tags = [ "container" "network" "crypto" ];
      }
    ];
    macros = [ ];
    lists = [ ];
  };

  # Falco configuration
  falcoConfig = builtins.toJSON {
    rules_file = [ "-rule" "/etc/falco/rules.d/rules.yaml" ];
    json_output = true;
    json_include_output_property = true;
    log_level = "info";
    log_stderr = true;
    log_syslog = false;
    outputs = [
      {
        type = "http";
        config = {
          url = "http://falco-sidekick:2801/";
        };
      }
    ];
    syscall_event_drops = {
      actions = [ "log" "alert" ];
      rate = 33.3;
      max_burst = 100;
    };
  };

in [
  # Namespace
  (lib.namespace {
    name = namespace;
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged";
      # Falco requires privileged for syscall instrumentation
      "pod-security.kubernetes.io/audit" = "restricted";
      "pod-security.kubernetes.io/warn" = "restricted";
    };
  })

  # ServiceAccount
  (lib.serviceAccount {
    name = name;
    namespace = namespace;
    labels = labels;
    automountServiceAccountToken = true;
  })

  # ClusterRole — read access to Pods, Nodes, Namespaces for event metadata
  {
    apiVersion = "rbac.authorization.k8s.io/v1";
    kind = "ClusterRole";
    metadata = {
      name = name;
      labels = labels;
    };
    rules = [
      {
        apiGroups = [ "" ];
        resources = [ "pods" "nodes" "namespaces" ];
        verbs = [ "get" "list" "watch" ];
      }
      {
        apiGroups = [ "apps" ];
        resources = [ "replicasets" "daemonsets" "deployments" "statefulsets" ];
        verbs = [ "get" "list" "watch" ];
      }
      {
        apiGroups = [ "" ];
        resources = [ "events" ];
        verbs = [ "create" "patch" ];
      }
    ];
  }

  # ClusterRoleBinding
  {
    apiVersion = "rbac.authorization.k8s.io/v1";
    kind = "ClusterRoleBinding";
    metadata = {
      name = name;
      labels = labels;
    };
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io";
      kind = "ClusterRole";
      name = name;
    };
    subjects = [{
      kind = "ServiceAccount";
      name = name;
      namespace = namespace;
    }];
  }

  # ConfigMap — Falco custom rules
  {
    apiVersion = "v1";
    kind = "ConfigMap";
    metadata = {
      name = "${name}-rules";
      namespace = namespace;
      labels = labels;
    };
    data = {
      "rules.yaml" = customRules;
    };
  }

  # ConfigMap — Falco configuration
  {
    apiVersion = "v1";
    kind = "ConfigMap";
    metadata = {
      name = "${name}-config";
      namespace = namespace;
      labels = labels;
    };
    data = {
      "falco.yaml" = falcoConfig;
    };
  }

  # DaemonSet — Falco runs on every node
  {
    apiVersion = "apps/v1";
    kind = "DaemonSet";
    metadata = {
      name = name;
      namespace = namespace;
      labels = labels;
    };
    spec = {
      revisionHistoryLimit = 10;
      selector = {
        matchLabels = lib.mkSelectorLabels { inherit name; };
      };
      updateStrategy = {
        type = "RollingUpdate";
        rollingUpdate = {
          maxUnavailable = 1;
        };
      };
      template = {
        metadata = {
          labels = labels;
          annotations = {
            "prometheus.io/scrape" = "true";
            "prometheus.io/port" = "8765";
            "prometheus.io/path" = "/metrics";
          };
        };
        spec = {
          serviceAccountName = name;
          # Falco requires privileged mode for syscall tracing via eBPF
          # This is intentional — Falco's purpose IS deep kernel observation
          securityContext = {
            fsGroup = 2000;
            fsGroupChangePolicy = "OnRootMismatch";
          };
          initContainers = [{
            name = "${name}-init";
            image = "${initImage}:${initTag}";
            imagePullPolicy = "IfNotPresent";
            args = [
              "driver-init"
              "--pull"
              "--type"
              "module"
              "--mount"
              "/host/modules"
              "--mod-version"
              # Match Falco version to kernel driver version
              "0.39.0"
            ];
            resources = {
              requests = {
                cpu = "50m";
                memory = "64Mi";
              };
              limits = {
                cpu = "200m";
                memory = "128Mi";
              };
            };
            securityContext = {
              privileged = true;
              runAsUser = 0;
            };
            volumeMounts = [
              {
                name = "boot-fs";
                mountPath = "/host/boot";
                readOnly = true;
              }
              {
                name = "modules-dir";
                mountPath = "/host/modules";
              }
              {
                name = "usr-src";
                mountPath = "/host/usr/src";
                readOnly = true;
              }
            ];
          }];
          containers = [{
            name = name;
            image = "${image}:${tag}";
            imagePullPolicy = "IfNotPresent";
            resources = resources;
            # Falco MUST run privileged for eBPF syscall tracing
            securityContext = {
              privileged = true;
              runAsUser = 0;
            };
            env = [
              {
                name = "FALCO_BPF_PROBE";
                value = "";
              }
              {
                name = "SYSDIG_HOST_ROOT";
                value = "/host";
              }
              {
                name = "HOST_ROOT";
                value = "/host";
              }
              {
                name = "FALCO_DRIVER";
                # K3s comes with eBPF support on modern kernels
                value = "module";
              }
            ];
            volumeMounts = [
              {
                name = "root-fs";
                mountPath = "/host/root";
                readOnly = true;
              }
              {
                name = "boot-fs";
                mountPath = "/host/boot";
                readOnly = true;
              }
              {
                name = "modules-dir";
                mountPath = "/host/modules";
                readOnly = true;
              }
              {
                name = "usr-src";
                mountPath = "/host/usr/src";
                readOnly = true;
              }
              {
                name = "docker-sock";
                mountPath = "/host/var/run/containerd/containerd.sock";
              }
              {
                name = "dev-fs";
                mountPath = "/host/dev";
              }
              {
                name = "proc-fs";
                mountPath = "/host/proc";
                readOnly = true;
              }
              {
                name = "falco-rules";
                mountPath = "/etc/falco/rules.d";
              }
              {
                name = "falco-config";
                mountPath = "/etc/falco";
                subPath = "falco.yaml";
              }
              {
                name = "tmp-dir";
                mountPath = "/tmp";
              }
            ];
            ports = [
              {
                containerPort = 8765;
                name = "metrics";
                protocol = "TCP";
              }
            ];
          }];
          volumes = [
            {
              name = "root-fs";
              hostPath = {
                path = "/";
                type = "Directory";
              };
            }
            {
              name = "boot-fs";
              hostPath = {
                path = "/boot";
                type = "Directory";
              };
            }
            {
              name = "modules-dir";
              hostPath = {
                path = "/lib/modules";
                type = "DirectoryOrCreate";
              };
            }
            {
              name = "usr-src";
              hostPath = {
                path = "/usr/src";
                type = "Directory";
              };
            }
            {
              name = "docker-sock";
              hostPath = {
                path = "/run/containerd/containerd.sock";
                type = "Socket";
              };
            }
            {
              name = "dev-fs";
              hostPath = {
                path = "/dev";
                type = "Directory";
              };
            }
            {
              name = "proc-fs";
              hostPath = {
                path = "/proc";
                type = "Directory";
              };
            }
            {
              name = "falco-rules";
              configMap = {
                name = "${name}-rules";
                items = [{
                  key = "rules.yaml";
                  path = "rules.yaml";
                }];
              };
            }
            {
              name = "falco-config";
              configMap = {
                name = "${name}-config";
                items = [{
                  key = "falco.yaml";
                  path = "falco.yaml";
                }];
              };
            }
            {
              name = "tmp-dir";
              emptyDir = { };
            }
          ];
          # Falco needs to run on ALL nodes including master
          tolerations = [{
            key = "node-role.kubernetes.io/master";
            operator = "Exists";
            effect = "NoSchedule";
          } {
            key = "node-role.kubernetes.io/control-plane";
            operator = "Exists";
            effect = "NoSchedule";
          }];
          dnsPolicy = "ClusterFirstWithHostNet";
          restartPolicy = "Always";
        };
      };
    };
  }
]
