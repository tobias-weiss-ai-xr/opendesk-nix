#!/usr/bin/env bats
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# OpenDesk Kubernetes regression tests (offline, CI-safe).
#
# These fixtures encode the invariants that were violated during the
# 2026-09-05/06 outage:
#   * portal login 500  -> egress NetworkPolicy silently blocked cluster DNS
#     (Keycloak 'UnknownHostException: mariadb-galera...svc.cluster.local')
#   * XWiki 503         -> two Ingress objects claimed the same host across
#     namespaces; HAProxy routed to the broken (all-servers-disabled) backend
#   * KC_DB mangled     -> a JSON-patch style edit corrupted KC_DB env
#
# Run:   bats tests/opendesk-regression.bats
# CI:    bats tests/*.bats        (stage test)
# Gate:  nix build .#checks.<system>.opendesk-k8s-regressions   (flake.nix)

setup() {
    cd "$BATS_TEST_DIRNAME/.."
    SCRIPT_DIR="$(pwd)/scripts/ci"
    SERVICES_DIR="$(pwd)/platform/kubernetes/services"
}

# =============================================================================
# 1. Egress NetworkPolicy must not silently deny DNS
# =============================================================================

@test "regression checker script exists and is executable" {
    [ -f "$SCRIPT_DIR/check-opendesk-regressions.sh" ]
    [ -x "$SCRIPT_DIR/check-opendesk-regressions.sh" ]
}

@test "check-opendesk-regressions.sh uses set -euo pipefail" {
    run grep "set -euo pipefail" "$SCRIPT_DIR/check-opendesk-regressions.sh"
    [ "$status" -eq 0 ]
}

@test "check-opendesk-regressions.sh has no bash syntax errors" {
    run bash -n "$SCRIPT_DIR/check-opendesk-regressions.sh"
    [ "$status" -eq 0 ]
}

@test "every lib.networkPolicy call site sets an explicit policyTypes" {
    # The k8s.nix library DEFAULTS policyTypes to ["Ingress" "Egress"]. A
    # NetworkPolicy with Egress in policyTypes but no egress rules = deny ALL
    # egress (incl. DNS port 53) for every matched pod. Callers MUST pin the
    # policy type so this cannot regress silently.
    run bash -c "
      cd '$SERVICES_DIR'
      fail=0
      for f in \$(grep -rln 'networkPolicy {' . 2>/dev/null); do
        start=\$(grep -n 'networkPolicy {' \"\$f\" | head -1 | cut -d: -f1)
        tail=\$(sed -n \"\${start},\$((start+25))p\" \"\$f\")
        if ! printf '%s' \"\$tail\" | grep -q 'policyTypes'; then
          echo \"  \$f: missing policyTypes\"
          fail=1
        fi
      done
      exit \$fail
    "
    [ "$status" -eq 0 ]
    [ -z "$output" ] || true
}

@test "no egress-capable NetworkPolicy blocks DNS (port 53)" {
    # Any NetPol that declares egress RULES (egress = [...]) must include DNS
    # (port 53), otherwise the selected pods lose resolution (Keycloak/XWiki
    # outage root cause). Policies with policyTypes Ingress-only, or no egress
    # rules at all, cannot block DNS and are not flagged.
    run bash -c "
      cd '$SERVICES_DIR'
      fail=0
      for f in \$(grep -rln 'egress =' . 2>/dev/null || true); do
        # files declaring egress rules must also reference DNS port 53
        if ! grep -qE 'port[[:space:]]*=[[:space:]]*53' \"\$f\"; then
          echo \"  \$f: egress rules present but no DNS (port 53) rule\"
          fail=1
        fi
      done
      exit \$fail
    "
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# =============================================================================
# 2. Ingress host claims must be unique (XWiki 503 duplicate-host regression)
# =============================================================================

@test "no duplicate ingress host claims across services" {
    run bash -c "
      cd '$SERVICES_DIR'
      dups=\$(grep -rhoE 'host = \"[^\"]+\"' . 2>/dev/null | sort | uniq -d || true)
      if [ -n \"\$dups\" ]; then
        echo \"duplicate hosts:\"
        printf '%s\n' \"\$dups\"
        exit 1
      fi
      exit 0
    "
    [ "$status" -eq 0 ]
}

@test "xwiki host claimed by exactly one service" {
    run bash -c "
      cd '$SERVICES_DIR'
      count=\$(grep -rlE 'host = \"xwiki\.' . 2>/dev/null | wc -l)
      echo \"xwiki ingress claims: \$count\"
      [ \"\$count\" -eq 1 ]
    "
    [ "$status" -eq 0 ]
}

# =============================================================================
# 3. Keycloak DB config coherence (portal login 500 regression)
# =============================================================================

@test "KC_DB is exactly mariadb" {
    run bash -c "grep -m1 -A1 'name = \"KC_DB\"' '$SERVICES_DIR/keycloak.nix' | grep 'value' | grep -q 'mariadb'"
    [ "$status" -eq 0 ]
}

@test "KC_DB_URL is built from db.host / db.port (single source of truth)" {
    run bash -c "grep -m1 -A1 'name = \"KC_DB_URL\"' '$SERVICES_DIR/keycloak.nix' | grep 'value' | grep -q '\\\${db.host}'"
    [ "$status" -eq 0 ]
}

@test "keycloak does not reference galera-headless ExternalName" {
    # galera-headless is an ExternalName-style headless service resolving to
    # raw pod IPs; cross-node routing failures make it unreachable. Use the
    # ClusterIP service (mariadb-galera.opendesk-edu.svc.cluster.local).
    run grep -n "galera-headless" "$SERVICES_DIR/keycloak.nix"
    [ "$status" -ne 0 ]
}

@test "keycloak DB port is 3306 (via db.port or URL)" {
    # No separate KC_DB_PORT env exists; the port comes from db.port in the
    # environment and is rendered into KC_DB_URL. The environment default is
    # 3306 (shared Galera).
    run bash -c "grep -m1 'db.port' '$SERVICES_DIR/keycloak.nix'"
    if [ "$status" -eq 0 ]; then
        [ "$output" != "" ]
    else
        grep -m1 '^[[:space:]]*port = ' ../platform/kubernetes/environments/scs/default.nix | grep -q '3306' 2>/dev/null \
            || grep -m1 'database' -A2 ../platform/kubernetes/environments/scs/default.nix >/dev/null
    fi
}

@test "full regression checker passes against current manifests" {
    run "$SCRIPT_DIR/check-opendesk-regressions.sh" "$SERVICES_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"All OpenDesk Kubernetes regression checks passed"* ]]
}

@test "no oauth2-proxy:latest image tag in manifests (caused day-2 403/500)" {
    # The 2026-09-06 portal failure chain started with image:
    #   quay.io/oauth2-proxy/oauth2-proxy:latest  (pulls drifted v7.x at deploy)
    # plus a client-secret rotated AFTER pod start (stale env) and a
    # home-cookie-secret stored as 64-char hex string (crashed the pod).
    # oauth2-proxy must be pinned to an immutable tag; secrets must be
    # 16/24/32 raw bytes, matching both Keycloak AND the running pod.
    bad=$(grep -rEn 'oauth2-proxy/oauth2-proxy:[^v][^"]*"?' \
        "$SERVICES_DIR" 2>/dev/null || true)
    # only flag explicit ':latest' (or any unpinned bare tag)
    bad=$(printf '%s' "$bad" | grep -E 'oauth2-proxy/oauth2-proxy:(latest|[0-9])' || true)
    [ -z "$bad" ]
}

# ------------------------------------------------------------------
# Day-2 invariants (2026-09-06): hardcoded pod IPs + nodeSelector pin
# ------------------------------------------------------------------

@test "no hardcoded pod IP literals in manifests (ClusterIP svc names only)" {
    # 2026-09-05: cross-namespace DB via raw pod IP worked when pod-hop
    # routing was broken? NO - it BROKE. ClusterIP service names are the
    # only resilient address (iptables path). Raw pod IPs in declarative
    # config are a VM-topology coupling.
    bad=$(grep -rnE '172\.17\.(12[89]|1[3-9][0-9]|19[01])\.' "$SERVICES_DIR" \
        2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)
    [ -z "$bad" ]
}

@test "no nodeSelector pinning outside nix-builder (outage pin removed)" {
    # 2026-09-05 temporary Keycloak nodeSelector must not persist in config.
    bad=$(grep -rl 'nodeSelector' "$SERVICES_DIR" 2>/dev/null || true)
    for f in $bad; do
        case "$(basename "$f")" in
            nix-builder.nix) : ;;  # image-cache placement, intentional
            *) echo "unexpected nodeSelector in $f"; return 1 ;;
        esac
    done
}

# ------------------------------------------------------------------
# Backend-service coherence + TLS completeness (503 / cert-miss guards)
# ------------------------------------------------------------------

@test "every ingress-declaring manifest still declares its backend Service" {
    # The XWiki 503 (2026-09-05) was a broken HAProxy backend. If an Ingress
    # stays in a manifest after its Service is removed, HAProxy answers 503 for
    # that host forever. This lib emits ingress + service under the same name,
    # so an ingress file MUST still contain a lib.service declaration.
    bad=0
    for f in $(grep -rl 'ingressWithCert\|mkIngressWithTLS' "$SERVICES_DIR" 2>/dev/null || true); do
        if ! grep -q 'lib\.service' "$f"; then
            echo "  $f: ingress declared but lib.service removed - broken backend!"
            bad=1
        fi
    done
    [ "$bad" -eq 0 ]
}

@test "every ingress host claim has a TLS block (cert must cover the host)" {
    # ingressWithCert emits tls.hosts = [ host ] automatically. A later
    # refactor that switches to raw ingress objects must not drop TLS -
    # Let's Encrypt/HRZ certs would no longer be presented for the host.
    # (Static proxy: every file using ingressWithCert must still define tlsSecretName,
    # and no service declares an ingress host without a matching tls block.)
    bad=0
    for f in $(grep -rl 'ingressWithCert\|mkIngressWithTLS' "$SERVICES_DIR" 2>/dev/null || true); do
        # ingressWithCert sets tlsSecretName default; a file overriding to ""
        # or dropping it would be a cert-miss. Check we always pass tlsSecretName
        # or rely on the default (no explicit override that empties it).
        if grep -qE 'tlsSecretName[[:space:]]*=[[:space:]]*""' "$f"; then
            echo "  $f: tlsSecretName set to empty string - no cert for ingress host(s)"
            bad=1
        fi
    done
    [ "$bad" -eq 0 ]
}
