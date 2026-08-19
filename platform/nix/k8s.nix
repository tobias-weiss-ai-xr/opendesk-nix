# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Kubernetes resource builders for openDesk Nix deployment.
# Pure functions: input in, manifest out, no side effects.
# Errors surface at build time, not runtime.

{ lib, ... }:

let
  # ===========================================================================
  # DEFAULTS
  # ===========================================================================

  defaultSecurityContext = {
    allowPrivilegeEscalation = false;
    runAsNonRoot = true;
    readOnlyRootFilesystem = true;
    capabilities = {
      drop = [ "ALL" ];
      add = [ "NET_BIND_SERVICE" ];
    };
  };

  defaultPodSecurityContext = {
    runAsNonRoot = true;
    runAsUser = 1000;
    fsGroup = 2000;
    fsGroupChangePolicy = "OnRootMismatch";
  };

  defaultResources = {
    limits = {
      cpu = "500m";
      memory = "512Mi";
    };
    requests = {
      cpu = "100m";
      memory = "128Mi";
    };
  };

  # ===========================================================================
  # LABELS
  # ===========================================================================

  mkOCILabels =
    {
      name,
      version,
      description ? "",
      component ? "backend",
    }:
    {
      "app.kubernetes.io/name" = name;
      "app.kubernetes.io/version" = version;
      "app.kubernetes.io/component" = component;
      "app.kubernetes.io/part-of" = "opendesk";
      "app.kubernetes.io/managed-by" = "nix";
      "org.opencontainers.image.title" = name;
      "org.opencontainers.image.description" = description;
      "org.opencontainers.image.version" = version;
    };

  mkLabels =
    {
      name,
      partOf ? "opendesk",
      instance ? null,
      version ? null,
    }:
    {
      app = name;
      "app.kubernetes.io/name" = name;
      "app.kubernetes.io/part-of" = partOf;
    }
    // (lib.optionalAttrs (instance != null) {
      "app.kubernetes.io/instance" = instance;
    })
    // (lib.optionalAttrs (version != null) {
      "app.kubernetes.io/version" = version;
    });

  mkSelectorLabels =
    {
      name,
      instance ? null,
    }:
    {
      app = name;
    }
    // (lib.optionalAttrs (instance != null) { inherit instance; });

  # ===========================================================================
  # PROBES
  # ===========================================================================

  mkProbe =
    {
      type ? "http",
      port ? null,
      path ? "/healthz",
      initialDelaySeconds ? 30,
      periodSeconds ? 10,
      timeoutSeconds ? 5,
      successThreshold ? 1,
      failureThreshold ? 3,
    }:
    if type == "http" then
      {
        httpGet = {
          inherit path;
          port = if port != null then port else 8080;
          scheme = "HTTP";
        };
        inherit
          initialDelaySeconds
          periodSeconds
          timeoutSeconds
          successThreshold
          failureThreshold
          ;
      }
    else if type == "tcp" then
      {
        tcpSocket = {
          port = if port != null then port else 8080;
        };
        inherit
          initialDelaySeconds
          periodSeconds
          timeoutSeconds
          successThreshold
          failureThreshold
          ;
      }
    else
      {
        exec = {
          command = [
            "/bin/sh"
            "-c"
            path
          ];
        };
        inherit
          initialDelaySeconds
          periodSeconds
          timeoutSeconds
          successThreshold
          failureThreshold
          ;
      };

  # ===========================================================================
  # POD TEMPLATE
  # ===========================================================================

  mkPodTemplate =
    {
      name,
      image,
      tag ? "latest",
      port ? 8080,
      labels ? null,
      annotations ? { },
      securityCtx ? defaultSecurityContext,
      resources ? defaultResources,
      env ? [ ],
      ports ? null,
      ...
    }:
    let
      selLabels = if labels != null then labels else mkLabels { inherit name; };
      defaultPorts = [
        {
          containerPort = port;
          name = "http";
          protocol = "TCP";
        }
      ];
      usedPorts = if ports != null then ports else defaultPorts;
    in
    {
      metadata = {
        inherit name;
        labels = selLabels;
        inherit annotations;
      };
      spec = {
        containers = [
          ({
            inherit name;
            image = "${image}:${tag}";
            imagePullPolicy = "IfNotPresent";
            ports = usedPorts;
            inherit resources;
            securityContext = securityCtx;
          } // (lib.optionalAttrs (env != [ ]) { inherit env; }))
        ];
      };
    };

  # ===========================================================================
  # DEPLOYMENT
  # ===========================================================================

  deployment =
    {
      name,
      image,
      tag ? "latest",
      port ? 8080,
      replicas ? 1,
      env ? [ ],
      envFrom ? [ ],
      resources ? defaultResources,
      securityContext ? defaultSecurityContext,
      podSecurityContext ? defaultPodSecurityContext,
      volumes ? [ ],
      volumeMounts ? [ ],
      initContainers ? [ ],
      imagePullSecrets ? [ ],
      command ? null,
      cmdArgs ? null,
      ports ? null,
      labels ? null,
      annotations ? { },
      nodeSelector ? { },
      tolerations ? [ ],
      affinity ? null,
      strategyType ? "RollingUpdate",
      maxSurge ? "25%",
      maxUnavailable ? "25%",
      revisionHistoryLimit ? 10,
      progressDeadlineSeconds ? 600,
      priorityClassName ? null,
      terminationGracePeriodSeconds ? 30,
      namespace ? null,
      ...
    }:
    let
      selLabels = if labels != null then labels else mkLabels { inherit name; };
      usedPorts =
        if ports != null then
          ports
        else
          [
            {
              containerPort = port;
              name = "http";
              protocol = "TCP";
            }
          ];
      container =
        {
          inherit name;
          image = "${image}:${tag}";
          imagePullPolicy = "IfNotPresent";
          ports = usedPorts;
          inherit resources;
          inherit securityContext;
        }
        // (lib.optionalAttrs (env != [ ]) { inherit env; })
        // (lib.optionalAttrs (envFrom != [ ]) { inherit envFrom; })
        // (lib.optionalAttrs (volumeMounts != [ ]) { inherit volumeMounts; })
        // (lib.optionalAttrs (command != null) { inherit command; })
        // (lib.optionalAttrs (cmdArgs != null) { args = cmdArgs; });
    in
    {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = {
        inherit name;
        labels = selLabels;
      } // (lib.optionalAttrs (namespace != null) { inherit namespace; });
      spec = {
        inherit replicas;
        inherit revisionHistoryLimit;
        inherit progressDeadlineSeconds;
        selector = {
          matchLabels = mkSelectorLabels { inherit name; };
        };
        template = {
          metadata = {
            labels = selLabels;
            inherit annotations;
          };
          spec =
            {
              containers = [ container ];
              securityContext = podSecurityContext;
              inherit volumes;
              restartPolicy = "Always";
              inherit terminationGracePeriodSeconds;
              dnsPolicy = "ClusterFirst";
              dnsConfig = {
                searches = [
                  "opendesk.svc.cluster.local"
                  "svc.cluster.local"
                  "cluster.local"
                ];
              };
            }
            // (lib.optionalAttrs (initContainers != [ ]) { inherit initContainers; })
            // (lib.optionalAttrs (affinity != null) { inherit affinity; })
            // (lib.optionalAttrs (nodeSelector != { }) {
              inherit nodeSelector;
            })
            // (lib.optionalAttrs (tolerations != [ ]) { inherit tolerations; })
            // (lib.optionalAttrs (imagePullSecrets != [ ]) {
              inherit imagePullSecrets;
            })
            // (lib.optionalAttrs (priorityClassName != null) {
              inherit priorityClassName;
            });
        };
        strategy =
          {
            type = strategyType;
          }
          // lib.optionalAttrs (strategyType == "RollingUpdate") {
            rollingUpdate = { inherit maxSurge maxUnavailable; };
          };
      };
    };

  # Alias
  mkDeployment = deployment;

  # ===========================================================================
  # STATEFULSET
  # ===========================================================================

  statefulset =
    {
      name,
      image,
      tag ? "latest",
      port ? 8080,
      replicas ? 1,
      serviceName ? name,
      env ? [ ],
      envFrom ? [ ],
      resources ? defaultResources,
      securityContext ? defaultSecurityContext,
      podSecurityContext ? defaultPodSecurityContext,
      liveness ? null,
      readiness ? null,
      volumeClaims ? [ ],
      volumes ? [ ],
      volumeMounts ? [ ],
      imagePullSecrets ? [ ],
      command ? null,
      cmdArgs ? null,
      ports ? null,
      labels ? null,
      annotations ? { },
      nodeSelector ? { },
      tolerations ? [ ],
      affinity ? null,
      podManagementPolicy ? "Parallel",
      updateStrategy ? "RollingUpdate",
      revisionHistoryLimit ? 10,
      priorityClassName ? null,
      terminationGracePeriodSeconds ? 30,
      namespace ? null,
      instance ? null,
      ...
    }:
    let
      selLabels = if labels != null then labels else mkLabels { inherit name instance; };
      usedPorts =
        if ports != null then
          ports
        else
          [
            {
              containerPort = port;
              name = "http";
              protocol = "TCP";
            }
          ];
      probeLiveness =
        if liveness != null then
          liveness
        else
          mkProbe {
            type = "tcp";
            inherit port;
          };
      probeReadiness =
        if readiness != null then
          readiness
        else
          mkProbe {
            type = "tcp";
            inherit port;
            initialDelaySeconds = 5;
          };
      container =
        {
          inherit name;
          image = "${image}:${tag}";
          imagePullPolicy = "IfNotPresent";
          ports = usedPorts;
          inherit resources;
          inherit securityContext;
          livenessProbe = probeLiveness;
          readinessProbe = probeReadiness;
        }
        // (lib.optionalAttrs (env != [ ]) { inherit env; })
        // (lib.optionalAttrs (envFrom != [ ]) { inherit envFrom; })
        // (lib.optionalAttrs (volumeMounts != [ ]) { inherit volumeMounts; })
        // (lib.optionalAttrs (command != null) { inherit command; })
        // (lib.optionalAttrs (cmdArgs != null) { args = cmdArgs; });
    in
    {
      apiVersion = "apps/v1";
      kind = "StatefulSet";
      metadata = {
        inherit name;
        labels = selLabels;
      } // (lib.optionalAttrs (namespace != null) { inherit namespace; });
      spec = {
        inherit serviceName;
        inherit replicas;
        inherit podManagementPolicy;
        updateStrategy = {
          type = updateStrategy;
        };
        inherit revisionHistoryLimit;
        selector = {
          matchLabels = mkSelectorLabels { inherit name instance; };
        };
        template = {
          metadata = {
            labels = selLabels;
            inherit annotations;
          };
          spec =
            {
              containers = [ container ];
              securityContext = podSecurityContext;
              inherit volumes;
              restartPolicy = "Always";
              inherit terminationGracePeriodSeconds;
              dnsPolicy = "ClusterFirst";
            }
            // (lib.optionalAttrs (affinity != null) { inherit affinity; })
            // (lib.optionalAttrs (nodeSelector != { }) {
              inherit nodeSelector;
            })
            // (lib.optionalAttrs (tolerations != [ ]) { inherit tolerations; })
            // (lib.optionalAttrs (imagePullSecrets != [ ]) {
              inherit imagePullSecrets;
            })
            // (lib.optionalAttrs (priorityClassName != null) {
              inherit priorityClassName;
            });
        };
        volumeClaimTemplates = volumeClaims;
      };
    };

  mkStatefulSet = statefulset;

  # ===========================================================================
  # SERVICE
  # ===========================================================================

  service =
    {
      name,
      port ? 8080,
      targetPort ? null,
      type ? "ClusterIP",
      selector ? null,
      ports ? null,
      sessionAffinity ? "None",
      externalTrafficPolicy ? "Cluster",
      loadBalancerSourceRanges ? [ ],
      loadBalancerClass ? null,
      labels ? null,
      namespace ? null,
      instance ? null,
      ...
    }:
    let
      selLabels = if selector != null then selector else mkSelectorLabels { inherit name instance; };
      usedPorts =
        if ports != null then
          ports
        else
          [
            {
              inherit port;
              targetPort = if targetPort != null then targetPort else port;
              protocol = "TCP";
              name = "http";
            }
          ];
      svcLabels = if labels != null then labels else mkLabels { inherit name instance; };
    in
    {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        inherit name;
        labels = svcLabels;
      } // (lib.optionalAttrs (namespace != null) { inherit namespace; });
      spec =
        {
          inherit type;
          ports = usedPorts;
          selector = selLabels;
          inherit sessionAffinity;
        }
        // (lib.optionalAttrs (type != "ClusterIP") {
          inherit externalTrafficPolicy;
        })
        // (lib.optionalAttrs (loadBalancerSourceRanges != [ ]) {
          inherit loadBalancerSourceRanges;
        })
        // (lib.optionalAttrs (loadBalancerClass != null) {
          inherit loadBalancerClass;
        });
    };

  mkService = service;

  # ===========================================================================
  # HEADLESS SERVICE
  # ===========================================================================

  headlessService =
    {
      name,
      port ? 8080,
      targetPort ? null,
      selector ? null,
      ports ? null,
      labels ? null,
      namespace ? null,
      instance ? null,
      ...
    }:
    let
      selLabels = if selector != null then selector else mkSelectorLabels { inherit name instance; };
      usedPorts =
        if ports != null then
          ports
        else
          [
            {
              inherit port;
              targetPort = if targetPort != null then targetPort else port;
              protocol = "TCP";
              name = "http";
            }
          ];
      svcLabels = if labels != null then labels else mkLabels { inherit name instance; };
    in
    {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        name = "${name}-headless";
        labels = svcLabels;
      } // (lib.optionalAttrs (namespace != null) { inherit namespace; });
      spec = {
        type = "ClusterIP";
        clusterIP = "None";
        ports = usedPorts;
        selector = selLabels;
      };
    };

  # ===========================================================================
  # INGRESS
  # ===========================================================================

  ingress =
    {
      name,
      hosts ? [ "${name}.opendesk.local" ],
      backendService,
      backendPort ? 8080,
      tls ? null,
      annotations ? { },
      pathType ? "Prefix",
      paths ? [ "/" ],
      className ? "haproxy",
      namespace ? null,
      ...
    }:
    let
      tlsConfig =
        if tls != null then
          tls
        else
          map (host: {
            hosts = [ host ];
            secretName = "tls-${name}";
          }) hosts;
    in
    {
      apiVersion = "networking.k8s.io/v1";
      kind = "Ingress";
      metadata = {
        inherit name;
        labels = mkLabels { inherit name; };
        inherit annotations;
      } // (lib.optionalAttrs (namespace != null) { inherit namespace; });
      spec = {
        ingressClassName = className;
        tls = tlsConfig;
        rules = map (host: {
          inherit host;
          http = {
            paths = map (path: {
              inherit path;
              inherit pathType;
              backend = {
                service = {
                  name = backendService;
                  port = {
                    number = backendPort;
                  };
                };
              };
            }) paths;
          };
        }) hosts;
      };
    };

  mkIngress = ingress;

  ingressWithCert =
    {
      name,
      host,
      port ? 80,
      className ? "haproxy",
      tlsSecretName ? "opendesk-certificates-tls",
      annotations ? { },
      namespace ? null,
      ...
    }:
    {
      apiVersion = "networking.k8s.io/v1";
      kind = "Ingress";
      metadata = {
        name = "${name}-ingress";
        labels = mkLabels { inherit name; };
        annotations = annotations // {
          "haproxy-ingress.github.io/ssl-redirect" = "true";
        };
      } // (lib.optionalAttrs (namespace != null) { inherit namespace; });
      spec = {
        ingressClassName = className;
        tls = [
          {
            hosts = [ host ];
            secretName = tlsSecretName;
          }
        ];
        rules = [
          {
            inherit host;
            http = {
              paths = [
                {
                  path = "/";
                  pathType = "Prefix";
                  backend = {
                    service = {
                      inherit name;
                      port = {
                        number = port;
                      };
                    };
                  };
                }
              ];
            };
          }
        ];
      };
    };

  mkIngressWithTLS = ingressWithCert;

  # ===========================================================================
  # CONFIGMAP
  # ===========================================================================

  configMap =
    {
      name,
      data,
      immutable ? false,
      labels ? null,
      namespace ? null,
      ...
    }:
    let
      cmLabels = if labels != null then labels else mkLabels { inherit name; };
    in
    {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        inherit name;
        labels = cmLabels;
      } // (lib.optionalAttrs (namespace != null) { inherit namespace; });
      inherit data;
      inherit immutable;
    };

  mkConfigMap = configMap;

  # ===========================================================================
  # SECRET
  # ===========================================================================

  secret =
    {
      name,
      stringData ? { },
      data ? { },
      type ? "Opaque",
      labels ? null,
      namespace ? null,
      ...
    }:
    let
      secLabels = if labels != null then labels else mkLabels { inherit name; };
    in
    {
      apiVersion = "v1";
      kind = "Secret";
      metadata = {
        inherit name;
        labels = secLabels;
      } // (lib.optionalAttrs (namespace != null) { inherit namespace; });
      inherit type;
    }
    // (lib.optionalAttrs (stringData != { }) { inherit stringData; })
    // (lib.optionalAttrs (data != { }) { inherit data; });

  mkOpaqueSecret = secret;

  # ===========================================================================
  # PVC
  # ===========================================================================

  pvc =
    {
      name,
      size ? "1Gi",
      storageClass ? "ceph-rbd",
      accessModes ? [ "ReadWriteOnce" ],
      volumeMode ? "Filesystem",
      labels ? null,
      namespace ? null,
      ...
    }:
    let
      pvcLabels = if labels != null then labels else mkLabels { inherit name; };
    in
    {
      apiVersion = "v1";
      kind = "PersistentVolumeClaim";
      metadata = {
        inherit name;
        labels = pvcLabels;
      } // (lib.optionalAttrs (namespace != null) { inherit namespace; });
      spec = {
        inherit accessModes;
        inherit volumeMode;
        storageClassName = storageClass;
        resources = {
          requests = {
            storage = size;
          };
        };
      };
    };

  mkPVC = pvc;

  # ===========================================================================
  # NETWORK POLICY
  # ===========================================================================

  networkPolicy =
    {
      name,
      podSelector ? null,
      namespaceSelector ? null,
      ingress ? null,
      egress ? null,
      policyTypes ? [
        "Ingress"
        "Egress"
      ],
      labels ? null,
      namespace ? null,
      ...
    }:
    let
      npLabels = if labels != null then labels else mkLabels { inherit name; };
      selLabels = if podSelector != null then podSelector else mkSelectorLabels { inherit name; };
    in
    {
      apiVersion = "networking.k8s.io/v1";
      kind = "NetworkPolicy";
      metadata = {
        inherit name;
        labels = npLabels;
      } // (lib.optionalAttrs (namespace != null) { inherit namespace; });
      spec =
        {
          podSelector = {
            matchLabels = selLabels;
          };
          inherit policyTypes;
        }
        // (lib.optionalAttrs (ingress != null) { inherit ingress; })
        // (lib.optionalAttrs (egress != null) { inherit egress; })
        // (lib.optionalAttrs (namespaceSelector != null) {
          inherit namespaceSelector;
        });
    };

  mkNetworkPolicy = networkPolicy;

  # ===========================================================================
  # POD DISRUPTION BUDGET
  # ===========================================================================

  pdb =
    {
      name,
      minAvailable ? 1,
      maxUnavailable ? null,
      selector ? null,
      labels ? null,
      namespace ? null,
      ...
    }:
    let
      pdbLabels = if labels != null then labels else mkLabels { inherit name; };
      selLabels = if selector != null then selector else mkSelectorLabels { inherit name; };
    in
    {
      apiVersion = "policy/v1";
      kind = "PodDisruptionBudget";
      metadata = {
        inherit name;
        labels = pdbLabels;
      } // (lib.optionalAttrs (namespace != null) { inherit namespace; });
      spec =
        {
          selector = {
            matchLabels = selLabels;
          };
        }
        // (lib.optionalAttrs (minAvailable != null) { inherit minAvailable; })
        // (lib.optionalAttrs (maxUnavailable != null) {
          inherit maxUnavailable;
        });
    };

  mkPDB = pdb;

  # ===========================================================================
  # HPA
  # ===========================================================================

  hpa =
    {
      name,
      targetRef,
      minReplicas ? 1,
      maxReplicas ? 3,
      cpuTarget ? 80,
      memoryTarget ? null,
      behavior ? null,
      metrics ? null,
      labels ? null,
      namespace ? null,
      targetCPUUtilization ? null,
      ...
    }:
    let
      hpaLabels = if labels != null then labels else mkLabels { name = targetRef.name or name; };
      cpuUtil = if targetCPUUtilization != null then targetCPUUtilization else cpuTarget;
      cpuMetric = {
        type = "Resource";
        resource = {
          name = "cpu";
          target = {
            type = "Utilization";
            averageUtilization = cpuUtil;
          };
        };
      };
      memoryMetric =
        if memoryTarget != null then
          {
            type = "Resource";
            resource = {
              name = "memory";
              target = {
                type = "Utilization";
                averageUtilization = memoryTarget;
              };
            };
          }
        else
          null;
      allMetrics =
        (if metrics != null then metrics else [ ])
        ++ [ cpuMetric ]
        ++ (if memoryMetric != null then [ memoryMetric ] else [ ]);
    in
    {
      apiVersion = "autoscaling/v2";
      kind = "HorizontalPodAutoscaler";
      metadata = {
        inherit name;
        labels = hpaLabels;
      } // (lib.optionalAttrs (namespace != null) { inherit namespace; });
      spec = {
        scaleTargetRef = targetRef;
        inherit minReplicas;
        inherit maxReplicas;
        metrics = allMetrics;
      } // (lib.optionalAttrs (behavior != null) { inherit behavior; });
    };

  mkHPA = hpa;

  # ===========================================================================
  # NAMESPACE
  # ===========================================================================

  namespace =
    {
      name,
      labels ? { },
      ...
    }:
    {
      apiVersion = "v1";
      kind = "Namespace";
      metadata = {
        inherit name;
        labels = labels // {
          "app.kubernetes.io/part-of" = "opendesk";
        };
      };
    };

  # ===========================================================================
  # SERVICE ACCOUNT
  # ===========================================================================

  serviceAccount =
    {
      name,
      namespace ? null,
      automountServiceAccountToken ? false,
      labels ? null,
      ...
    }:
    let
      saLabels = if labels != null then labels else mkLabels { inherit name; };
    in
    {
      apiVersion = "v1";
      kind = "ServiceAccount";
      metadata = {
        inherit name;
        labels = saLabels;
      } // (lib.optionalAttrs (namespace != null) { inherit namespace; });
      inherit automountServiceAccountToken;
    };

  # ===========================================================================
  # TLS SECRET (placeholder)
  # ===========================================================================

  mkTLSSecret =
    {
      name,
      namespace ? null,
      labels ? null,
      ...
    }:
    let
      tlsLabels = if labels != null then labels else mkLabels { inherit name; };
    in
    {
      apiVersion = "v1";
      kind = "Secret";
      metadata = {
        inherit name;
        labels = tlsLabels;
      } // (lib.optionalAttrs (namespace != null) { inherit namespace; });
      type = "kubernetes.io/tls";
    };

  # ===========================================================================
  # SECURITY CONTEXT HELPERS
  # ===========================================================================

  securityContext = defaultSecurityContext;

  # Database security context (needs SYS_NICE for MariaDB)
  databaseSecurityContext = {
    allowPrivilegeEscalation = false;
    runAsNonRoot = false;
    readOnlyRootFilesystem = false;
    capabilities = {
      drop = [ "ALL" ];
      add = [
        "SYS_NICE"
        "DAC_OVERRIDE"
        "CHOWN"
        "FOWNER"
        "SETGID"
        "SETUID"
      ];
    };
  };

  databasePodSecurityContext = {
    runAsNonRoot = false;
    fsGroup = 999;
    fsGroupChangePolicy = "OnRootMismatch";
  };

in
{
  inherit
    defaultSecurityContext
    defaultPodSecurityContext
    defaultResources
    mkOCILabels
    mkLabels
    mkSelectorLabels
    mkProbe
    mkPodTemplate
    deployment
    mkDeployment
    statefulset
    mkStatefulSet
    service
    mkService
    headlessService
    ingress
    mkIngress
    ingressWithCert
    mkIngressWithTLS
    configMap
    mkConfigMap
    secret
    mkOpaqueSecret
    mkTLSSecret
    pvc
    mkPVC
    networkPolicy
    mkNetworkPolicy
    pdb
    mkPDB
    hpa
    mkHPA
    namespace
    serviceAccount
    securityContext
    databaseSecurityContext
    databasePodSecurityContext
    ;
}
