#!/bin/bash
# Emergency Policy Disable Script for Kyverno
#
# This script provides emergency bypass mechanisms for Kyverno policies
# when they block critical operations.
#
# Usage: ./emergency-policy-disable.sh [LEVEL] [POLICY_NAME] [NAMESPACE]
#
# Levels:
#   L1 - Set specific policy to audit mode (1 hour response)
#   L2 - Disable policy in specific namespace (30 minute response)
#   L3 - Bypass Kyverno webhook entirely (15 minute response)
#   L4 - Re-enable all policies (immediate)
#
# WARNING: Use only in emergency situations!
# All actions are logged for audit purposes.

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[$timestamp] [INFO]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[$timestamp] [WARN]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[$timestamp] [ERROR]${NC} $message"
            ;;
    esac
    
    # Log to file for audit
    echo "[$timestamp] [$level] $message" >> /var/log/kyverno-emergency.log 2>/dev/null || true
}

# Check prerequisites
check_prerequisites() {
    if ! command -v kubectl &> /dev/null; then
        log "ERROR" "kubectl is not installed"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        log "ERROR" "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    log "INFO" "Prerequisites check passed"
}

# Level 1: Set specific policy to audit mode
level1_audit_mode() {
    local policy_name=$1
    
    if [ -z "$policy_name" ]; then
        log "ERROR" "Policy name required for Level 1"
        echo "Usage: $0 L1 <POLICY_NAME>"
        exit 1
    fi
    
    log "INFO" "Level 1: Setting policy '$policy_name' to audit mode"
    
    # Check if it's a ClusterPolicy or Policy
    if kubectl get clusterpolicy "$policy_name" &> /dev/null; then
        kubectl patch clusterpolicy "$policy_name" \
            -p '{"spec":{"validationFailureAction":"audit"}}'
        log "INFO" "ClusterPolicy '$policy_name' set to audit mode"
    elif kubectl get policy -A -o name | grep -q "$policy_name"; then
        local ns=$(kubectl get policy -A -o name | grep "$policy_name" | cut -d'/' -f1)
        kubectl patch policy "$policy_name" \
            -n "$ns" \
            -p '{"spec":{"validationFailureAction":"audit"}}'
        log "INFO" "Policy '$policy_name' in namespace '$ns' set to audit mode"
    else
        log "ERROR" "Policy '$policy_name' not found"
        exit 1
    fi
    
    log "INFO" "Level 1 action completed successfully"
    log "INFO" "Remember to re-enable enforcement after issue is resolved:"
    echo "  kubectl patch clusterpolicy $policy_name -p '{\"spec\":{\"validationFailureAction\":\"enforce\"}}'"
}

# Level 2: Disable policy in specific namespace
level2_namespace_exclude() {
    local namespace=$1
    
    if [ -z "$namespace" ]; then
        log "ERROR" "Namespace required for Level 2"
        echo "Usage: $0 L2 <NAMESPACE>"
        exit 1
    fi
    
    log "WARN" "Level 2: Excluding namespace '$namespace' from Kyverno policies"
    
    # Label namespace to exclude from Kyverno
    kubectl label namespace "$namespace" kyverno-exclude=true --overwrite
    
    log "INFO" "Namespace '$namespace' labeled with kyverno-exclude=true"
    log "INFO" "This namespace is now excluded from all Kyverno policies"
    log "INFO" "Remember to re-enable after issue is resolved:"
    echo "  kubectl label namespace $namespace kyverno-exclude-"
}

# Level 3: Bypass Kyverno webhook (EMERGENCY ONLY)
level3_webhook_bypass() {
    log "ERROR" "Level 3: BYPASSING KYVERNO WEBHOOK - EMERGENCY ONLY"
    log "ERROR" "This action disables ALL Kyverno policy enforcement"
    
    read -p "Are you sure you want to bypass the Kyverno webhook? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log "INFO" "Action cancelled by user"
        exit 0
    fi
    
    log "WARN" "Bypassing Kyverno webhook..."
    
    # Patch webhook failure policy to Ignore
    kubectl patch validatingwebhookconfiguration kyverno-validation-webhook \
        --type='json' \
        -p='[{"op": "replace", "path": "/webhooks/0/failurePolicy", "value":"Ignore"}]'
    
    kubectl patch mutatingwebhookconfiguration kyverno-mutating-webhook \
        --type='json' \
        -p='[{"op": "replace", "path": "/webhooks/0/failurePolicy", "value":"Ignore"}]'
    
    log "INFO" "Kyverno webhook failure policy set to 'Ignore'"
    log "INFO" "All deployments can now proceed without Kyverno validation"
    log "INFO" "CRITICAL: Re-enable immediately after emergency is resolved!"
    log "INFO" "Use Level 4 to re-enable:"
    echo "  $0 L4"
}

# Level 4: Re-enable all policies
level4_reenable() {
    log "INFO" "Level 4: Re-enabling all Kyverno policies"
    
    # Re-enable webhook failure policy
    kubectl patch validatingwebhookconfiguration kyverno-validation-webhook \
        --type='json' \
        -p='[{"op": "replace", "path": "/webhooks/0/failurePolicy", "value":"Fail"}]'
    
    kubectl patch mutatingwebhookconfiguration kyverno-mutating-webhook \
        --type='json' \
        -p='[{"op": "replace", "path": "/webhooks/0/failurePolicy", "value":"Fail"}]'
    
    # Remove namespace exclusion labels
    for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
        if kubectl get namespace "$ns" -o jsonpath='{.metadata.labels.kyverno-exclude}' 2>/dev/null | grep -q "true"; then
            kubectl label namespace "$ns" kyverno-exclude-
            log "INFO" "Removed kyverno-exclude label from namespace '$ns'"
        fi
    done
    
    log "INFO" "All Kyverno policies re-enabled"
    log "INFO" "Webhook failure policy set to 'Fail'"
    log "INFO" "Namespace exclusions removed"
    
    # Verify
    log "INFO" "Verifying re-enablement..."
    kubectl get validatingwebhookconfiguration kyverno-validation-webhook \
        -o jsonpath='{"Webhook Failure Policy: "}{.webhooks[0].failurePolicy}'
    echo
    kubectl get mutatingwebhookconfiguration kyverno-mutating-webhook \
        -o jsonpath='{"Webhook Failure Policy: "}{.webhooks[0].failurePolicy}'
    echo
}

# Show status
show_status() {
    log "INFO" "Current Kyverno Status"
    echo "================================"
    
    # Check webhook configuration
    echo -e "\nWebhook Failure Policies:"
    kubectl get validatingwebhookconfiguration kyverno-validation-webhook \
        -o jsonpath='{"  Validating: "}{.webhooks[0].failurePolicy}' 2>/dev/null || echo "  Validating: Not found"
    echo
    kubectl get mutatingwebhookconfiguration kyverno-mutating-webhook \
        -o jsonpath='{"  Mutating: "}{.webhooks[0].failurePolicy}' 2>/dev/null || echo "  Mutating: Not found"
    echo
    
    # Check excluded namespaces
    echo -e "\nExcluded Namespaces:"
    excluded=$(kubectl get namespaces -o jsonpath='{range .items[*]}{.metadata.name}{"="}{.metadata.labels.kyverno-exclude}{"\n"}{end}' 2>/dev/null | grep "true")
    if [ -n "$excluded" ]; then
        echo "$excluded" | while read line; do
            echo "  $line"
        done
    else
        echo "  None"
    fi
    
    # Check policies in audit mode
    echo -e "\nPolicies in Audit Mode:"
    audit_policies=$(kubectl get clusterpolicies -o jsonpath='{range .items[*]}{.metadata.name}{"="}{.spec.validationFailureAction}{"\n"}{end}' 2>/dev/null | grep "audit")
    if [ -n "$audit_policies" ]; then
        echo "$audit_policies" | while read line; do
            echo "  $line"
        done
    else
        echo "  None"
    fi
    
    echo "================================"
}

# Print usage
usage() {
    echo "Kyverno Emergency Policy Disable Script"
    echo ""
    echo "Usage: $0 <LEVEL> [OPTIONS]"
    echo ""
    echo "Levels:"
    echo "  L1 <POLICY_NAME>  - Set specific policy to audit mode (1 hour response)"
    echo "  L2 <NAMESPACE>    - Disable policy in specific namespace (30 minute response)"
    echo "  L3                - Bypass Kyverno webhook entirely (15 minute response)"
    echo "  L4                - Re-enable all policies (immediate)"
    echo "  STATUS            - Show current Kyverno status"
    echo "  HELP              - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 L1 verify-images        # Set 'verify-images' policy to audit mode"
    echo "  $0 L2 opendesk             # Exclude 'opendesk' namespace from policies"
    echo "  $0 L3                      # Emergency webhook bypass (confirm required)"
    echo "  $0 L4                      # Re-enable all policies"
    echo "  $0 STATUS                  # Show current status"
    echo ""
    echo "WARNING: Use only in emergency situations!"
    echo "All actions are logged for audit purposes."
}

# Main
main() {
    check_prerequisites
    
    case $1 in
        L1)
            level1_audit_mode "$2"
            ;;
        L2)
            level2_namespace_exclude "$2"
            ;;
        L3)
            level3_webhook_bypass
            ;;
        L4)
            level4_reenable
            ;;
        STATUS)
            show_status
            ;;
        HELP|--help|-h)
            usage
            ;;
        *)
            echo "Error: Unknown command '$1'"
            echo ""
            usage
            exit 1
            ;;
    esac
}

main "$@"
