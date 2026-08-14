# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Cosign Image Verification Policies — Kyverno verifyImages rules for SCS K3s.
# Activates ZKI checkpoint P0-CONT-001 (Cosign image verification).
#
# Uses key-based Cosign signing (SCS is behind university firewall, no OIDC keyless).
# The public key is stored as a ConfigMap placeholder — deploy real key via
# kubectl create configmap cosign-pub --from-file=cosign.pub=<pubkey-path>
# BEFORE applying these policies.
#
# Audit mode initially — switch to Enforce after key rotation and validation.

{ lib, ... }:

let
  labels =
    lib.mkLabels {
      name = "cosign-policies";
      partOf = "scs-security";
    }
    // {
      "app.kubernetes.io/component" = "image-verification";
      "app.kubernetes.io/managed-by" = "nix";
      "policies.kyverno.io/category" = "Supply Chain";
    };

in
[
  # =============================================================================
  # ConfigMap — Cosign public key placeholder
  # Replace with actual public key before deployment:
  #   cosign keypair -name opendesk-scs
  #   kubectl create configmap cosign-pub -n opendesk \
  #     --from-file=cosign.pub=cosign.pub --dry-run=client -o yaml | kubectl apply -f -
  # =============================================================================
  {
    apiVersion = "v1";
    kind = "ConfigMap";
    metadata = {
      name = "cosign-pub";
      namespace = "opendesk";
      inherit labels;
    };
    data = {
      "cosign.pub" = ''
        # PLACEHOLDER — Replace with actual Cosign public key
        # Generated via: cosign generate-key-pair
        # The private key (.cosign.key) must be stored securely offline
        # and used in the SCS devShell for signing images.
        #
        # Example key format:
        # -----BEGIN PUBLIC KEY-----
        # MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE...
        # -----END PUBLIC KEY-----
      '';
    };
  }

  # =============================================================================
  # POLICY: Verify Image Signatures via Cosign
  # Uses Kyverno verifyImages rule type for key-based attestation.
  # Matches only opendesk and opendesk-edu namespaces (NOT kube-system).
  # =============================================================================
  {
    apiVersion = "kyverno.io/v2beta1";
    kind = "ClusterPolicy";
    metadata = {
      name = "verify-signed-images";
      labels = labels // {
        "policies.kyverno.io/title" = "Verify Signed Images";
      };
      annotations = {
        "policies.kyverno.io/description" =
          "Verifies that container images are signed with Cosign key-based signatures before deployment. Air-gapped cluster requires key-based verification (no OIDC keyless).";
        "policies.kyverno.io/subject" = "Pod";
        "policies.kyverno.io/severity" = "high";
      };
    };
    spec = {
      validationFailureAction = "Audit";
      background = false;
      webhookTimeoutSeconds = 30;
      failurePolicy = "Fail";
      rules = [
        {
          name = "verify-cosign-signature";
          match = {
            any = [
              {
                resources = {
                  namespaces = [ "opendesk" ];
                };
              }
              {
                resources = {
                  namespaces = [ "opendesk-edu" ];
                };
              }
            ];
          };
          verifyImages = [
            {
              imageReferences = [
                "docker.io/weissto/*"
                "localhost:5001/*"
              ];
              attestors = [
                {
                  keys = [
                    {
                      # Reference the public key from the ConfigMap
                      publicKeys = "- | \n  -----BEGIN PUBLIC KEY-----\n  PLACEHOLDER_REPLACE_WITH_ACTUAL_KEY\n  -----END PUBLIC KEY-----";
                      # In production, use a k8s:// reference:
                      # kubernetes://opendesk/cosign-pub/cosign.pub
                    }
                  ];
                }
              ];
              attestations = [
                {
                  type = "https://aquasecurity.github.io/trivy-operator/trivy-scan";
                  conditions = [
                    {
                      key = "{{ items[].Report.Severity }}";
                      operator = "NotEquals";
                      value = "CRITICAL";
                    }
                  ];
                }
              ];
            }
          ];
        }
      ];
    };
  }

  # =============================================================================
  # POLICY: Require SBOM Attestation
  # Ensures images have an SBOM attestation attached (syft/cyclonedx format).
  # =============================================================================
  {
    apiVersion = "kyverno.io/v2beta1";
    kind = "ClusterPolicy";
    metadata = {
      name = "require-sbom-attestation";
      labels = labels // {
        "policies.kyverno.io/title" = "Require SBOM Attestation";
      };
      annotations = {
        "policies.kyverno.io/description" =
          "Requires that container images have a Software Bill of Materials (SBOM) attestation attached before deployment.";
        "policies.kyverno.io/subject" = "Pod";
        "policies.kyverno.io/severity" = "medium";
      };
    };
    spec = {
      validationFailureAction = "Audit";
      background = false;
      rules = [
        {
          name = "check-sbom-attestation";
          match = {
            any = [
              {
                resources = {
                  namespaces = [ "opendesk" ];
                };
              }
              {
                resources = {
                  namespaces = [ "opendesk-edu" ];
                };
              }
            ];
          };
          verifyImages = [
            {
              imageReferences = [ "docker.io/weissto/*" ];
              attestors = [
                {
                  entries = [
                    {
                      type = "https://cyclonedx.org/bom";
                      keys = {
                        rekor = {
                          ignoreTlog = true;
                        };
                      };
                    }
                  ];
                }
              ];
            }
          ];
        }
      ];
    };
  }
]
