{ lib, ... }:

# =============================================================================
# OPERATORS PLUGIN LIBRARY
# Pluggable operator components for OpenDesk-Nix
# =============================================================================

{
  # ---------------------------------------------------------------------------
  # Types and Constants
  # ---------------------------------------------------------------------------

  types = {
    operator = [
      "compliance"
      "image-builder"
      "security-scanner"
      "attestation"
      "policy"
    ];
    action =
      [ "create" "update" "delete" "validate" "scan" "sign" "attest" "block" ];
    resource = [
      "Pod"
      "Deployment"
      "StatefulSet"
      "DaemonSet"
      "Job"
      "CronJob"
      "Namespace"
    ];
    phase = [ "Pending" "Running" "Succeeded" "Failed" "Unknown" "Completed" ];
  };

  # default namespace for operators
  defaultNamespace = "opendesk";

  # default operator labels
  defaultLabels = {
    "app.kubernetes.io/part-of" = "opendesk";
    "opendesk.io/operator" = "true";
  };

}
