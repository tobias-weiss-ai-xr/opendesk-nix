#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# CI gate: OpenDesk Kubernetes regression checks.
#
# Encodes the operational invariants that were violated during the
# 2026-09-05/06 outage (portal login 500 + XWiki 503):
#
#   1. DNS must not be blocked by egress NetworkPolicies.
#      A NetworkPolicy with `policyTypes` containing "Egress" but NO egress
#      rules means "deny ALL egress for matched pods" - including UDP/TCP 53
#      (kube-dns). The `lib.networkPolicy` helper in platform/nix/k8s.nix
#      DEFAULTS policyTypes to [ "Ingress" "Egress" ], so a caller that omits
#      `policyTypes` or omits egress DNS rules silently cuts DNS for the whole
#      selected pod set. This was the root cause of Keycloak's
#      `UnknownHostException: mariadb-galera...svc.cluster.local` and the ->
#      portal login 500s.
#
#   2. Ingress host claims must be unique across namespaces/services.
#      Two Ingress objects claiming the same host in different namespaces made
#      HAProxy pick the broken (all-servers-disabled) backend -> XWiki 503
#      "Service Unavailable".
#
#   3. KC_DB / KC_DB_URL must stay coherent in keycloak.nix.
#      KC_DB must be exactly "mariadb"; KC_DB_URL must be built from
#      ${db.host}:${db.port} (single source of truth) and must NOT reference a
#      cross-namespace ExternalName that resolves to raw pod IPs.
#
# Usage:
#   scripts/ci/check-opendesk-regressions.sh [services-dir]
#     services-dir  defaults to platform/kubernetes/services
#
# Exit 0 on success; exit 1 with a listing of every violated invariant.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVICES_DIR="${1:-$ROOT/platform/kubernetes/services}"
K8S_LIB="$ROOT/platform/nix/k8s.nix"
fail=0

say() { printf '  %s\n' "$*"; }
fail_line() { printf '    - %s\n' "$*"; }

echo "OpenDesk Kubernetes regression checks"
echo "  services dir: $SERVICES_DIR"
echo ""

# =============================================================================
# 1. Egress NetworkPolicy must not silently deny DNS
# =============================================================================
echo "[1] Egress NetworkPolicy DNS-safety"

# 1a. Every `lib.networkPolicy { ... }` call that relies on the library default
#     policyTypes = ["Ingress" "Egress"] without stating a policyTypes is a
#     deny-all-egress footgun: an eventual egress-less or DNS-less NetPol.
#     We can't easily parse nested Nix, so we enforce the conservative rule:
#     every networkPolicy call site must explicitly set `policyTypes`.
for f in $(grep -rln 'networkPolicy {' "$SERVICES_DIR" 2>/dev/null || true); do
  # Iterate EVERY call site in the file, not just the first one.
  awk -v file="$f" '
    /networkPolicy {/ { inpol=1; depth=0 }
    inpol {
      depth += gsub(/\(/, "(")
      depth -= gsub(/\)/, ")")
      if (depth <= 0 && NR > 0) {
        has=has || /policyTypes/
        if (!has) print file ":" NR ": networkPolicy call omits explicit policyTypes (library default = Ingress+Egress deny-all-egress)"
        inpol=0; has=0; depth=0
      }
      has = has || /policyTypes/
    }
  ' "$f" || true
  # The awk above may not close cleanly if parens span lines unevenly; fall
  # back to a robust per-block scan with a bracket counter.
  off=$(grep -n 'networkPolicy {' "$f" | head -1 | cut -d: -f1)
  [ -z "$off" ] && continue
  block="$(sed -n "${off},\$p" "$f")"
  # Walk blocks by tracking open/close parens per call.
  awk -v file="$f" -v start="$off" '
    NR >= start {
      block=block "\n" $0
      opens += gsub(/\(/, "(")
      closes += gsub(/\)/, ")")
      if (opens > 0 && closes >= opens && index(block, "networkPolicy {")) {
        if (index(block, "policyTypes") == 0) {
          print file ": scope-start ~" NR ": omits explicit policyTypes"
        }
        block=""; opens=0; closes=0
      }
    }
  ' "$f" || true
done | sort -u | while IFS= read -r line; do
  [ -z "$line" ] && continue
  fail=$((fail+1))
  fail_line "$line"
done

# 1b. Any NetPol declaring egress RULES for a BROAD pod selector must still let
#     DNS through (port 53) - otherwise the whole namespace loses resolution.
for f in $(grep -rln 'egress =' "$SERVICES_DIR" 2>/dev/null || true); do
  [ -f "$f" ] || continue
  # Must reference DNS port 53 somewhere, or it blocks cluster DNS.
  if ! grep -qE 'port[[:space:]]*=[[:space:]]*53' "$f"; then
    fail=$((fail+1))
    fail_line "$f: egress rules declared but no DNS (port 53) rule - will block cluster DNS"
  fi
done
[ "$fail" -eq 0 ] && say "OK: no DNS-blocking egress NetworkPolicy"

# =============================================================================
# 2. Ingress host claims must be unique
# =============================================================================
echo "[2] Ingress host uniqueness (XWiki 503 duplicate-host regression)"
dup=$(grep -rhoE 'host = "[^"]+"' "$SERVICES_DIR" 2>/dev/null | sort | uniq -d || true)
if [ -n "$dup" ]; then
  fail=$((fail+1))
  fail_line "duplicate ingress host claim(s):"
  printf '%s\n' "$dup" | while IFS= read -r h; do [ -n "$h" ] && printf '      %s\n' "$h"; done
else
  say "OK: all ingress host claims are unique"
fi

# =============================================================================
# 3. Keycloak DB config coherence (portal login 500 regression)
# =============================================================================
echo "[3] Keycloak KC_DB / KC_DB_URL coherence"
KC="$SERVICES_DIR/keycloak.nix"
if [ -f "$KC" ]; then
  kc_db="$(grep -m1 -A1 'name = "KC_DB"' "$KC" | grep 'value' | grep -oE '"[^"]*"' | tr -d '"' || true)"
  kc_url="$(grep -m1 -A1 'name = "KC_DB_URL"' "$KC" | grep 'value' | grep -oE '"[^"]*"' | tr -d '"' || true)"
  [ "$kc_db" = "mariadb" ] || { fail=$((fail+1)); fail_line "KC_DB should be exactly \"mariadb\" (got: ${kc_db:-<missing>})"; }
  if [ -n "$kc_url" ]; then
    if printf '%s' "$kc_url" | grep -q '\${db.host}'; then
      :  # correct: built from db.* single source of truth
    else
      fail=$((fail+1))
      fail_line "KC_DB_URL should be built from \${db.host}/\${db.port} (got: $kc_url)"
    fi
  fi
  # ExternalName-to-pod-IP for cross-namespace DB is not allowed (breaks when
  # inter-node pod routing is degraded). host must be same-namespace service.
  if grep -q "galera-headless" "$KC"; then
    fail=$((fail+1))
    fail_line "keycloak.nix must not use galera-headless (ExternalName -> raw pod IPs); use ClusterIP service mariadb-galera.opendesk-edu.svc.cluster.local"
  fi
  [ "$fail" -eq 0 ] && say "OK: KC_DB=$kc_db, KC_DB_URL=built-from-db-host"
else
  say "SKIP: $KC not found"
fi

# =============================================================================
# 4. No hardcoded pod IPs (ClusterIP service names are the only address truth)
# =============================================================================
echo "[4] Hardcoded pod IP literals"
# Cross-namespace DB access must go through ClusterIP services
# (mariadb-galera.opendesk-edu.svc.cluster.local:3306 -> ClusterIP), NEVER a
# raw pod IP. Raw pod IPs break when inter-node routing degrades (2026-09-05:
# flannel routes broken -> only ClusterIP-via-iptables kept working). The
# cluster pod CIDR is 172.17.128.0/18 on this platform.
bad_ips=$(grep -rnE '172\.17\.(12[8-9]|1[3-9][0-9]|19[0-1])\.' "$SERVICES_DIR" 2>/dev/null \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)   # ignore full-line comments
if [ -n "$bad_ips" ]; then
  fail=$((fail+1))
  fail_line "hardcoded pod IP literal(s) - use ClusterIP service names instead:"
  printf '%s\n' "$bad_ips" | while IFS= read -r l; do [ -n "$l" ] && printf '      %s\n' "$l"; done
else
  say "OK: no hardcoded pod IP literals"
fi

# =============================================================================
# 5. No nodeSelector pinning (temporary outage workaround must not persist)
# =============================================================================
echo "[5] nodeSelector pinning"
# 2026-09-05: Keycloak was temporarily pinned to clrz14-06 to dodge broken
# pod routing. That pin must NOT survive in declarative config - node affinity
# is a cluster-topology concern, not an app property.
bad_ns=$(grep -rl 'nodeSelector' "$SERVICES_DIR" 2>/dev/null || true)
# nix-builder intentionally schedules on a specific builder node for image
# caching; exclude it.
allowed="nix-builder.nix"
found=0
for f in $bad_ns; do
  base=$(basename "$f")
  case " $allowed " in
    *" $base "*) continue ;;
  esac
  found=$((found+1))
  fail=$((fail+1))
  fail_line "$f: nodeSelector present - temporary outage pin must not be in config"
done
[ "$found" -eq 0 ] && say "OK: no stray nodeSelector (except nix-builder image-cache pin)"

if [ "$fail" -gt 0 ]; then
  echo ""
  echo "FAILED: $fail invariant violation(s) (see above)."
  exit 1
fi
echo ""
echo "All OpenDesk Kubernetes regression checks passed."
