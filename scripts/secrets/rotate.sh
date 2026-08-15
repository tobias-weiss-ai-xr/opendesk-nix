#!/usr/bin/env bash
# Rotate (or set) a secret in a sops+age encrypted store for an environment.
#
# Usage: scripts/secrets/rotate.sh <env> <service> <key> [length]
#   env    : scs  -> platform/kubernetes/secrets/<env>.enc.json
#   service: opencloud
#   key    : service_account_secret
#   length : random value length (default 24)
#
# Requires the age private key in ~/.config/sops/age/keys.txt (or SOPS_AGE_KEY).
# After rotation: commit the changed .enc.json and redeploy. The real value is
# only materialized at deploy time (the nix build decrypts with SOPS_AGE_KEY).
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
ENV="${1:?usage: rotate.sh <env> <service> <key> [length]}"
SERVICE="${2:?missing <service>}"
KEY="${3:?missing <key>}"
LEN="${4:-24}"

STORE="$REPO_ROOT/platform/kubernetes/secrets/$ENV.enc.json"
[ -f "$STORE" ] || { echo "store not found: $STORE" >&2; exit 1; }

VAL="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c"$LEN")"
sops --set "[\"$SERVICE\"][\"$KEY\"] \"$VAL\"" "$STORE"
echo "Rotated $SERVICE.$KEY (len=$LEN). Commit $STORE and redeploy to apply."
