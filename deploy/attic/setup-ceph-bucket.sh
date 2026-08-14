#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Ceph RGW Bucket Setup for Attic Binary Cache
#
# Prerequisites:
# - Ceph RGW endpoint accessible
# - Admin credentials for Ceph
# - s3cmd or awscli installed

set -euo pipefail

# Configuration
CEPH_ENDPOINT="${CEPH_ENDPOINT:-https://rgw.scs.opendesk.hrz.uni-marburg.de}"
BUCKET_NAME="${BUCKET_NAME:-opendesk-nix-cache}"
ACCESS_KEY="${CEPH_ACCESS_KEY:-}"
SECRET_KEY="${CEPH_SECRET_KEY:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    if [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ]; then
        log_error "Ceph credentials not set!"
        log_error "Set CEPH_ACCESS_KEY and CEPH_SECRET_KEY environment variables"
        exit 1
    fi

    if ! command -v s3cmd &>/dev/null && ! command -v aws &>/dev/null; then
        log_error "Neither s3cmd nor awscli found"
        log_error "Install one of: s3cmd or awscli"
        exit 1
    fi

    log_info "Prerequisites check passed"
}

# Configure s3cmd
configure_s3cmd() {
    log_info "Configuring s3cmd..."

    cat >~/.s3cfg <<EOF
[default]
access_key = ${ACCESS_KEY}
secret_key = ${SECRET_KEY}
host_base = ${CEPH_ENDPOINT#*://}
host_bucket = %(bucket)s.${CEPH_ENDPOINT#*://}
use_https = True
ssl_verify = True
EOF

    chmod 600 ~/.s3cfg
    log_info "s3cmd configured"
}

# Create bucket
create_bucket() {
    log_info "Creating Ceph RGW bucket: ${BUCKET_NAME}..."

    if command -v s3cmd &>/dev/null; then
        if s3cmd ls "s3://${BUCKET_NAME}" &>/dev/null; then
            log_warn "Bucket ${BUCKET_NAME} already exists"
        else
            s3cmd mb "s3://${BUCKET_NAME}"
            log_info "Bucket ${BUCKET_NAME} created"
        fi
    elif command -v aws &>/dev/null; then
        if aws s3 ls "s3://${BUCKET_NAME}" 2>/dev/null; then
            log_warn "Bucket ${BUCKET_NAME} already exists"
        else
            aws s3api create-bucket --bucket "${BUCKET_NAME}" \
                --endpoint-url "${CEPH_ENDPOINT}"
            log_info "Bucket ${BUCKET_NAME} created"
        fi
    fi
}

# Set bucket lifecycle policy
set_lifecycle_policy() {
    log_info "Setting bucket lifecycle policy..."

    cat >/tmp/lifecycle-policy.json <<EOF
{
    "Rules": [
        {
            "ID": "CacheExpiration",
            "Status": "Enabled",
            "Prefix": "",
            "Expiration": {
                "Days": 90
            }
        }
    ]
}
EOF

    if command -v s3cmd &>/dev/null; then
        s3cmd set-lifecycle-policy /tmp/lifecycle-policy.json "s3://${BUCKET_NAME}"
    elif command -v aws &>/dev/null; then
        aws s3api put-bucket-lifecycle-configuration \
            --bucket "${BUCKET_NAME}" \
            --lifecycle-configuration file:///tmp/lifecycle-policy.json \
            --endpoint-url "${CEPH_ENDPOINT}"
    fi

    rm /tmp/lifecycle-policy.json
    log_info "Lifecycle policy set (90-day expiration)"
}

# Generate signing keys
generate_signing_keys() {
    log_info "Generating Attic signing keys..."

    KEYS_DIR="${KEYS_DIR:-./attic-keys}"
    mkdir -p "${KEYS_DIR}"

    # Generate private key
    if [ ! -f "${KEYS_DIR}/attic-private.key" ]; then
        attic key generate "${KEYS_DIR}/attic-private.key"
        chmod 600 "${KEYS_DIR}/attic-private.key"
        log_info "Private key generated: ${KEYS_DIR}/attic-private.key"
    else
        log_warn "Private key already exists"
    fi

    # Export public key
    attic key export "${KEYS_DIR}/attic-private.key" >"${KEYS_DIR}/attic-public.key"
    log_info "Public key exported: ${KEYS_DIR}/attic-public.key"

    # Create Kubernetes secret
    log_info "Creating Kubernetes secret for signing keys..."

    cat >"${KEYS_DIR}/attic-keys-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: attic-signing-keys
  namespace: attic-server
type: Opaque
stringData:
  private.key: |
$(cat "${KEYS_DIR}/attic-private.key" | sed 's/^/    /')
  public.key: |
$(cat "${KEYS_DIR}/attic-public.key" | sed 's/^/    /')
EOF

    log_info "Kubernetes secret template created: ${KEYS_DIR}/attic-keys-secret.yaml"
}

# Configure client substituters
configure_clients() {
    log_info "Generating client configuration..."

    cat >./attic-client-config.nix <<EOF
# Attic Binary Cache Client Configuration
# Add this to your NixOS configuration:

{
  nix.settings = {
    substituters = [
      "https://attic.scs.opendesk-edu.org"
      \${config.nix.settings.substituters or []}
    ];
    trusted-public-keys = [
      "attic.scs.opendesk-edu.org:\$(cat ./attic-keys/attic-public.key)"
    ];
  };
}
EOF

    log_info "Client configuration generated: ./attic-client-config.nix"
}

# Verify setup
verify_setup() {
    log_info "Verifying setup..."

    # Test bucket access
    if command -v s3cmd &>/dev/null; then
        if s3cmd ls "s3://${BUCKET_NAME}" &>/dev/null; then
            log_info "✓ Bucket access verified"
        else
            log_error "✗ Bucket access failed"
            exit 1
        fi
    fi

    # Check key files
    if [ -f "${KEYS_DIR}/attic-private.key" ] && [ -f "${KEYS_DIR}/attic-public.key" ]; then
        log_info "✓ Signing keys present"
    else
        log_error "✗ Signing keys missing"
        exit 1
    fi

    log_info "Setup verification complete"
}

# Main
main() {
    log_info "=========================================="
    log_info "Ceph RGW Bucket Setup for Attic"
    log_info "=========================================="
    log_info ""

    check_prerequisites
    configure_s3cmd
    create_bucket
    set_lifecycle_policy
    generate_signing_keys
    configure_clients
    verify_setup

    log_info ""
    log_info "=========================================="
    log_info "Setup Complete!"
    log_info "=========================================="
    log_info ""
    log_info "Next steps:"
    log_info "1. Review and apply Kubernetes secret: kubectl apply -f ${KEYS_DIR}/attic-keys-secret.yaml"
    log_info "2. Deploy Attic server: kubectl apply -f deploy/attic/attic-server-deployment.yaml"
    log_info "3. Configure clients with public key: ./attic-keys/attic-public.key"
    log_info "4. Test binary cache: nix build .# --option substituters 'https://attic.scs.opendesk-edu.org'"
    log_info ""
}

main "$@"
