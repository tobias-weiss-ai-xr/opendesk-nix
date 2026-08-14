#!/bin/bash
# Kyverno Webhook TLS Certificate Generator
#
# This script generates TLS certificates for Kyverno webhook communication
# to ensure encrypted and authenticated webhook connections.
#
# Usage: ./generate-tls-certificates.sh [OPTIONS]
#
# Options:
#   --ca-only        Generate CA certificate only
#   --server         Generate server certificate for Kyverno
#   --client         Generate client certificate for admission
#   --all            Generate all certificates (default)
#   --days           Certificate validity in days (default: 3650)
#   --output-dir     Output directory (default: ./certs)
#   --help           Show this help message
#
# Example:
#   ./generate-tls-certificates.sh --all --days 365

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Default values
VALIDITY_DAYS=3650
OUTPUT_DIR="./certs"
GENERATE_CA=true
GENERATE_SERVER=true
GENERATE_CLIENT=true

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
}

# Show usage
usage() {
    cat <<EOF
Kyverno Webhook TLS Certificate Generator

Usage: $0 [OPTIONS]

Options:
  --ca-only        Generate CA certificate only
  --server         Generate server certificate for Kyverno
  --client         Generate client certificate for admission
  --all            Generate all certificates (default)
  --days           Certificate validity in days (default: 3650)
  --output-dir     Output directory (default: ./certs)
  --help           Show this help message

Example:
  $0 --all --days 365
  $0 --server --output-dir /etc/kyverno/certs

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
    --ca-only)
        GENERATE_SERVER=false
        GENERATE_CLIENT=false
        shift
        ;;
    --server)
        GENERATE_CA=false
        GENERATE_CLIENT=false
        shift
        ;;
    --client)
        GENERATE_CA=false
        GENERATE_SERVER=false
        shift
        ;;
    --all)
        GENERATE_CA=true
        GENERATE_SERVER=true
        GENERATE_CLIENT=true
        shift
        ;;
    --days)
        VALIDITY_DAYS="$2"
        shift 2
        ;;
    --output-dir)
        OUTPUT_DIR="$2"
        shift 2
        ;;
    --help)
        usage
        exit 0
        ;;
    *)
        echo "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
done

# Create output directory
mkdir -p "$OUTPUT_DIR"

log "INFO" "Generating TLS certificates"
log "INFO" "Output directory: $OUTPUT_DIR"
log "INFO" "Validity: $VALIDITY_DAYS days"

# ============================================================================
# Generate CA Certificate
# ============================================================================

if [ "$GENERATE_CA" = true ]; then
    log "INFO" "=== Generating CA Certificate ==="

    # Generate CA private key
    log "INFO" "Generating CA private key..."
    openssl genrsa -out "$OUTPUT_DIR/ca.key" 4096
    chmod 600 "$OUTPUT_DIR/ca.key"

    # Generate CA certificate
    log "INFO" "Generating CA certificate..."
    openssl req -x509 -new -nodes -key "$OUTPUT_DIR/ca.key" \
        -sha256 -days "$VALIDITY_DAYS" \
        -subj "/C=DE/ST=Hesse/O=University Marburg/CN=opendesk-edu CA" \
        -out "$OUTPUT_DIR/ca.crt"

    log "INFO" "CA certificate generated:"
    log "INFO" "  Certificate: $OUTPUT_DIR/ca.crt"
    log "INFO" "  Private Key: $OUTPUT_DIR/ca.key"

    # Display CA certificate details
    log "INFO" "CA Certificate Details:"
    openssl x509 -in "$OUTPUT_DIR/ca.crt" -noout -subject -dates
fi

# ============================================================================
# Generate Server Certificate for Kyverno
# ============================================================================

if [ "$GENERATE_SERVER" = true ]; then
    log "INFO" "=== Generating Server Certificate ==="

    # Generate server private key
    log "INFO" "Generating server private key..."
    openssl genrsa -out "$OUTPUT_DIR/kyverno.key" 4096
    chmod 600 "$OUTPUT_DIR/kyverno.key"

    # Generate certificate signing request
    log "INFO" "Generating certificate signing request..."
    openssl req -new -key "$OUTPUT_DIR/kyverno.key" \
        -subj "/C=DE/ST=Hesse/O=University Marburg/CN=kyverno.kyverno.svc" \
        -out "$OUTPUT_DIR/kyverno.csr"

    # Create extensions file for SAN
    log "INFO" "Creating SAN extensions..."
    cat >"$OUTPUT_DIR/kyverno.ext" <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = kyverno.kyverno.svc
DNS.2 = kyverno.kyverno.svc.cluster.local
DNS.3 = kyverno.kyverno
IP.1 = 10.96.0.1
EOF

    # Sign the certificate
    log "INFO" "Signing server certificate..."
    openssl x509 -req -in "$OUTPUT_DIR/kyverno.csr" \
        -CA "$OUTPUT_DIR/ca.crt" -CAkey "$OUTPUT_DIR/ca.key" -CAcreateserial \
        -days "$VALIDITY_DAYS" -sha256 -extfile "$OUTPUT_DIR/kyverno.ext" \
        -out "$OUTPUT_DIR/kyverno.crt"

    log "INFO" "Server certificate generated:"
    log "INFO" "  Certificate: $OUTPUT_DIR/kyverno.crt"
    log "INFO" "  Private Key: $OUTPUT_DIR/kyverno.key"
    log "INFO" "  CSR: $OUTPUT_DIR/kyverno.csr"

    # Display certificate details
    log "INFO" "Server Certificate Details:"
    openssl x509 -in "$OUTPUT_DIR/kyverno.crt" -noout -subject -dates
    log "INFO" "Subject Alternative Names:"
    openssl x509 -in "$OUTPUT_DIR/kyverno.crt" -noout -text | grep -A1 "Subject Alternative Name"
fi

# ============================================================================
# Generate Client Certificate for Admission
# ============================================================================

if [ "$GENERATE_CLIENT" = true ]; then
    log "INFO" "=== Generating Client Certificate ==="

    # Generate client private key
    log "INFO" "Generating client private key..."
    openssl genrsa -out "$OUTPUT_DIR/admission-client.key" 4096
    chmod 600 "$OUTPUT_DIR/admission-client.key"

    # Generate client certificate signing request
    log "INFO" "Generating client certificate signing request..."
    openssl req -new -key "$OUTPUT_DIR/admission-client.key" \
        -subj "/C=DE/ST=Hesse/O=University Marburg/CN=kyverno-admission-client" \
        -out "$OUTPUT_DIR/admission-client.csr"

    # Sign the client certificate
    log "INFO" "Signing client certificate..."
    openssl x509 -req -in "$OUTPUT_DIR/admission-client.csr" \
        -CA "$OUTPUT_DIR/ca.crt" -CAkey "$OUTPUT_DIR/ca.key" -CAcreateserial \
        -days "$VALIDITY_DAYS" -sha256 \
        -out "$OUTPUT_DIR/admission-client.crt"

    log "INFO" "Client certificate generated:"
    log "INFO" "  Certificate: $OUTPUT_DIR/admission-client.crt"
    log "INFO" "  Private Key: $OUTPUT_DIR/admission-client.key"

    # Display certificate details
    log "INFO" "Client Certificate Details:"
    openssl x509 -in "$OUTPUT_DIR/admission-client.crt" -noout -subject -dates
fi

# ============================================================================
# Create Kubernetes Secrets
# ============================================================================

log "INFO" "=== Creating Kubernetes Secrets ==="

# Create CA bundle secret
log "INFO" "Creating CA bundle secret..."
CA_BUNDLE=$(base64 -w0 <"$OUTPUT_DIR/ca.crt")
cat >"$OUTPUT_DIR/ca-bundle-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: kyverno-ca-bundle
  namespace: kyverno
type: Opaque
data:
  ca.crt: $CA_BUNDLE
EOF

log "INFO" "CA bundle secret manifest created: $OUTPUT_DIR/ca-bundle-secret.yaml"

# Create server certificate secret
log "INFO" "Creating server certificate secret..."
KYVERNO_TLS=$(base64 -w0 <"$OUTPUT_DIR/kyverno.crt")
KYVERNO_KEY=$(base64 -w0 <"$OUTPUT_DIR/kyverno.key")
cat >"$OUTPUT_DIR/kyverno-webhook-tls-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: kyverno-webhook-tls
  namespace: kyverno
type: kubernetes.io/tls
data:
  tls.crt: $KYVERNO_TLS
  tls.key: $KYVERNO_KEY
EOF

log "INFO" "Server certificate secret manifest created: $OUTPUT_DIR/kyverno-webhook-tls-secret.yaml"

# Create client certificate secret
log "INFO" "Creating client certificate secret..."
CLIENT_CERT=$(base64 -w0 <"$OUTPUT_DIR/admission-client.crt")
CLIENT_KEY=$(base64 -w0 <"$OUTPUT_DIR/admission-client.key")
cat >"$OUTPUT_DIR/admission-client-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: kyverno-admission-client
  namespace: kyverno
type: Opaque
data:
  client.crt: $CLIENT_CERT
  client.key: $CLIENT_KEY
EOF

log "INFO" "Client certificate secret manifest created: $OUTPUT_DIR/admission-client-secret.yaml"

# ============================================================================
# Create ValidatingWebhookConfiguration
# ============================================================================

log "INFO" "=== Creating Webhook Configuration ==="

cat >"$OUTPUT_DIR/kyverno-validation-webhook.yaml" <<EOF
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: kyverno-validation-webhook
  annotations:
    cert-manager.io/inject-ca-from: kyverno/kyverno-serving-cert
webhooks:
  - name: validate.kyverno.svc
    clientConfig:
      service:
        namespace: kyverno
        name: kyverno
        path: "/validate"
      caBundle: $CA_BUNDLE
    rules:
      - apiGroups: ["*"]
        apiVersions: ["*"]
        resources: ["*"]
        excludeResourceRules:
          - apiGroups: [""]
            apiVersions: ["v1"]
            resources: ["secrets"]
    admissionReviewVersions: ["v1"]
    sideEffects: None
    timeoutSeconds: 5
    failurePolicy: Fail
    namespaceSelector:
      matchExpressions:
        - key: kyverno-exclude
          operator: DoesNotExist
EOF

log "INFO" "ValidatingWebhookConfiguration manifest created: $OUTPUT_DIR/kyverno-validation-webhook.yaml"

cat >"$OUTPUT_DIR/kyverno-mutating-webhook.yaml" <<EOF
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingWebhookConfiguration
metadata:
  name: kyverno-mutating-webhook
webhooks:
  - name: mutate.kyverno.svc
    clientConfig:
      service:
        namespace: kyverno
        name: kyverno
        path: "/mutate"
      caBundle: $CA_BUNDLE
    rules:
      - apiGroups: ["*"]
        apiVersions: ["*"]
        resources: ["*"]
        excludeResourceRules:
          - apiGroups: [""]
            apiVersions: ["v1"]
            resources: ["secrets"]
    admissionReviewVersions: ["v1"]
    sideEffects: None
    timeoutSeconds: 5
    failurePolicy: Fail
    namespaceSelector:
      matchExpressions:
        - key: kyverno-exclude
          operator: DoesNotExist
EOF

log "INFO" "MutatingWebhookConfiguration manifest created: $OUTPUT_DIR/kyverno-mutating-webhook.yaml"

# ============================================================================
# Summary
# ============================================================================

log "INFO" "=== Certificate Generation Complete ==="
log "INFO" ""
log "INFO" "Generated files in $OUTPUT_DIR:"
ls -la "$OUTPUT_DIR"
log "INFO" ""
log "INFO" "To apply to Kubernetes cluster:"
log "INFO" "  kubectl apply -f $OUTPUT_DIR/ca-bundle-secret.yaml"
log "INFO" "  kubectl apply -f $OUTPUT_DIR/kyverno-webhook-tls-secret.yaml"
log "INFO" "  kubectl apply -f $OUTPUT_DIR/admission-client-secret.yaml"
log "INFO" "  kubectl apply -f $OUTPUT_DIR/kyverno-validation-webhook.yaml"
log "INFO" "  kubectl apply -f $OUTPUT_DIR/kyverno-mutating-webhook.yaml"
log "INFO" ""
log "INFO" "To verify certificates:"
log "INFO" "  openssl x509 -in $OUTPUT_DIR/ca.crt -noout -dates"
log "INFO" "  openssl x509 -in $OUTPUT_DIR/kyverno.crt -noout -dates"
log "INFO" "  openssl x509 -in $OUTPUT_DIR/admission-client.crt -noout -dates"
log "INFO" ""
log "INFO" "Certificate expiration:"
log "INFO" "  CA: $(openssl x509 -in "$OUTPUT_DIR/ca.crt" -noout -enddate)"
log "INFO" "  Server: $(openssl x509 -in "$OUTPUT_DIR/kyverno.crt" -noout -enddate)"
log "INFO" "  Client: $(openssl x509 -in "$OUTPUT_DIR/admission-client.crt" -noout -enddate)"
