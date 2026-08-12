#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Post-build hook for automatic upload to Attic binary cache

set -euo pipefail

ATTIC_URL="${ATTIC_URL:-http://attic.local:8080}"
ATTIC_CACHE="${ATTIC_CACHE:-main}"
ATTIC_KEY="${ATTIC_KEY:-/etc/attic/signing.key}"

# Get the built path from NIX_STORE_PATH or first argument
STORE_PATH="${NIX_STORE_PATH:-$1}"

if [[ -z "$STORE_PATH" ]]; then
  echo "Error: No store path provided"
  exit 1
fi

echo "Uploading $STORE_PATH to $ATTIC_URL"

# Upload to Attic
attic upload --key "$ATTIC_KEY" "$ATTIC_CACHE" "$STORE_PATH"

echo "Upload complete"
